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

#ifndef _KERNEL_H_
#define _KERNEL_H_

#include <circle/actled.h>
#include <circle/koptions.h>
#include <circle/devicenameservice.h>
#include <circle/bcmframebuffer.h>
#include <circle/screen.h>
#include <circle/exceptionhandler.h>
#include <circle/interrupt.h>
#include <circle/timer.h>
#include <circle/logger.h>
#include <circle/sound/soundbasedevice.h>
#include <circle/sound/pwmsoundbasedevice.h>
#include <circle/sound/hdmisoundbasedevice.h>
#include <circle/sound/usbsoundbasedevice.h>
#include <circle/usb/usbhcidevice.h>
#include <circle/usb/usbkeyboard.h>
#include <circle/usb/usbgamepad.h>
#include <circle/input/mouse.h>
#include <circle/bcm54213.h>
#include <circle/macb.h>
#include <circle/types.h>
#include <SDCard/emmc.h>

#include <libretro.h>

#define DRIVE "SD:"
#define SAMPLE_RATE	22050
#define CHUNK_SIZE 256
#define AUDIO_LATENCY_MS 10
#define HDMI_CHUNK_SIZE (384 * 10) // Not sure why it has to be this exact size?
#define HDMI_AUDIO_LATENCY_MS 100
#define MAX_GAMEPADS 2

#define LOGI(...) ( LOG(RETRO_LOG_INFO, __VA_ARGS__) )
#define LOG(lv, ...) ( log_printf((lv), __VA_ARGS__) )
extern "C" void log_printf(enum retro_log_level level, const char *fmt, ...);

enum TShutdownMode {
	ShutdownNone,
	ShutdownHalt,
	ShutdownReboot
};

class CKernel {
public:
	CKernel(void);
	~CKernel(void);

	boolean Initialize(void);
	TShutdownMode Run(void);

	static CKernel *Get(void);

	// TODO: Make this priveate and signal other threads instead.
	volatile TShutdownMode m_ShutdownMode;

private:
	void InitializeAudio(void);

	static void KeyStatusHandlerRaw(unsigned char ucModifiers, const unsigned char RawKeys[6]);
	static void KeyboardRemovedHandler(CDevice *pDevice, void *pContext);

	static void MouseStatusHandlerRaw(unsigned nButtons, int nDisplacementX, int nDisplacementY, int nWheelMove);
	static void MouseRemovedHandler(CDevice *pDevice, void *pContext);

	static void GamePadStatusHandler(unsigned nDeviceIndex, const TGamePadState *pState);
	static void GamePadRemovedHandler(CDevice *pDevice, void *pContext);

	CKernelOptions		m_Options;
	CDeviceNameService	m_DeviceNameService;
	CCPUThrottle 		m_CPUThrottle;
	CExceptionHandler	m_ExceptionHandler;
	CInterruptSystem	m_Interrupt;
	CTimer				m_Timer;
	CLogger				m_Logger;
	CUSBHCIDevice		m_USBHCI;
	CEMMCDevice			m_EMMC;
#if RASPPI == 4
	CBcm54213Device		m_Bcm54213;
#elif RASPPI == 5
	CMACBDevice			m_MACB;
#endif

	CMouseDevice *volatile m_pMouse;
	CUSBKeyboardDevice *volatile m_pKeyboard;
	CUSBGamePadDevice *volatile m_pGamePad[MAX_GAMEPADS];

	unsigned m_AudioLatency;
	CSoundBaseDevice *m_pSound;
	CBcmFrameBuffer *m_pFrameBuffer;

	static CKernel *s_pThis;
};

#endif
