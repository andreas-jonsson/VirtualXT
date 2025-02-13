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

#include "kernel.h"
#include "emuloop.h"

#include <circle/string.h>
#include <circle/util.h>
#include <circle/new.h>
#include <fatfs/ff.h>
#include <assert.h>

#include <libretro.h>

CKernel *CKernel::s_pThis = 0;

volatile bool mouse_updated = false;
//struct frontend_mouse_event mouse_state;

volatile bool keyboard_updated = false;
bool key_states_current[0x100];
bool key_states[0x100];

bool enable_logging = false;
FIL log_file = {0};
FIL vfs_handles[0x100] = {0};

struct retro_frame_time_callback frame_time = {0};
struct retro_vfs_interface vfs_interface = {0};

extern "C" {
	void retro_init(void);
	void retro_deinit(void);
	void retro_set_environment(retro_environment_t cb);
	bool retro_load_game(const struct retro_game_info *info);
	void retro_unload_game(void);
	void retro_set_input_poll(retro_input_poll_t cb);
}

extern "C" {
	void log_printf(enum retro_log_level level, const char *fmt, ...) {
		va_list args;
		va_start(args, fmt);
		
		CString prefix;
		switch (level) {
			case RETRO_LOG_DEBUG:
				prefix += "[DEBUG] ";
				break;
			case RETRO_LOG_INFO:
				prefix += "[INFO] ";
				break;
			case RETRO_LOG_WARN:
				prefix += "[WARNING] ";
				break;
			case RETRO_LOG_ERROR:
				prefix += "[ERROR] ";
				break;
			default:
				break;
		}

		CString msg;
		msg.FormatV(fmt, args);
		prefix += msg;
		if (prefix.c_str()[prefix.GetLength() - 1] != '\n')
			prefix += "\n";
		
		f_write(&log_file, prefix, prefix.GetLength(), 0);
		f_sync(&log_file);
		va_end(args);
	}

	void no_log_printf(enum retro_log_level level, const char *fmt, ...) {
	}

	struct retro_vfs_file_handle *vfs_open(const char *path, unsigned mode, unsigned hints) {
		uintptr_t i;
		for (i = 1; i < 0x100; i++) {
			FIL *handle = &vfs_handles[i];
			FIL zero = {0};

			if (!memcmp(handle, &zero, sizeof(FIL))) {
				BYTE m = 0;
				if (mode & RETRO_VFS_FILE_ACCESS_READ)
					m |= FA_READ;
				if (mode & RETRO_VFS_FILE_ACCESS_WRITE)
					m |= FA_WRITE;
				if (mode & RETRO_VFS_FILE_ACCESS_UPDATE_EXISTING)
					m |= FA_OPEN_EXISTING;
				
				if (f_open(handle, path, m) != FR_OK) {
					memset(handle, 0, sizeof(FIL));
					return 0;
				}
			}
			return (struct retro_vfs_file_handle*)i;
		}
		return 0;		
	}

	int vfs_close(struct retro_vfs_file_handle *stream) {
		FIL *handle = &vfs_handles[(uintptr_t)stream];
		f_close(handle);
		memset(handle, 0, sizeof(FIL));
		return 0;
	}

	int vfs_flush(struct retro_vfs_file_handle *stream) {
		FIL *handle = &vfs_handles[(uintptr_t)stream];
		f_sync(handle);
		return 0;
	}

	int64_t vfs_size(struct retro_vfs_file_handle *stream) {
		FIL *handle = &vfs_handles[(uintptr_t)stream];
		return f_size(handle);
	}

	int64_t vfs_read(struct retro_vfs_file_handle *stream, void *s, uint64_t len) {
		FIL *handle = &vfs_handles[(uintptr_t)stream];
		UINT num = 0;
		if (f_read(handle, s, len, &num) != FR_OK)
			return -1;
		return num;
	}

	int64_t vfs_write(struct retro_vfs_file_handle *stream, const void *s, uint64_t len) {
		FIL *handle = &vfs_handles[(uintptr_t)stream];
		UINT num = 0;
		if (f_write(handle, s, len, &num) != FR_OK)
			return -1;
		return num;
	}
	
	int64_t vfs_seek(struct retro_vfs_file_handle *stream, int64_t offset, int seek_position) {
		FIL *handle = &vfs_handles[(uintptr_t)stream];
		if (seek_position != RETRO_VFS_SEEK_POSITION_START)
			return -1;
		return (f_lseek(handle, offset) != FR_OK) ? -1 : 0;
	}

	void input_poll(void) {
	}

	bool retro_environment(unsigned cmd, void *data) {
		switch (cmd) {
		case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
			{
				struct retro_log_callback *ret = (struct retro_log_callback*)data;
				ret->log = enable_logging ? &log_printf : no_log_printf;
			}
			return true;
		case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
			return true;
		case RETRO_ENVIRONMENT_SET_FRAME_TIME_CALLBACK:
			frame_time = *(struct retro_frame_time_callback*)data;
			return true;
		case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
			*((const char**)data) = DRIVE;
			return true;
		case RETRO_ENVIRONMENT_GET_VFS_INTERFACE:
			memset(data, 0, sizeof(struct retro_vfs_interface_info));
			
			vfs_interface.open = &vfs_open;
			vfs_interface.close = &vfs_close;
			vfs_interface.flush = &vfs_flush;
			vfs_interface.size = &vfs_size;
			vfs_interface.read = &vfs_read;
			vfs_interface.write = &vfs_write;
			vfs_interface.seek = &vfs_seek;

			((struct retro_vfs_interface_info*)data)->iface = &vfs_interface;
			return true;
		}
		return false;
	}
}

