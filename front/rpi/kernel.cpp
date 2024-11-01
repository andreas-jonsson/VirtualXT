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

#include "kernel.h"
#include <circle/string.h>
#include <circle/util.h>
#include <circle/new.h>
#include <assert.h>

#include <vxt/vxtu.h>
#include <frontend.h>
#include "../../bios/glabios.h"
#include "../../bios/vxtx.h"

CKernel *CKernel::s_pThis = 0;

struct frontend_video_adapter video_adapter = {0};
struct frontend_mouse_adapter mouse_adapter = {0};

extern "C" {
	static void *allocator(void *ptr, size_t sz) {
		if (!sz) {
			if (ptr)
				CMemorySystem::HeapFree(ptr);
			return NULL;
		}
		void *np = CMemorySystem::HeapAllocate(sz, HEAP_DEFAULT_NEW);
		if (ptr)
			memcpy(np, ptr, sz);
		return np;
	}


	static int logger(const char *fmt, ...) {
		va_list alist;
		va_start(alist, fmt);

		int ret = 0;//vsnprintf(NULL, 0, fmt, alist);
		CLogger::Get()->WriteV("VirtualXT", LogNotice, fmt, alist);

		va_end(alist);
		return ret;
	}

	static struct vxt_peripheral *load_bios(const vxt_byte *data, int size, vxt_pointer base) {
		struct vxt_peripheral *rom = vxtu_memory_create(&allocator, base, size, true);
		if (!vxtu_memory_device_fill(rom, data, size)) {
			VXT_LOG("vxtu_memory_device_fill() failed!");
			return (struct vxt_peripheral*)NULL;
		}
		VXT_LOG("Loaded BIOS @ 0x%X-0x%X", base, base + size - 1);
		return rom;
	}

	static bool set_video_adapter(const struct frontend_video_adapter *adapter) {
		if (video_adapter.device)
			return false;
		video_adapter = *adapter;
		return true;
	}
	
	static bool set_mouse_adapter(const struct frontend_mouse_adapter *adapter) {
		if (mouse_adapter.device)
			return false;
		mouse_adapter = *adapter;
		return true;
	}
	
	static vxt_byte emu_control(enum frontend_ctrl_command cmd, vxt_byte data, void *userdata) {
		(void)data; (void)userdata;
		if (cmd == FRONTEND_CTRL_SHUTDOWN) {
			VXT_LOG("Guest OS shutdown!");
			js_shutdown();
		}
		return 0;
	}
	
	static int render_callback(int width, int height, const vxt_byte *rgba, void *userdata) {
	    cga_width = width;
		cga_height = height;
	    *(const vxt_byte**)userdata = rgba;
	    return 0;
	}
}

CKernel::CKernel(void)
:	m_Screen(m_Options.GetWidth(), m_Options.GetHeight()),
	m_Timer(&m_Interrupt),
	m_Logger(m_Options.GetLogLevel(), &m_Timer),
	m_USBHCI(&m_Interrupt, &m_Timer, TRUE),
	m_pKeyboard(0),
	m_ShutdownMode(ShutdownNone)
{
	s_pThis = this;
}

CKernel::~CKernel(void) {
	s_pThis = 0;
}

boolean CKernel::Initialize(void) {
	boolean bOK = TRUE;
	if (bOK)
		bOK = m_Screen.Initialize();

	if (bOK)
		bOK = m_Serial.Initialize(115200);

	if (bOK) {
		CDevice *pTarget = m_DeviceNameService.GetDevice(m_Options.GetLogDevice(), FALSE);
		if (pTarget)
			pTarget = &m_Screen;
		bOK = m_Logger.Initialize(pTarget);
	}

	if (bOK)
		bOK = m_Interrupt.Initialize();

	if (bOK)
		bOK = m_Timer.Initialize();

	if (bOK)
		bOK = m_USBHCI.Initialize();
	return bOK;
}

