// Copyright (c) 2019-2024 Andreas T Jonsson <mail@andreasjonsson.se>
//
// This software is provided 'as-is', without any express or implied
// warranty. In no event will the authors be held liable for any damages
// arising from the use of this software.
//
// Permission is granted to anyone to use this software for any purpose,
// including commercial applications, and to alter it and redistribute it
// freely, subject to the following restrictions:
//
// 1. The origin of this software must not be misrepresented; you must not
//    claim that you wrote the original software. If you use this software
//    in a product, an acknowledgment in the product documentation would be
//    appreciated but is not required.
//
// 2. Altered source versions must be plainly marked as such, and must not be
//    misrepresented as being the original software.
//
// 3. This notice may not be removed or altered from any source
//    distribution.

#include "emuloop.h"

#define SYSTEM_STEPS 1
#define GET_TICKS ( CTimer::GetClockTicks64() * (vxt_system_frequency(m_pSystem) / 1000000) )

#ifndef ARM_ALLOW_MULTI_CORE
	#error You need to enable multicore support!
#endif

CSpinLock CEmuLoop::s_SpinLock(TASK_LEVEL);
CBcmFrameBuffer *CEmuLoop::s_pFrameBuffer(0);

int screen_width = 0;
int screen_height = 0;

extern "C" int render_callback(int width, int height, const vxt_byte *rgba, void *userdata) {
	if ((width != screen_width) || (height != screen_height) || !CEmuLoop::s_pFrameBuffer) {
		screen_width = width;
		screen_height = height;

		if (CEmuLoop::s_pFrameBuffer)
			delete CEmuLoop::s_pFrameBuffer;

		CEmuLoop::s_pFrameBuffer = new CBcmFrameBuffer((unsigned)width, (unsigned)height, 32);

		if (!CEmuLoop::s_pFrameBuffer->Initialize()) {
			VXT_LOG("Could not set correct ressolution. Fallback to virtual resolution.");

			delete CEmuLoop::s_pFrameBuffer;
			CKernelOptions *opt = (CKernelOptions*)userdata;
			CEmuLoop::s_pFrameBuffer = new CBcmFrameBuffer(opt->GetWidth(), opt->GetHeight(), 32, (unsigned)width, (unsigned)height);

			if (!CEmuLoop::s_pFrameBuffer->Initialize()) {
				VXT_LOG("Could not initialize framebuffer!");
				delete CEmuLoop::s_pFrameBuffer;
				return -1;
			}
		}
	}

	u8 *buffer = (u8*)(u64)CEmuLoop::s_pFrameBuffer->GetBuffer();
	for (int i = 0; i < height; i++) {
		// This is probably a firmware bug!
		// The framebuffer should be 32 bit at this point.
		#if RASPPI == 5
			#define RGB555(red, green, blue) (((red) & 0x1F) << 11 | ((green) & 0x1F) << 6 | ((blue) & 0x1F))
			for (int j = 0; j < width; j++) {
				((u16*)buffer)[j] = RGB555(rgba[2] >> 3, rgba[1] >> 3, rgba[0] >> 3);
				rgba += 4;
			}
		#else
			memcpy(buffer, rgba, 4 * width);
			rgba += 4 * width;
		#endif
		buffer += CEmuLoop::s_pFrameBuffer->GetPitch();
	}
	
    return 0;
}


CEmuLoop::CEmuLoop(
	CMemorySystem *mem, CKernelOptions *opt, vxt_system *s,
	CBcmFrameBuffer *fb, struct frontend_video_adapter *va,
	CSoundBaseDevice *snd, struct frontend_audio_adapter *aa)
:
	CMultiCoreSupport(mem),
	m_pOptions(opt),
	m_pSystem(s),
	m_pVideoAdapter(va),
	m_pSound(snd),
	m_pAudioAdapter(aa),
	m_pPPI(0)
{
	assert(CLOCKHZ == 1000000);
	s_pFrameBuffer = fb;

	for (int i = 1; i < VXT_MAX_PERIPHERALS; i++) {
		struct vxt_peripheral *device = vxt_system_peripheral(s, (vxt_byte)i);
		if (device && vxt_peripheral_class(device) == VXT_PCLASS_PPI) {
			m_pPPI = device;
			break;
		}
	}
}