CKernel::CKernel(void)
:	m_ShutdownMode(ShutdownNone),
	m_CPUThrottle(
		#if RASPPI == 5
			CPUSpeedUnknown
		#else
			CPUSpeedMaximum
		#endif
	),
	m_Timer(&m_Interrupt),
	m_Logger(m_Options.GetLogLevel()),
	m_USBHCI(&m_Interrupt, &m_Timer, TRUE),
	m_EMMC(&m_Interrupt, &m_Timer, 0),
	m_pMouse(0),
	m_pKeyboard(0),
	m_pSound(0)
{
	// Initialize here to clear screen during boot.
	m_pFrameBuffer = new CBcmFrameBuffer(m_Options.GetWidth(), m_Options.GetHeight(), 32);
	if (!m_pFrameBuffer->Initialize())
		delete m_pFrameBuffer;

	for (int i = 0; i < MAX_GAMEPADS; i++)
		m_pGamePad[i] = 0;
	
	//memset(&mouse_state, 0, sizeof(mouse_state));
	memset(key_states, 0, sizeof(key_states));
	memset(key_states_current, 0, sizeof(key_states_current));
	
	s_pThis = this;
}

CKernel::~CKernel(void) {
	if (m_pFrameBuffer)
		delete m_pFrameBuffer;
	s_pThis = 0;
}

CKernel *CKernel::Get(void) {
	assert(s_pThis);
	return s_pThis;
};

boolean CKernel::Initialize(void) {
	boolean bOK = TRUE;
	if (bOK)
		bOK = m_Interrupt.Initialize();

	if (bOK)
		bOK = m_Timer.Initialize();

	if (bOK)
		bOK = m_USBHCI.Initialize();

	if (bOK)
		bOK = m_EMMC.Initialize();

	if (bOK) {
		#if RASPPI == 4
			bOK = m_Bcm54213.Initialize();
		#elif RASPPI == 5
			bOK = m_MACB.Initialize();
		#endif
	}
	return bOK;
}

