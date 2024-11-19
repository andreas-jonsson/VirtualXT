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

#ifndef _KERNEL_H_
#define _KERNEL_H_

#include <circle/actled.h>
#include <circle/koptions.h>
#include <circle/devicenameservice.h>
#include <circle/bcmframebuffer.h>
#include <circle/screen.h>
#include <circle/serial.h>
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
#include <circle/input/mouse.h>
#include <circle/bcm54213.h>
#include <circle/macb.h>
#include <circle/types.h>

#include <SDCard/emmc.h>

#define _Static_assert static_assert
#define bool bool

#include <vxt/vxt.h>

#undef NULL
#define NULL nullptr

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

private:
	static void KeyStatusHandlerRaw(unsigned char ucModifiers, const unsigned char RawKeys[6]);
	static void KeyboardRemovedHandler(CDevice *pDevice, void *pContext);

	static void MouseStatusHandlerRaw(unsigned nButtons, int nDisplacementX, int nDisplacementY, int nWheelMove);
	static void MouseRemovedHandler(CDevice *pDevice, void *pContext);

	// Do not change this order!
	CKernelOptions		m_Options;
	CDeviceNameService	m_DeviceNameService;
	CCPUThrottle 		m_CPUThrottle;
	CSerialDevice		m_Serial;
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
	volatile TShutdownMode m_ShutdownMode;

	CSoundBaseDevice *m_pSound;

	unsigned char m_Modifiers;
	unsigned char m_RawKeys[6];

	static CKernel *s_pThis;
};

#endif
