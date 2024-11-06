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

#define LOGGING 0

#include "kernel.h"
#include <circle/string.h>
#include <circle/util.h>
#include <circle/new.h>
#include <fatfs/ff.h>
#include <assert.h>

#include <vxt/vxtu.h>
#include "keymap.h"

int screen_width = 640;
int screen_height = 480;
struct vxt_peripheral *ppi = 0;

CKernel *CKernel::s_pThis = 0;
CDevice *pUMSD1 = 0;
int pUMSD1_head = 0;

#define DRIVE "SD:"
#define DISKIMAGE "virtualxt.img"
#define NEWIMAGESIZE_MB 40
#define MAX_DISKSIZE_MB 1024*1024*256
#define BIOSIMAGE "GLABIOS.ROM"
#define CPU_FREQUENCY VXT_DEFAULT_FREQUENCY

extern "C" {
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

	static int tell_file(vxt_system *s, void *fp) {
		(void)s;
		if (fp == pUMSD1)
			return pUMSD1_head;
		return (int)f_tell((FIL*)fp);
	}

	static int read_file(vxt_system *s, void *fp, vxt_byte *buffer, int size) {
		(void)s;
		if (fp == pUMSD1) {
			pUMSD1_head += size;
			return (int)pUMSD1->Read(buffer, size);
		}
		
		UINT out = 0;
		if (f_read((FIL*)fp, buffer, (UINT)size, &out) != FR_OK)
			return -1;
		return (int)out;
	}

	static int write_file(vxt_system *s, void *fp, vxt_byte *buffer, int size) {
		(void)s;
		if (fp == pUMSD1) {
			pUMSD1_head += size;
			return (int)pUMSD1->Write(buffer, size);
		}
		
		UINT out = 0;
		if (f_write((FIL*)fp, buffer, (UINT)size, &out) != FR_OK)
			return -1;
			
		f_sync((FIL*)fp);
		return (int)out;
	}

	static int seek_file(vxt_system *s, void *fp, int offset, enum vxtu_disk_seek whence) {
		(void)s;

		int disk_head = tell_file(s, fp);
		int disk_sz = (fp == pUMSD1) ? (int)pUMSD1->GetSize() : (int)f_size((FIL*)fp);
		int pos = -1;

		if (disk_sz > MAX_DISKSIZE_MB)
			disk_sz = MAX_DISKSIZE_MB;

		switch (whence) {
			case VXTU_SEEK_START:
				if ((pos = offset) > disk_sz)
					return -1;
				break;
			case VXTU_SEEK_CURRENT:
				pos = disk_head + offset;
				if ((pos < 0) || (pos > disk_sz))
					return -1;
				break;
			case VXTU_SEEK_END:
				pos = disk_sz - offset;
				if ((pos < 0) || (pos > disk_sz))
					return -1;
				break;
			default:
				VXT_LOG("Invalid seek!");
				return -1;
		}

		if (fp == pUMSD1)
			return (int)pUMSD1->Seek((pUMSD1_head = pos));
		return (f_lseek((FIL*)fp, (FSIZE_t)pos) == FR_OK) ? 0 : -1;
	}

	static struct vxt_peripheral *load_bios(const char *filename, vxt_pointer base) {
		FIL file;
		if (f_open(&file, filename, FA_READ|FA_OPEN_EXISTING) != FR_OK) {
			VXT_LOG("Could not open BIOS image: %s", filename);
			return NULL;
		}

		UINT sz = f_size(&file);
		struct vxt_peripheral *rom = vxtu_memory_create(&allocator, base, (int)sz, true);
		
		if (f_read(&file, vxtu_memory_internal_pointer(rom), sz, NULL) != FR_OK) {
			VXT_LOG("Could not read BIOS image: %s", filename);
			f_close(&file);
			return NULL;
		}

		VXT_LOG("Loaded BIOS @ 0x%X-0x%X", base, base + sz - 1);
		f_close(&file);
		return rom;
	}
	
	static int render_callback(int width, int height, const vxt_byte *rgba, void *userdata) {
		CBcmFrameBuffer **fbp = (CBcmFrameBuffer**)userdata;
		CBcmFrameBuffer *fb = *fbp;

		if (!fb)
			return -1;

		unsigned w = fb->GetWidth();
		unsigned h = fb->GetHeight();

		if ((width != screen_width) || (height != screen_height)) {
			screen_width = width;
			screen_height = height;

			delete fb;
			*fbp = new CBcmFrameBuffer(w, h, 32, (unsigned)width, (unsigned)height, 0, TRUE);
			fb = *fbp;

			if (!fb->Initialize()) {
				VXT_LOG("Cannot recreate framebuffer!");
				return -1;	
			}
		}

		u8 *buffer = (u8*)fb->GetBuffer();
		for (int i = 0; i < height; i++) {
			memcpy(buffer, rgba, 4 * width);
			buffer += fb->GetPitch();
			rgba += 4 * width;
		}
	    return 0;
	}
}