CEmuLoop::~CEmuLoop(void) {
	SendIPI(1, IPI_HALT_CORE); // EmuThread
	SendIPI(2, IPI_HALT_CORE); // RenderThread
	SendIPI(3, IPI_HALT_CORE); // AudioThread
}

void CEmuLoop::Lock(void) {	
	s_SpinLock.Acquire();
}

void CEmuLoop::Unlock(void) {
	s_SpinLock.Release();
}

void CEmuLoop::Run(unsigned nCore) {
	switch (nCore) {
		case 1: EmuThread(); break;
		case 2: RenderThread(); break;
		case 3: AudioThread(); break;
	}
}

void CEmuLoop::EmuThread(void) {
	VXT_LOG("Emulation thread started!");

	u64 virtual_ticks = GET_TICKS;
	
	for (u64 cpu_ticks = virtual_ticks; CKernel::Get()->m_ShutdownMode == ShutdownNone; cpu_ticks = GET_TICKS) {
		if (virtual_ticks < cpu_ticks) {
			Lock();
			struct vxt_step step = vxt_system_step(m_pSystem, vxt_system_frequency(m_pSystem) / CLOCKHZ);
			Unlock();

			if (step.err != VXT_NO_ERROR)
				VXT_LOG(vxt_error_str(step.err));
			virtual_ticks += step.cycles;
		}
	}

	VXT_LOG("Emulation thread ended!");
}

void CEmuLoop::RenderThread(void) {
	VXT_LOG("Render thread started!");

	u64 render_ticks = CTimer::GetClockTicks64();

	for (u64 ticks = render_ticks; CKernel::Get()->m_ShutdownMode == ShutdownNone; ticks = CTimer::GetClockTicks64()) {
		if ((ticks - render_ticks) >= (CLOCKHZ / 60)) {
			render_ticks = ticks;
			
			Lock();
			m_pVideoAdapter->snapshot(m_pVideoAdapter->device);
			Unlock();

		   	m_pVideoAdapter->render(m_pVideoAdapter->device, &render_callback, m_pOptions);
		}
	}

	VXT_LOG("Render thread ended!");
}

void CEmuLoop::AudioThread(void) {
	VXT_LOG("Audio thread started!");

	const unsigned audio_buffer_size = (SAMPLE_RATE / 1000) * AUDIO_LATENCY_MS;
	unsigned audio_buffer_len = 0;

	DMA_BUFFER(short, audio_buffer, audio_buffer_size);
	memset(audio_buffer, 0, audio_buffer_size * 2);
	
	u64 audio_ticks = CTimer::GetClockTicks64();

	for (u64 ticks = audio_ticks; CKernel::Get()->m_ShutdownMode == ShutdownNone; ticks = CTimer::GetClockTicks64()) {
		while ((ticks - audio_ticks) >= (CLOCKHZ / SAMPLE_RATE)) {
			audio_ticks += CLOCKHZ / SAMPLE_RATE;

			// Generate audio.
			if (audio_buffer_len < audio_buffer_size) {
				Lock();
				{
					short sample = m_pPPI ? vxtu_ppi_generate_sample(m_pPPI, SAMPLE_RATE) : 0;
					if (m_pAudioAdapter->device)
						sample += m_pAudioAdapter->generate_sample(m_pAudioAdapter->device, SAMPLE_RATE);
					audio_buffer[audio_buffer_len++] = sample;
				}
				Unlock();
			}

			// Write audio data to output device.
			if (m_pSound && m_pSound->IsActive()) {
				const unsigned samples_needed = m_pSound->GetQueueSizeFrames() - m_pSound->GetQueueFramesAvail();

				if ((audio_buffer_len == audio_buffer_size) || (samples_needed > audio_buffer_len)) {
					unsigned num_samples = (samples_needed < audio_buffer_len) ? samples_needed : audio_buffer_len;
					m_pSound->Write((u8*)audio_buffer, num_samples * 2);
					audio_buffer_len = 0;
				}
			}
		}
	}
	
	VXT_LOG("Audio thread ended!");
}