TShutdownMode CKernel::Run(void) {
	FATFS emmc_fs;
	if (f_mount(&emmc_fs, DRIVE, 1) != FR_OK) {
		return (m_ShutdownMode = ShutdownHalt);
	}

	const char *log_file_name = m_Options.GetAppOptionString("LOGFILE");
	if (log_file_name && (f_open(&log_file, log_file_name, FA_WRITE|FA_CREATE_ALWAYS) == FR_OK))
		enable_logging = true;

	LOGI("Machine: %s (%s)", CMachineInfo::Get()->GetMachineName(), CMachineInfo::Get()->GetSoCName());

	LOGI("retro_init");
	retro_init();

	LOGI("retro_set_environment");
	retro_set_environment(&retro_environment);

	LOGI("retro_load_game");
	struct retro_game_info game_info = { "C.img", 0	};
	retro_load_game(&game_info);

	retro_set_input_poll(&input_poll);
	
	InitializeAudio();

	CEmuLoop *emuloop = new CEmuLoop(CMemorySystem::Get(), &m_Options, m_pFrameBuffer, m_pSound, m_AudioLatency);
	if (!emuloop->Initialize()) {
		LOG(RETRO_LOG_ERROR, "Could not start emulation thread!");
		return (m_ShutdownMode = ShutdownHalt);
	}

	assert(CLOCKHZ == 1000000);
	u64 input_ticks = CTimer::GetClockTicks64();
	u64 sys_ticks = input_ticks;
	
	while (m_ShutdownMode == ShutdownNone) {
		u64 ticks = CTimer::GetClockTicks64();

		// Runs once every other second.
		if ((ticks - sys_ticks) >= (CLOCKHZ * 2)) {
			sys_ticks = ticks;
			m_CPUThrottle.SetOnTemperature();
		
			if (m_USBHCI.UpdatePlugAndPlay()) {			
				if (!m_pKeyboard) {
					m_pKeyboard = (CUSBKeyboardDevice*)m_DeviceNameService.GetDevice("ukbd1", FALSE);
					if (m_pKeyboard) {
						m_pKeyboard->RegisterRemovedHandler(KeyboardRemovedHandler);
						m_pKeyboard->RegisterKeyStatusHandlerRaw(KeyStatusHandlerRaw);
						LOGI("Keyboard connected!");
					}
				}

				if (!m_pMouse) {
					m_pMouse = (CMouseDevice*)m_DeviceNameService.GetDevice("mouse1", FALSE);
					if (m_pMouse){
						m_pMouse->RegisterRemovedHandler(MouseRemovedHandler);
						m_pMouse->RegisterStatusHandler(MouseStatusHandlerRaw);
						LOGI("Mouse connected!");
					}
				}
				/*
				if (joystick) {
					for (unsigned u = 1; u <= MAX_GAMEPADS; u++) {
						if (m_pGamePad[u - 1])
							continue;

						CUSBGamePadDevice *gp = (m_pGamePad[u - 1] = (CUSBGamePadDevice*)m_DeviceNameService.GetDevice("upad", u, FALSE));
						if (!gp)
							continue;

						const TGamePadState *pState = gp->GetInitialState();
						assert(pState != 0);

						LOGI("Gamepad %u: %d Button(s) %d Hat(s)", u, pState->nbuttons, pState->nhats);
						for (int i = 0; i < pState->naxes; i++)
							LOGI("Gamepad %u: Axis %d: Minimum %d Maximum %d", u, i + 1, pState->axes[i].minimum, pState->axes[i].maximum);

						gp->RegisterRemovedHandler(GamePadRemovedHandler, this);
						gp->RegisterStatusHandler(GamePadStatusHandler);
					}
				}*/
			}
		}

		if ((ticks - input_ticks) >= (CLOCKHZ / 60)) {
			input_ticks = ticks;
			
			if (m_pKeyboard)
				m_pKeyboard->UpdateLEDs();

			CEmuLoop::Lock();
			{
				if (keyboard_updated) {
					for (int i = 0; i < 0x100; i++) {
						bool bnew = key_states[i];
						bool *bcurrent = &key_states_current[i];

						// TODO: Fix key repeat!
						//if (bnew || (bnew != *bcurrent)) {
						if (bnew != *bcurrent) {
							//enum vxtu_scancode scan = (enum vxtu_scancode)i;
							//vxtu_ppi_key_event(ppi, bnew ? scan : VXTU_KEY_UP(scan), false);
						}
						*bcurrent = bnew;
					}	
					keyboard_updated = false;
				}

				if (m_pMouse && mouse_updated) {
					//mouse_push_event(mouse, &mouse_state);
					mouse_updated = false;
				}
			}
			CEmuLoop::Unlock();
		}
	}

	delete emuloop;

	retro_unload_game();
	retro_deinit();

	if (m_pSound)
		delete m_pSound;

	f_unmount(DRIVE);
	
	return m_ShutdownMode;
}