CKernel::CKernel(void)
:	m_CPUThrottle(CPUSpeedMaximum),
	m_Timer(&m_Interrupt),
	m_Logger(m_Options.GetLogLevel()),
	m_USBHCI(&m_Interrupt, &m_Timer, TRUE),
	m_EMMC(&m_Interrupt, &m_Timer, NULL),
	m_pKeyboard(0),
	m_ShutdownMode(ShutdownNone),
	m_pFrameBuffer(0),
	m_Modifiers(0)
{
	memset(m_RawKeys, 0, sizeof(m_RawKeys));
	s_pThis = this;
}

CKernel::~CKernel(void) {
	if (m_pFrameBuffer)
		delete m_pFrameBuffer;
	s_pThis = 0;
}

boolean CKernel::Initialize(void) {
	boolean bOK = TRUE;
	if (bOK)
		bOK = m_Serial.Initialize(115200);

	#if LOGGING
		if (bOK)
			bOK = m_Logger.Initialize(m_DeviceNameService.GetDevice(m_Options.GetLogDevice(), FALSE));
	#endif

	if (bOK)
		bOK = m_Interrupt.Initialize();

	if (bOK)
		bOK = m_Timer.Initialize();

	if (bOK)
		bOK = m_USBHCI.Initialize();

	if (bOK)
		bOK = m_EMMC.Initialize();

	return bOK;
}

TShutdownMode CKernel::Run(void) {
	struct vxt_peripheral *disk = NULL;
	struct vxt_peripheral *cga = NULL;
	//struct vxt_peripheral *mouse = NULL;
	//struct vxt_peripheral *joystick = NULL;

	vxt_set_logger(&logger);

	FATFS emmc_fs;
	FRESULT res = f_mount(&emmc_fs, DRIVE, 1);
	if (res != FR_OK) {
		VXT_PRINT("Cannot mout filesystem: ");
		switch (res) {
			case FR_INVALID_DRIVE: VXT_PRINT("FR_INVALID_DRIVE\n"); break;
			case FR_DISK_ERR: VXT_PRINT("FR_DISK_ERR\n"); break;	
			case FR_NOT_READY: VXT_PRINT("FR_NOT_READY\n"); break;
			case FR_NOT_ENABLED: VXT_PRINT("FR_NOT_ENABLED\n"); break;
			case FR_NO_FILESYSTEM: VXT_PRINT("FR_NO_FILESYSTEM\n"); break;
			default: VXT_PRINT("UNKNOWN ERROR\n");
		}
	}

	m_pFrameBuffer = new CBcmFrameBuffer(m_Options.GetWidth(), m_Options.GetHeight(), 32, (unsigned)screen_width, (unsigned)screen_height, 0, TRUE);
	if (!m_pFrameBuffer->Initialize()) {
		VXT_LOG("Could not initialize framebuffer!");
		return (m_ShutdownMode = ShutdownHalt);
	}
	
	FIL file;
	open_disk: if (f_open(&file, DRIVE DISKIMAGE, FA_READ|FA_WRITE|FA_OPEN_EXISTING) != FR_OK) {
		VXT_LOG("Cannot open file: %s", DISKIMAGE);
		VXT_LOG("Creating one now...");

		if (f_open(&file, DRIVE DISKIMAGE, FA_WRITE|FA_CREATE_NEW) == FR_OK) {
			static const char buffer[512] = {0};
			UINT tmp;
			for (int i = 0; i < 2000 * NEWIMAGESIZE_MB; i++)
				f_write(&file, buffer, sizeof(buffer), &tmp);
			f_close(&file);
			VXT_LOG("Done!");
			goto open_disk;
		} else {
			VXT_LOG("Error! Can't create disk image: %s", DISKIMAGE);
			return (m_ShutdownMode = ShutdownHalt);
		}
	}

	if ((pUMSD1 = m_DeviceNameService.GetDevice("umsd1", TRUE)))
		VXT_LOG("Found USB storage device!");
	
	struct vxtu_disk_interface intrf = {
		&read_file, &write_file, &seek_file, &tell_file
	};

	struct vxt_peripheral *devices[] = {
		vxtu_memory_create(&allocator, 0x0, 0x100000, false),
		load_bios(DRIVE BIOSIMAGE, 0xFE000),
		load_bios(DRIVE "vxtx.bin", 0xE0000),
		vxtu_uart_create(&allocator, 0x3F8, 4),
		vxtu_pic_create(&allocator),
		vxtu_dma_create(&allocator),
		vxtu_pit_create(&allocator),
		(ppi = vxtu_ppi_create(&allocator)),
		(cga = cga_create(&allocator)),
		(disk = vxtu_disk_create(&allocator, &intrf)),
		//(mouse = mouse_create(&allocator, NULL, "0x3F8")),
		//(joystick = joystick_create(&allocator, NULL, "0x201")),
		NULL
	};

	vxt_system *s = vxt_system_create(&allocator, CPU_FREQUENCY, devices);
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

	vxtu_disk_mount(disk, 128, &file);
	if (pUMSD1) vxtu_disk_mount(disk, 129, pUMSD1);
	vxtu_disk_set_boot_drive(disk, 128);

	VXT_LOG("CPU reset!");
	vxt_system_reset(s);

	assert(CLOCKHZ == 1000000);
	u64 renderTicks = CTimer::GetClockTicks64();
	u64 cpuTicks = renderTicks;
	
	while (m_ShutdownMode == ShutdownNone) {
		m_CPUThrottle.Update();
	
		u64 ticks = CTimer::GetClockTicks64();
		if ((ticks - renderTicks) >= (CLOCKHZ / 60)) {
			renderTicks = ticks;
			
			if (m_USBHCI.UpdatePlugAndPlay() && !m_pKeyboard) {
				m_pKeyboard = (CUSBKeyboardDevice*)m_DeviceNameService.GetDevice("ukbd1", FALSE);
				if (m_pKeyboard) {
					m_pKeyboard->RegisterRemovedHandler(KeyboardRemovedHandler);
					m_pKeyboard->RegisterKeyStatusHandlerRaw(KeyStatusHandlerRaw);
					VXT_LOG("Keyboard connected!");
				}
			}

			if (m_pKeyboard)
				m_pKeyboard->UpdateLEDs();

			cga_snapshot(cga);
	    	cga_render(cga, &render_callback, &m_pFrameBuffer);
		}

		u64 dtics = ticks - cpuTicks;
		if (dtics) {
			struct vxt_step step = vxt_system_step(s, (dtics * CPU_FREQUENCY) / 1000000);
			if (step.err != VXT_NO_ERROR)
				VXT_LOG(vxt_error_str(step.err));
			cpuTicks = ticks;
		}
	}

	vxt_system_destroy(s);
	f_unmount(DRIVE);
	
	return m_ShutdownMode;
}

