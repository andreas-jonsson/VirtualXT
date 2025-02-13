// Copyright (c) 2019-2025 Andreas T Jonsson <mail@andreasjonsson.se>
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
#include <circle/util.h>

#ifndef ARM_ALLOW_MULTI_CORE
	#error You need to enable multicore support!
#endif

extern struct retro_frame_time_callback frame_time;

extern "C" {
	void retro_run(void);
	void retro_set_video_refresh(retro_video_refresh_t cb);
}

CSpinLock CEmuLoop::s_SpinLock(TASK_LEVEL);
CBcmFrameBuffer *CEmuLoop::s_pFrameBuffer(0);

unsigned screen_width = 0;
unsigned screen_height = 0;

extern "C" void video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
	if ((width != screen_width) || (height != screen_height) || !CEmuLoop::s_pFrameBuffer) {
		screen_width = width;
		screen_height = height;

		if (CEmuLoop::s_pFrameBuffer)
			delete CEmuLoop::s_pFrameBuffer;

		CEmuLoop::s_pFrameBuffer = new CBcmFrameBuffer(width, height, 32);

		if (!CEmuLoop::s_pFrameBuffer->Initialize()) {
			LOG(RETRO_LOG_WARN, "Could not set correct ressolution. Fallback to virtual resolution.");

			delete CEmuLoop::s_pFrameBuffer;
			//CKernelOptions *opt = (CKernelOptions*)userdata;
			//CEmuLoop::s_pFrameBuffer = new CBcmFrameBuffer(opt->GetWidth(), opt->GetHeight(), 32, width, height);
			CEmuLoop::s_pFrameBuffer = new CBcmFrameBuffer(640, 480, 32, width, height);

			if (!CEmuLoop::s_pFrameBuffer->Initialize()) {
				LOG(RETRO_LOG_ERROR, "Could not initialize framebuffer!");
				delete CEmuLoop::s_pFrameBuffer;
				return;
			}
		}
	}

	u8 *buffer = (u8*)(u64)CEmuLoop::s_pFrameBuffer->GetBuffer();
	const u8 *rgba = (const u8*)data;
	
	for (unsigned i = 0; i < height; i++) {
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
}

CEmuLoop::CEmuLoop(
	CMemorySystem *mem, CKernelOptions *opt, CBcmFrameBuffer *fb,
	CSoundBaseDevice *snd, unsigned al)
:
	CMultiCoreSupport(mem),
	m_pOptions(opt),
	m_pSound(snd),
	m_AudioLatency(al)
{
	assert(CLOCKHZ == 1000000);
	s_pFrameBuffer = fb;
/*
	for (int i = 1; i < VXT_MAX_PERIPHERALS; i++) {
		struct vxt_peripheral *device = vxt_system_peripheral(s, (vxt_byte)i);
		if (device && vxt_peripheral_class(device) == VXT_PCLASS_PPI) {
			m_pPPI = device;
			break;
		}
	}
*/
	retro_set_video_refresh(&video_refresh);
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
	LOGI("Emulation thread started!");

	for (u64 ticks = CTimer::GetClockTicks64(); CKernel::Get()->m_ShutdownMode == ShutdownNone;) {
		u64 now = CTimer::GetClockTicks64();
		u64 dt = now - ticks;

		if (dt >= (CLOCKHZ / 60)) {
			Lock();
			frame_time.callback(dt);
			retro_run();
			Unlock();

			ticks = now;
		}
	}

	LOGI("Emulation thread ended!");
}

void CEmuLoop::RenderThread(void) {
	LOGI("Render thread started!");

	u64 render_ticks = CTimer::GetClockTicks64();

	for (u64 ticks = render_ticks; CKernel::Get()->m_ShutdownMode == ShutdownNone; ticks = CTimer::GetClockTicks64()) {
		if ((ticks - render_ticks) >= (CLOCKHZ / 60)) {
			render_ticks = ticks;
			
			Lock();
			// Render here
			Unlock();

		   	//m_pVideoAdapter->render(m_pVideoAdapter->device, &render_callback, m_pOptions);
		}
	}

	LOGI("Render thread ended!");
}

void CEmuLoop::AudioThread(void) {
	if (!m_pSound)
		return;
	
	LOGI("Audio thread started!");

	const unsigned audio_buffer_size = (SAMPLE_RATE / 1000) * m_AudioLatency;
	unsigned audio_buffer_len = 0;

	DMA_BUFFER(short, audio_buffer, audio_buffer_size);
	memset(audio_buffer, 0, audio_buffer_size * 2);
	
	u64 audio_ticks = CTimer::GetClockTicks64();

	for (u64 ticks = audio_ticks; CKernel::Get()->m_ShutdownMode == ShutdownNone; ticks = CTimer::GetClockTicks64()) {
		if ((ticks - audio_ticks) >= (CLOCKHZ / SAMPLE_RATE)) {
			audio_ticks = ticks;

			// Generate audio.
			if (audio_buffer_len < audio_buffer_size) {
				Lock();
				{/*
					short sample = m_pPPI ? vxtu_ppi_generate_sample(m_pPPI, SAMPLE_RATE) : 0;
					if (m_pAudioAdapter->device)
						sample += m_pAudioAdapter->generate_sample(m_pAudioAdapter->device, SAMPLE_RATE);
					*/
					audio_buffer[audio_buffer_len++] = 0;
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
	
	LOGI("Audio thread ended!");
}
