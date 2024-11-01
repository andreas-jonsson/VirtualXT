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

#define LOGGING 1

#include "kernel.h"
#include <circle/string.h>
#include <circle/util.h>
#include <circle/new.h>
#include <assert.h>

#include <vxt/vxtu.h>

CKernel *CKernel::s_pThis = 0;

extern "C" {
	#include "../../bios/glabios.h"
	#include "../../bios/vxtx.h"
	#include "../../modules/cga/cga.h"

	// From joystick.c
	bool joystick_push_event(struct vxt_peripheral *p, const struct frontend_joystick_event *ev);
	struct vxt_peripheral *joystick_create(vxt_allocator *alloc, void *frontend, const char *args);

	// From mouse.c
	struct vxt_peripheral *mouse_create(vxt_allocator *alloc, void *frontend, const char *args);
	bool mouse_push_event(struct vxt_peripheral *p, const struct frontend_mouse_event *ev);

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

		#if LOGGING
			static CString string_buffer;

			CString str;
			str.FormatV(fmt, alist);
			string_buffer.Append(str);
			
			int idx = string_buffer.Find('\n');
			if (idx >= 0) {
				char *cstr = new char[idx + 1]; 
				memcpy(cstr, string_buffer, idx);
				cstr[idx] = 0;
				CLogger::Get()->Write("VirtualXT", LogNotice, cstr);
				string_buffer = &string_buffer[idx + 1];
				delete[] cstr;
			}
		#endif
		
		va_end(alist);
		return 0; // Not correct but it will have to do for now.
	}

	static struct vxt_peripheral *load_bios(const vxt_byte *data, int size, vxt_pointer base) {
		struct vxt_peripheral *rom = vxtu_memory_create(&allocator, base, size, true);
		if (!vxtu_memory_device_fill(rom, data, size)) {
			VXT_LOG("vxtu_memory_device_fill() failed!");
			return NULL;
		}
		VXT_LOG("Loaded BIOS @ 0x%X-0x%X", base, base + size - 1);
		return rom;
	}
	
	static int render_callback(int width, int height, const vxt_byte *rgba, void *userdata) {
		CScreenDevice *screen = (CScreenDevice*)userdata;
		for (int y = 0; y < height; y++) {
			for (int x = 0; x < width; x++) {
				#ifdef COLOR32
					#define COLOR COLOR32
				#else
					#define COLOR COLOR16
				#endif
				screen->SetPixel(x, y, COLOR(rgba[0], rgba[1], rgba[2], rgba[3]));
				rgba += 4;
			}
		}
	    return 0;
	}
}

CKernel::CKernel(void)
:	m_Screen(m_Options.GetWidth(), m_Options.GetHeight()),
	m_Timer(&m_Interrupt),
	m_Logger(m_Options.GetLogLevel()),
	m_USBHCI(&m_Interrupt, &m_Timer, TRUE),
	m_pKeyboard(0),
	m_ShutdownMode(ShutdownNone)
{
	m_timerUpdated = true;
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

	#if LOGGING
		if (bOK) {
			CDevice *pTarget = m_DeviceNameService.GetDevice(m_Options.GetLogDevice(), FALSE);
			if (pTarget)
				pTarget = &m_Screen;
			bOK = m_Logger.Initialize(pTarget);
		}
	#endif

	if (bOK)
		bOK = m_Interrupt.Initialize();

	if (bOK)
		bOK = m_Timer.Initialize();

	if (bOK)
		bOK = m_USBHCI.Initialize();
	return bOK;
}

