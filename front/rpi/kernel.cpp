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
#include <fatfs/ff.h>
#include <assert.h>

#include <vxt/vxtu.h>
#include <frontend.h>
#include "keymap.h"

volatile bool mouse_updated = false;
volatile struct frontend_mouse_event mouse_state = {0};

int screen_width = 0;
int screen_height = 0;
struct vxt_peripheral *ppi = 0;
struct vxt_peripheral *mouse = 0;

CKernel *CKernel::s_pThis = 0;
CBcmFrameBuffer *pFrameBuffer = 0;
CDevice *pUMSD1 = 0;
volatile int pUMSD1_head = 0;

FIL log_file = {0};

#define LOGFILE "virtualxt.log"
//#define LOGDEV

#define DRIVE "SD:"
#define FLOPPYIMAGE "A.img"
#define DISKIMAGE "C.img"
#define BIOSIMAGE "GLABIOS.ROM"
#define CPU_FREQUENCY VXT_DEFAULT_FREQUENCY
#define SAMPLE_RATE	48000

extern "C" {
	#include "../../modules/cga/cga.h"

	// From joystick.c
	bool joystick_push_event(struct vxt_peripheral *p, const struct frontend_joystick_event *ev);
	struct vxt_peripheral *joystick_create(vxt_allocator *alloc, void *frontend, const char *args);

	// From mouse.c
	struct vxt_peripheral *mouse_create(vxt_allocator *alloc, void *frontend, const char *args);
	bool mouse_push_event(struct vxt_peripheral *p, const struct frontend_mouse_event *ev);

	// From ethernet.cpp
	struct vxt_peripheral *ethernet_create(vxt_allocator *alloc);

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

#ifdef LOGFILE
	static int file_logger(const char *fmt, ...) {
		va_list alist;
		va_start(alist, fmt);
		
		CString str;
		str.FormatV(fmt, alist);
		f_write(&log_file, str, str.GetLength(), 0);
		f_sync(&log_file);
		
		va_end(alist);
		return 0; // Not correct but it will have to do for now.
	}
#endif

#ifdef LOGDEV
	static int dev_logger(const char *fmt, ...) {
		va_list alist;
		va_start(alist, fmt);

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
		
		va_end(alist);
		return 0; // Not correct but it will have to do for now.
	}
#endif

	static int num_sectors(vxt_system *s, void *fp) {
		(void)s;
		return ((fp == pUMSD1) ? pUMSD1->GetSize() : f_size((FIL*)fp)) / VXTU_SECTOR_SIZE;
	}

	static vxt_error read_sector(vxt_system *s, void *fp, unsigned index, vxt_byte *buffer) {
		(void)s;
		if (fp == pUMSD1) {
			if (pUMSD1->Seek(index * VXTU_SECTOR_SIZE) < 0)
				return VXT_USER_ERROR(0);

			DMA_BUFFER(vxt_byte, temp, VXTU_SECTOR_SIZE);
			if (pUMSD1->Read(temp, VXTU_SECTOR_SIZE) != VXTU_SECTOR_SIZE)
				return VXT_USER_ERROR(1);

			memcpy(buffer, temp, VXTU_SECTOR_SIZE);
			return VXT_NO_ERROR;
		}

		if (f_lseek((FIL*)fp, (FSIZE_t)index * VXTU_SECTOR_SIZE) != FR_OK)
			return VXT_USER_ERROR(2);
		
		UINT out = 0;
		if (f_read((FIL*)fp, buffer, VXTU_SECTOR_SIZE, &out) != FR_OK)
			return VXT_USER_ERROR(3);
		return (out == VXTU_SECTOR_SIZE) ? VXT_NO_ERROR : VXT_USER_ERROR(4);
	}

	static vxt_error write_sector(vxt_system *s, void *fp, unsigned index, vxt_byte *buffer) {
		(void)s;
		if (fp == pUMSD1) {
			if (pUMSD1->Seek(index * VXTU_SECTOR_SIZE) < 0)
				return VXT_USER_ERROR(0);
			
			DMA_BUFFER(vxt_byte, temp, VXTU_SECTOR_SIZE);
			memcpy(temp, buffer, VXTU_SECTOR_SIZE);

			return (pUMSD1->Write(temp, VXTU_SECTOR_SIZE) == VXTU_SECTOR_SIZE) ? VXT_NO_ERROR : VXT_USER_ERROR(1);
		}

		if (f_lseek((FIL*)fp, (FSIZE_t)index * VXTU_SECTOR_SIZE) != FR_OK)
			return VXT_USER_ERROR(2);

		UINT out = 0;
		if (f_write((FIL*)fp, buffer, VXTU_SECTOR_SIZE, &out) != FR_OK)
			return VXT_USER_ERROR(3);
		if (out != VXTU_SECTOR_SIZE)
			return VXT_USER_ERROR(4);
		return (f_sync((FIL*)fp) == FR_OK) ? VXT_NO_ERROR : VXT_USER_ERROR(5);
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
		if ((width != screen_width) || (height != screen_height) || !pFrameBuffer) {
			screen_width = width;
			screen_height = height;

			if (pFrameBuffer)
				delete pFrameBuffer;

			CKernelOptions *opt = (CKernelOptions*)userdata;
			pFrameBuffer = new CBcmFrameBuffer((unsigned)width, (unsigned)height, 32);

			if (!pFrameBuffer->Initialize()) {
				VXT_LOG("Could not set correct ressolution. Fallback to virtual resolution.");
				pFrameBuffer = new CBcmFrameBuffer(opt->GetWidth(), opt->GetHeight(), 32, (unsigned)width, (unsigned)height);

				if (!pFrameBuffer->Initialize()) {
					VXT_LOG("Could not initialize framebuffer!");
					delete pFrameBuffer;
					return -1;
				}
			}
		}

		u8 *buffer = (u8*)pFrameBuffer->GetBuffer();
		for (int i = 0; i < height; i++) {
			memcpy(buffer, rgba, 4 * width);
			buffer += pFrameBuffer->GetPitch();
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
	m_pMouse(0),
	m_pKeyboard(0),
	m_ShutdownMode(ShutdownNone),
	m_pSound(0),
	m_Modifiers(0){
	// Initialize here to clear screen during boot.
	pFrameBuffer = new CBcmFrameBuffer(m_Options.GetWidth(), m_Options.GetHeight(), 32);
	if (!pFrameBuffer->Initialize())
		delete pFrameBuffer;

	memset(m_RawKeys, 0, sizeof(m_RawKeys));
	s_pThis = this;
}

CKernel::~CKernel(void) {
	if (pFrameBuffer)
		delete pFrameBuffer;
	s_pThis = 0;
}

boolean CKernel::Initialize(void) {
	boolean bOK = TRUE;
	if (bOK)
		bOK = m_Serial.Initialize(115200);

	#ifdef LOGDEV
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
	struct vxt_peripheral *disk = NULL;
	struct vxt_peripheral *cga = NULL;
	//struct vxt_peripheral *joystick = NULL;

	#ifdef LOGDEV
		vxt_set_logger(&dev_logger);
	#endif

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

	#ifdef LOGFILE
		if (f_open(&log_file, DRIVE LOGFILE, FA_WRITE|FA_CREATE_ALWAYS) == FR_OK)
			vxt_set_logger(&file_logger);
	#endif

	bool has_floppy = true;
	FIL floppy_file;
	if (f_open(&floppy_file, DRIVE FLOPPYIMAGE, FA_READ|FA_WRITE|FA_OPEN_EXISTING) != FR_OK) {
		has_floppy = false;
		VXT_LOG("Cannot open floppy image: %s", FLOPPYIMAGE);
	}

	bool has_hd = true;
	FIL hd_file;
	if (f_open(&hd_file, DRIVE DISKIMAGE, FA_READ|FA_WRITE|FA_OPEN_EXISTING) != FR_OK) {
		VXT_LOG("Cannot open harddrive image: %s", DISKIMAGE);
		has_hd = false;
	}

	if ((pUMSD1 = m_DeviceNameService.GetDevice("umsd1", TRUE)))
		VXT_LOG("Found USB storage device!");

	const char *pSoundDevice = m_Options.GetSoundDevice();
	if (!strcmp(pSoundDevice, "sndpwm")) {
		m_pSound = new CPWMSoundBaseDevice(&m_Interrupt, SAMPLE_RATE, 1);

		if (!m_pSound->AllocateQueueFrames(1))
			VXT_LOG("Cannot allocate sound queue!");

		m_pSound->SetWriteFormat(SoundFormatSigned16, 1);

		//unsigned nQueueSizeFrames = m_pSound->GetQueueSizeFrames();
		//WriteSoundData(nQueueSizeFrames);

		if (!m_pSound->Start())
			VXT_LOG("Cannot start sound device!");
	} else {
		VXT_LOG("No supported audio device!");
	}
	
	struct vxtu_disk_interface2 intrf = {
		&read_sector, &write_sector, &num_sectors
	};

	struct vxt_peripheral *devices[] = {
		vxtu_memory_create(&allocator, 0x0, 0x100000, false),
		load_bios(DRIVE BIOSIMAGE, 0xFE000),
		load_bios(DRIVE "vxtx.bin", 0xE0000),
		vxtu_uart_create(&allocator, 0x3F8, 4),
		vxtu_pic_create(&allocator),
		vxtu_dma_create(&allocator),
		vxtu_pit_create(&allocator),
		ethernet_create(&allocator),
		(ppi = vxtu_ppi_create(&allocator)),
		(cga = cga_create(&allocator)),
		(disk = vxtu_disk_create2(&allocator, &intrf)),
		(mouse = mouse_create(&allocator, NULL, "0x3F8")),
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

	int next_hd = 128;
	if (has_floppy) vxtu_disk_mount(disk, 0, &floppy_file);
	if (has_hd) vxtu_disk_mount(disk, next_hd++, &hd_file);
	if (pUMSD1) vxtu_disk_mount(disk, next_hd++, pUMSD1);
	vxtu_disk_set_boot_drive(disk, has_floppy ? 0 : 128);
	
	VXT_LOG("CPU reset!");
	vxt_system_reset(s);

	assert(CLOCKHZ == 1000000);
	u64 renderTicks = CTimer::GetClockTicks64();
	u64 audioTicks = renderTicks;
	u64 vCpuTicks = renderTicks * (CPU_FREQUENCY / 1000000);
	
	while (m_ShutdownMode == ShutdownNone) {
		m_CPUThrottle.Update();
		u64 ticks = CTimer::GetClockTicks64();

		if ((ticks - renderTicks) >= (CLOCKHZ / 60)) {
			renderTicks = ticks;
			
			if (m_USBHCI.UpdatePlugAndPlay()) {
				if (!m_pKeyboard) {
					m_pKeyboard = (CUSBKeyboardDevice*)m_DeviceNameService.GetDevice("ukbd1", FALSE);
					if (m_pKeyboard) {
						m_pKeyboard->RegisterRemovedHandler(KeyboardRemovedHandler);
						m_pKeyboard->RegisterKeyStatusHandlerRaw(KeyStatusHandlerRaw);
						VXT_LOG("Keyboard connected!");
					}
				}

				if (!m_pMouse) {
					m_pMouse = (CMouseDevice*)m_DeviceNameService.GetDevice("mouse1", FALSE);
					if (m_pMouse){
						m_pMouse->RegisterRemovedHandler(MouseRemovedHandler);
						m_pMouse->RegisterStatusHandler(MouseStatusHandlerRaw);
						VXT_LOG("Mouse connected!");
					}
				}
			}

			if (m_pKeyboard)
				m_pKeyboard->UpdateLEDs();

			if (m_pMouse && mouse_updated) {
				mouse_push_event(mouse, &mouse_state);
				mouse_updated = false;
			}

			cga_snapshot(cga);
	    	cga_render(cga, &render_callback, &m_Options);
		}

		if ((ticks - audioTicks) >= (CLOCKHZ / SAMPLE_RATE)) {
			audioTicks = ticks;
			if (m_pSound && m_pSound->IsActive()) {
				short sample = vxtu_ppi_generate_sample(ppi, SAMPLE_RATE);
				m_pSound->Write((u8*)&sample, 2);
			}			
		}

		u64	cpuTicks = ticks * (CPU_FREQUENCY / 1000000);
		if (vCpuTicks < cpuTicks) {
			u64 dtics = cpuTicks - vCpuTicks;
			struct vxt_step step = vxt_system_step(s, (dtics > CPU_FREQUENCY) ? CPU_FREQUENCY : dtics);
			if (step.err != VXT_NO_ERROR)
				VXT_LOG(vxt_error_str(step.err));
			vCpuTicks += step.cycles;
		}
	}

	vxt_system_destroy(s);

	if (has_floppy) f_close(&floppy_file);
	if (has_hd) f_close(&hd_file);
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

void CKernel::MouseStatusHandlerRaw(unsigned nButtons, int nDisplacementX, int nDisplacementY, int nWheelMove) {
	assert(s_pThis != 0);
	if (mouse_updated)
		return;

	int btn = (nButtons & MOUSE_BUTTON_LEFT) ? FRONTEND_MOUSE_LEFT : 0;
	btn |= (nButtons & MOUSE_BUTTON_RIGHT) ? FRONTEND_MOUSE_RIGHT : 0;

	mouse_state.buttons = (enum frontend_mouse_button)btn;
	mouse_state.xrel = nDisplacementX;
	mouse_state.yrel = nDisplacementY;
	mouse_updated = true;
}

void CKernel::MouseRemovedHandler(CDevice *pDevice, void *pContext) {
	assert(s_pThis != 0);
	VXT_LOG("Mouse removed!");
	s_pThis->m_pMouse = 0;
}