TShutdownMode CKernel::Run(void) {
	vxt_set_logger(&logger);

	struct vxt_peripheral *devices[] = {
		vxtu_memory_create(&allocator, 0x0, 0x100000, false),
		load_bios(glabios_bin, (int)glabios_bin_len, 0xFE000),
		load_bios(vxtx_bin, (int)vxtx_bin_len, 0xE0000),
		vxtu_uart_create(&allocator, 0x3F8, 4),
		vxtu_pic_create(&allocator),
		vxtu_dma_create(&allocator),
		vxtu_pit_create(&allocator),
		//ppi,
		cga,
		//disk,
		//mouse,
		//joystick,
		(struct vxt_peripheral*)NULL
	};

	vxt_system *s = vxt_system_create(&allocator, VXT_DEFAULT_FREQUENCY, devices);
	if (!s) {
		VXT_LOG("Could not create system!");
		return (m_ShutdownMode = ShutdownHalt);
	}

	VXT_LOG("Installed peripherals:\n");
	for (int i = 1; i < VXT_MAX_PERIPHERALS; i++) {
		struct vxt_peripheral *device = vxt_system_peripheral(s, (vxt_byte)i);
		if (device)
			VXT_LOG("%d - %s", i, vxt_peripheral_name(device));
	}

	VXT_LOG("System reset!");
	vxt_system_reset(s);
	
	for (unsigned nCount = 0; m_ShutdownMode == ShutdownNone; nCount++) {
		boolean bUpdated = m_USBHCI.UpdatePlugAndPlay();

		if (bUpdated && !m_pKeyboard) {
			m_pKeyboard = (CUSBKeyboardDevice*)m_DeviceNameService.GetDevice("ukbd1", FALSE);
			if (m_pKeyboard) {
				m_pKeyboard->RegisterRemovedHandler (KeyboardRemovedHandler);

#if 1	// set to 0 to test raw mode
				m_pKeyboard->RegisterShutdownHandler (ShutdownHandler);
				m_pKeyboard->RegisterKeyPressedHandler (KeyPressedHandler);
#else
				m_pKeyboard->RegisterKeyStatusHandlerRaw (KeyStatusHandlerRaw);
#endif

				m_Logger.Write ("kernel", LogNotice, "Just type something!");
			}
		}

		if (m_pKeyboard)
			m_pKeyboard->UpdateLEDs();

		struct vxt_step step = vxt_system_step(s, 1);
		if (step.err != VXT_NO_ERROR)
			VXT_LOG(vxt_error_str(step.err));


		m_Screen.Rotor(0, nCount);
		m_Timer.MsDelay(100);
	}

	vxt_system_destroy(s);
	return m_ShutdownMode;
}

void CKernel::KeyPressedHandler(const char *pString) {
	assert(s_pThis != 0);
#ifdef EXPAND_CHARACTERS
	while (*pString)
          {
	  CString s;
	  s.Format ("'%c' %d %02X\n", *pString, *pString, *pString);
          pString++;
	  s_pThis->m_Screen.Write (s, strlen (s));
          }
#else
	s_pThis->m_Screen.Write (pString, strlen (pString));
#endif
}

void CKernel::ShutdownHandler(void) {
	assert(s_pThis != 0);
	s_pThis->m_ShutdownMode = ShutdownReboot;
}

void CKernel::KeyStatusHandlerRaw(unsigned char ucModifiers, const unsigned char RawKeys[6]) {
	assert(s_pThis != 0);

	CString Message;
	Message.Format ("Key status (modifiers %02X)", (unsigned) ucModifiers);

	for (unsigned i = 0; i < 6; i++)
	{
		if (RawKeys[i] != 0)
		{
			CString KeyCode;
			KeyCode.Format (" %02X", (unsigned) RawKeys[i]);

			Message.Append (KeyCode);
		}
	}

	s_pThis->m_Logger.Write ("kernel", LogNotice, Message);
}

void CKernel::KeyboardRemovedHandler(CDevice *pDevice, void *pContext) {
	assert(s_pThis != 0);
	CLogger::Get()->Write("kernel", LogDebug, "Keyboard removed");
	s_pThis->m_pKeyboard = 0;
}