void CKernel::InitializeAudio(void) {
	if (m_Options.GetAppOptionDecimal("MUTE", 0)) {
		LOGI("Audio device muted!");
		return;
	}
		
	LOGI("Initializing audio...");

	m_AudioLatency = AUDIO_LATENCY_MS;
	const char *pSoundDevice = m_Options.GetSoundDevice();
	
	if (pSoundDevice) {
		if (!strcmp(pSoundDevice, "sndpwm")) {
			m_pSound = new CPWMSoundBaseDevice(&m_Interrupt, SAMPLE_RATE, CHUNK_SIZE);	
		} else if (!strcmp(pSoundDevice, "sndhdmi")) {
			m_AudioLatency = HDMI_AUDIO_LATENCY_MS;
			m_pSound = new CHDMISoundBaseDevice(&m_Interrupt, SAMPLE_RATE, HDMI_CHUNK_SIZE);
		}
		#if RASPPI >= 4
			else if (!m_pSound && !strcmp(pSoundDevice, "sndusb")) {
				m_pSound = new CUSBSoundBaseDevice(SAMPLE_RATE);
			}
		#endif
	}

	// Use PWM or HDMI as default audio device.
	if (!m_pSound) {
		#if RASPPI <= 4
			pSoundDevice = "sndpwm";
			m_pSound = new CPWMSoundBaseDevice(&m_Interrupt, SAMPLE_RATE, CHUNK_SIZE);
		#else
			pSoundDevice = "sndhdmi";
			m_AudioLatency = HDMI_AUDIO_LATENCY_MS;
			m_pSound = new CHDMISoundBaseDevice(&m_Interrupt, SAMPLE_RATE, HDMI_CHUNK_SIZE);
		#endif
	}
	
	LOGI("Sound device: %s", pSoundDevice);
	m_pSound->SetWriteFormat(SoundFormatSigned16, 1);
	
	if (!m_pSound->AllocateQueue(m_AudioLatency))
		LOG(RETRO_LOG_ERROR, "Cannot allocate sound queue!");

	if (!m_pSound->Start())
		LOG(RETRO_LOG_ERROR, "Cannot start sound device!");
}

void CKernel::KeyStatusHandlerRaw(unsigned char ucModifiers, const unsigned char RawKeys[6]) {
	//if (keyboard_updated)
	//	return;
/*
	memset(key_states, 0, sizeof(key_states));
	for(int i = 0; i < NUM_MODIFIERS; i++) {
		const int mask = 1 << i;
		key_states[modifierToXT[i]] = (ucModifiers & mask);
	}

	for (int i = 0; i < 6; i++) {
		unsigned char raw = RawKeys[i];
		if (raw == 0xE0) {
			i++;
			continue;
		}
			
		enum vxtu_scancode scan = usbToXT[raw];
		key_states[scan] = true;
	}
	keyboard_updated = true;*/
}

void CKernel::KeyboardRemovedHandler(CDevice *pDevice, void *pContext) {
	assert(s_pThis);
	LOGI("Keyboard removed!");
	s_pThis->m_pKeyboard = 0;
}

void CKernel::MouseStatusHandlerRaw(unsigned nButtons, int nDisplacementX, int nDisplacementY, int nWheelMove) {
	//if (mouse_updated)
	//	return;

/*
	int btn = (nButtons & MOUSE_BUTTON_LEFT) ? FRONTEND_MOUSE_LEFT : 0;
	btn |= (nButtons & MOUSE_BUTTON_RIGHT) ? FRONTEND_MOUSE_RIGHT : 0;

	mouse_state.buttons = (enum frontend_mouse_button)btn;
	mouse_state.xrel = nDisplacementX;
	mouse_state.yrel = nDisplacementY;*/
	mouse_updated = true;
}

void CKernel::MouseRemovedHandler(CDevice *pDevice, void *pContext) {
	assert(s_pThis);
	LOGI("Mouse removed!");
	s_pThis->m_pMouse = 0;
}

void CKernel::GamePadStatusHandler(unsigned nDeviceIndex, const TGamePadState *pState) {
	// TODO
}

void CKernel::GamePadRemovedHandler(CDevice *pDevice, void *pContext) {
	CKernel *pThis = (CKernel*)pContext;
	assert(pThis);

	for (int i = 0; i < MAX_GAMEPADS; i++) {
		if (pThis->m_pGamePad[i] == (CUSBGamePadDevice*)pDevice) {
			LOGI("Gamepad %d removed!", i + 1);
			pThis->m_pGamePad[i] = 0;
			return;
		}
	}
}