TShutdownMode CKernel::Run(void) {
	//struct vxt_peripheral *disk = NULL;
	struct vxt_peripheral *ppi = NULL;
	struct vxt_peripheral *cga = NULL;
	//struct vxt_peripheral *mouse = NULL;
	//struct vxt_peripheral *joystick = NULL;

	vxt_set_logger(&logger);

	if (sizeof(TScreenColor) < 2) {
		VXT_LOG("Screen color depth must be 16 or 32 bit!");
		return (m_ShutdownMode = ShutdownHalt);
	} else {
		VXT_LOG("Screen color depth: %dbit", sizeof(TScreenColor) * 8);
	}

	//struct vxtu_disk_interface intrf = {
	//	&read_file, &write_file, &seek_file, &tell_file
	//};

	struct vxt_peripheral *devices[] = {
		vxtu_memory_create(&allocator, 0x0, 0x100000, false),
		load_bios(glabios_bin, (int)glabios_bin_len, 0xFE000),
		load_bios(vxtx_bin, (int)vxtx_bin_len, 0xE0000),
		vxtu_uart_create(&allocator, 0x3F8, 4),
		vxtu_pic_create(&allocator),
		vxtu_dma_create(&allocator),
		vxtu_pit_create(&allocator),
		(ppi = vxtu_ppi_create(&allocator)),
		(cga = cga_create(&allocator)),
		//(disk = vxtu_disk_create(&allocator, &intrf)),
		//(mouse = mouse_create(&allocator, NULL, "0x3F8")),
		//(joystick = joystick_create(&allocator, NULL, "0x201")),
		NULL
	};

	vxt_system *s = vxt_system_create(&allocator, VXT_DEFAULT_FREQUENCY, devices);
	if (!s) {
		VXT_LOG("Could not create system!");
		return (m_ShutdownMode = ShutdownHalt);
	}

	vxt_error err = vxt_system_initialize(s);
	if (err != VXT_NO_ERROR) {
		VXT_LOG("Could not initialize system: %s", vxt_error_str(err));
		return (m_ShutdownMode = ShutdownHalt);
	}
	
	VXT_LOG("Installed peripherals:");
	for (int i = 1; i < VXT_MAX_PERIPHERALS; i++) {
		struct vxt_peripheral *device = vxt_system_peripheral(s, (vxt_byte)i);
		if (device)
			VXT_LOG("%d - %s", i, vxt_peripheral_name(device));
	}

	VXT_LOG("CPU reset!");
	vxt_system_reset(s);

	VXT_LOG("Start kernel timer");
	m_Timer.StartKernelTimer(60 * HZ, TimerHandler);
	
	for (unsigned nCount = 0; m_ShutdownMode == ShutdownNone;) {
		if (m_timerUpdated) {
			m_timerUpdated = FALSE;
			
			if (m_USBHCI.UpdatePlugAndPlay() && !m_pKeyboard) {
				m_pKeyboard = (CUSBKeyboardDevice*)m_DeviceNameService.GetDevice("ukbd1", FALSE);
				if (m_pKeyboard) {
					m_pKeyboard->RegisterRemovedHandler(KeyboardRemovedHandler);
					m_pKeyboard->RegisterKeyStatusHandlerRaw(KeyStatusHandlerRaw);
				}
			}

			if (m_pKeyboard)
				m_pKeyboard->UpdateLEDs();

			cga_snapshot(cga);
	    	cga_render(cga, &render_callback, &m_Screen);

			m_Screen.Rotor(0, nCount++);
			//m_Timer.MsDelay(100);
		}

		struct vxt_step step = vxt_system_step(s, 1);
		if (step.err != VXT_NO_ERROR)
			VXT_LOG(vxt_error_str(step.err));

	}

	vxt_system_destroy(s);
	return m_ShutdownMode;
}

void CKernel::KeyStatusHandlerRaw(unsigned char ucModifiers, const unsigned char RawKeys[6]) {
	assert(s_pThis);

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

	//s_pThis->m_Logger.Write ("kernel", LogNotice, Message);
}

void CKernel::KeyboardRemovedHandler(CDevice *pDevice, void *pContext) {
	assert(s_pThis);
	//CLogger::Get()->Write("kernel", LogDebug, "Keyboard removed");
	s_pThis->m_pKeyboard = 0;
}

void CKernel::TimerHandler(TKernelTimerHandle hTimer, void *pParam, void *pContext) {
	assert(s_pThis);
	s_pThis->m_timerUpdated = TRUE;
}