void CKernel::KeyStatusHandlerRaw(unsigned char ucModifiers, const unsigned char RawKeys[6]) {
	assert(s_pThis);
	assert(ppi);

	for(int i = 0; i < NUM_MODIFIERS; i++) {
		const int mask = 1 << i;
		bool was_pressed = (s_pThis->m_Modifiers & mask) != 0;
		bool is_pressed = (ucModifiers & mask) != 0;

		enum vxtu_scancode scan = VXTU_SCAN_INVALID;
		if (!was_pressed && is_pressed) {
			scan = modifierToXT[i];
		} else if (was_pressed && !is_pressed) {
			scan = modifierToXT[i];
			if (scan != VXTU_SCAN_INVALID)
				scan |= VXTU_KEY_UP_MASK;
		}

		if (scan != VXTU_SCAN_INVALID)
			vxtu_ppi_key_event(ppi, scan, false);
	}

	for (int i = 0; i < 6; i++) {
		if (s_pThis->m_RawKeys[i]) {
			bool found = false;
			for (int j = 0; j < 6; j++) {
				if (s_pThis->m_RawKeys[i] == RawKeys[j]) {
					found = true;
					break;
				}
			}

			enum vxtu_scancode scan = usbToXT[RawKeys[i]];
			if (!found && scan != VXTU_SCAN_INVALID)
				vxtu_ppi_key_event(ppi, scan | VXTU_KEY_UP_MASK, false);
		}
	}

	for (int i = 0; i < 6; i++) {
		if (RawKeys[i]) {
			bool found = false;
			for (int j = 0; j < 6; j++) {
				if (RawKeys[i] == s_pThis->m_RawKeys[j]) {
					found = true;
					break;
				}
			}

			enum vxtu_scancode scan = usbToXT[RawKeys[i]];
			if (!found && scan != VXTU_SCAN_INVALID)
				vxtu_ppi_key_event(ppi, scan, false);
		}
	}

	s_pThis->m_Modifiers = ucModifiers;
	memcpy(s_pThis->m_RawKeys, RawKeys, sizeof(s_pThis->m_RawKeys)); 
}

void CKernel::KeyboardRemovedHandler(CDevice *pDevice, void *pContext) {
	assert(s_pThis);
	VXT_LOG("Keyboard removed!");
	s_pThis->m_pKeyboard = 0;
}
