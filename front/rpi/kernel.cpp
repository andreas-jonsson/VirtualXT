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
#include "emuloop.h"

#include <circle/string.h>
#include <circle/util.h>
#include <circle/new.h>
#include <fatfs/ff.h>
#include <assert.h>

#include <vxt/vxtu.h>
#include <frontend.h>
#include "keymap.h"

//#define LOGSERIAL

#define DRIVE "SD:"
#define BIOSIMAGE "GLABIOS.ROM"
#define SAMPLE_RATE	22050
#define CHUNK_SIZE 256
#define AUDIO_LATENCY_MS 10

volatile bool mouse_updated = false;
struct frontend_mouse_event mouse_state;

volatile bool keyboard_updated = false;
bool key_states_current[0x100];
bool key_states[0x100];

struct frontend_video_adapter video_adapter = {0};
struct frontend_audio_adapter audio_adapter = {0};

unsigned cpu_frequency = VXT_DEFAULT_FREQUENCY;

int screen_width = 0;
int screen_height = 0;

const unsigned audio_buffer_size = (SAMPLE_RATE / 1000) * AUDIO_LATENCY_MS;
unsigned audio_buffer_len = 0;
DMA_BUFFER(short, audio_buffer, audio_buffer_size);

CKernel *CKernel::s_pThis = 0;
CBcmFrameBuffer *pFrameBuffer = 0;
CDevice *pUMSD1 = 0;

FIL log_file = {0};
static CSpinLock log_lock(TASK_LEVEL);

extern "C" {
	// From joystick.c
	bool joystick_push_event(struct vxt_peripheral *p, const struct frontend_joystick_event *ev);
	struct vxt_peripheral *joystick_create(vxt_allocator *alloc, const char *args);

	// From mouse.c
	struct vxt_peripheral *mouse_create(vxt_allocator *alloc, const char *args);
	bool mouse_push_event(struct vxt_peripheral *p, const struct frontend_mouse_event *ev);

	// From ethernet.cpp
	struct vxt_peripheral *ethernet_create(vxt_allocator *alloc);

	// From ems.c
	struct vxt_peripheral *ems_create(vxt_allocator *alloc, const char *args);

	// From adlib.c
	struct vxt_peripheral *adlib_create(vxt_allocator *alloc, struct frontend_audio_adapter *aa);

	// From cga.c
	struct vxt_peripheral *cga_card_create(vxt_allocator *alloc, struct frontend_video_adapter *va);

	// From vga.c
	struct vxt_peripheral *vga_card_create(vxt_allocator *alloc, struct frontend_video_adapter *va);
	struct vxt_peripheral *vga_bios_create(vxt_allocator *alloc, const char *args);

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

	int getch_(void) {
		return 0;
	}

	void ungetch_(int ch) {
		(void)ch;
	}

	static int file_logger(const char *fmt, ...) {
		va_list alist;
		va_start(alist, fmt);
		
		CString str;
		str.FormatV(fmt, alist);

		// We do not need to use log_lock here.
		f_write(&log_file, str, str.GetLength(), 0);
		f_sync(&log_file);
		
		va_end(alist);
		return 0; // Not correct but it will have to do for now.
	}

#ifdef LOGSERIAL
	static int dev_logger(const char *fmt, ...) {
		va_list alist;
		va_start(alist, fmt);

		static CString string_buffer;

		CString str;
		str.FormatV(fmt, alist);

		log_lock.Acquire();
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
		log_lock.Release();
		
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

	static vxt_error write_sector(vxt_system *s, void *fp, unsigned index, const vxt_byte *buffer) {
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

			pFrameBuffer = new CBcmFrameBuffer((unsigned)width, (unsigned)height, 32);

			if (!pFrameBuffer->Initialize()) {
				VXT_LOG("Could not set correct ressolution. Fallback to virtual resolution.");

				delete pFrameBuffer;
				CKernelOptions *opt = (CKernelOptions*)userdata;
				pFrameBuffer = new CBcmFrameBuffer(opt->GetWidth(), opt->GetHeight(), 32, (unsigned)width, (unsigned)height);

				if (!pFrameBuffer->Initialize()) {
					VXT_LOG("Could not initialize framebuffer!");
					delete pFrameBuffer;
					return -1;
				}
			}
		}

		u8 *buffer = (u8*)(u64)pFrameBuffer->GetBuffer();
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
			buffer += pFrameBuffer->GetPitch();
		}
		
	    return 0;
	}
}

CKernel::CKernel(void)
:	m_CPUThrottle(
		#if RASPPI == 5
			CPUSpeedUnknown
		#else
			CPUSpeedMaximum
		#endif
	),
	m_Timer(&m_Interrupt),
	m_Logger(m_Options.GetLogLevel()),
	m_USBHCI(&m_Interrupt, &m_Timer, TRUE),
	m_EMMC(&m_Interrupt, &m_Timer, NULL),
	m_pMouse(0),
	m_pKeyboard(0),
	m_ShutdownMode(ShutdownNone),
	m_pSound(0)
{
	// Initialize here to clear screen during boot.
	pFrameBuffer = new CBcmFrameBuffer(m_Options.GetWidth(), m_Options.GetHeight(), 32);
	if (!pFrameBuffer->Initialize())
		delete pFrameBuffer;

	for (int i = 0; i < MAX_GAMEPADS; i++)
		m_pGamePad[i] = 0;
	
	memset(&mouse_state, 0, sizeof(mouse_state));
	memset(key_states, 0, sizeof(key_states));
	memset(key_states_current, 0, sizeof(key_states_current));
	
	memset(&video_adapter, 0, sizeof(video_adapter));
	memset(audio_buffer, 0, audio_buffer_size * 2);
	s_pThis = this;
}

CKernel::~CKernel(void) {
	if (pFrameBuffer)
		delete pFrameBuffer;
	s_pThis = 0;
}

boolean CKernel::Initialize(void) {
	boolean bOK = TRUE;
	#ifdef LOGSERIAL
		if (bOK)
			bOK = m_Serial.Initialize(115200);

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
	struct vxt_peripheral *ppi = NULL;
	struct vxt_peripheral *mouse = NULL;
	struct vxt_peripheral *disk = NULL;
	struct vxt_peripheral *joystick = NULL;

	#ifdef LOGSERIAL
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

	#ifndef LOGSERIAL
		const char *log_file_name = m_Options.GetAppOptionString("LOGFILE");
		if (log_file_name && (f_open(&log_file, log_file_name, FA_WRITE|FA_CREATE_ALWAYS) == FR_OK))
			vxt_set_logger(&file_logger);
	#endif

	VXT_LOG("Machine: %s (%s)", CMachineInfo::Get()->GetMachineName(), CMachineInfo::Get()->GetSoCName());
	
	bool has_floppy = true;
	FIL floppy_file;
	if (f_open(&floppy_file, m_Options.GetAppOptionString("FD", "A.img"), FA_READ|FA_WRITE|FA_OPEN_EXISTING) != FR_OK) {
		has_floppy = false;
		VXT_LOG("Cannot open floppy image!");
	}

	bool has_hd = true;
	FIL hd_file;
	if (f_open(&hd_file, m_Options.GetAppOptionString("HD", "C.img"), FA_READ|FA_WRITE|FA_OPEN_EXISTING) != FR_OK) {
		VXT_LOG("Cannot open harddrive image!");
		has_hd = false;
	}

	if ((pUMSD1 = m_DeviceNameService.GetDevice("umsd1", TRUE)))
		VXT_LOG("Found USB storage device!");

	InitializeAudio();

	struct vxtu_disk_interface2 intrf = {
		&read_sector, &write_sector, &num_sectors
	};

	const bool use_cga = m_Options.GetAppOptionDecimal("CGA", 0) != 0;
	VXT_LOG("Video adapter: %s", use_cga ? "CGA" : "VGA");

	struct vxt_peripheral *devices[] = {
		vxtu_memory_create(&allocator, 0x0, 0x100000, false),
		load_bios(BIOSIMAGE, 0xFE000),
		load_bios("vxtx.bin", 0xE0000),
		vxtu_uart_create(&allocator, 0x3F8, 4),
		vxtu_pic_create(&allocator),
		vxtu_dma_create(&allocator),
		vxtu_pit_create(&allocator),
		ethernet_create(&allocator),
		ems_create(&allocator, "lotech_ems"),
		(ppi = vxtu_ppi_create(&allocator)),
		(disk = vxtu_disk_create2(&allocator, &intrf)),
		(mouse = mouse_create(&allocator, "0x3F8")),
		//(joystick = joystick_create(&allocator, "0x201")),
		adlib_create(&allocator, &audio_adapter),
		use_cga ? cga_card_create(&allocator, &video_adapter) : vga_card_create(&allocator, &video_adapter),
		use_cga ? NULL : load_bios("vgabios.bin", 0xC0000),
		NULL
	};

	cpu_frequency = m_Options.GetAppOptionDecimal("CPUFREQ", cpu_frequency);
	VXT_LOG("CPU frequency: %.2fMHz", (double)cpu_frequency / 1000000.0);
	
	vxt_system *s = vxt_system_create(&allocator, (int)cpu_frequency, devices);
	if (!s) {
		VXT_LOG("Could not create system!");
		return (m_ShutdownMode = ShutdownHalt);
	}

	vxt_system_configure(s, "lotech_ems", "memory", "0xD0000");
	
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

	int boot_drive = (int)m_Options.GetAppOptionDecimal("BOOT", has_floppy ? 0 : 128);
	vxtu_disk_set_boot_drive(disk, boot_drive);
	
	VXT_LOG("CPU reset!");
	vxt_system_reset(s);

	CEmuLoop *emuloop = new CEmuLoop(CMemorySystem::Get(), s);
	if (!emuloop->Initialize()) {
		VXT_LOG("Could not start emulation thread!");
		return (m_ShutdownMode = ShutdownHalt);
	}

	assert(CLOCKHZ == 1000000);
	u64 renderTicks = CTimer::GetClockTicks64();
	u64 audioTicks = renderTicks;
	u64 sysTicks = renderTicks;
	
	bool usb_updated = false;
	
	while (m_ShutdownMode == ShutdownNone) {
		u64 ticks = CTimer::GetClockTicks64();

		if ((ticks - sysTicks) >= (CLOCKHZ * 2)) { // Runs once every other second.
			sysTicks = ticks;
			m_CPUThrottle.SetOnTemperature();
			usb_updated = m_USBHCI.UpdatePlugAndPlay() || usb_updated;
		}

		if ((ticks - renderTicks) >= (CLOCKHZ / 60)) {
			renderTicks = ticks;
			
			if (usb_updated) {
				usb_updated = false;
			
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

				if (joystick) {
					for (unsigned u = 1; u <= MAX_GAMEPADS; u++) {
						if (m_pGamePad[u - 1])
							continue;

						CUSBGamePadDevice *gp = (m_pGamePad[u - 1] = (CUSBGamePadDevice*)m_DeviceNameService.GetDevice("upad", u, FALSE));
						if (!gp)
							continue;

						const TGamePadState *pState = gp->GetInitialState();
						assert(pState != 0);

						VXT_LOG("Gamepad %u: %d Button(s) %d Hat(s)", u, pState->nbuttons, pState->nhats);
						for (int i = 0; i < pState->naxes; i++)
							VXT_LOG("Gamepad %u: Axis %d: Minimum %d Maximum %d", u, i + 1, pState->axes[i].minimum, pState->axes[i].maximum);

						gp->RegisterRemovedHandler(GamePadRemovedHandler, this);
						gp->RegisterStatusHandler(GamePadStatusHandler);
					}
				}
			}

			if (m_pKeyboard)
				m_pKeyboard->UpdateLEDs();

			CEmuLoop::s_SpinLock.Acquire();
			{
				if (keyboard_updated) {
					for (int i = 0; i < 0x100; i++) {
						bool bnew = key_states[i];
						bool *bcurrent = &key_states_current[i];
						
						if (bnew || (bnew != *bcurrent)) {
							enum vxtu_scancode scan = (enum vxtu_scancode)i;
							vxtu_ppi_key_event(ppi, bnew ? scan : VXTU_KEY_UP(scan), false);
						}
						*bcurrent = bnew;
					}	
					keyboard_updated = false;
				}

				if (m_pMouse && mouse_updated) {
					mouse_push_event(mouse, &mouse_state);
					mouse_updated = false;
				}

				video_adapter.snapshot(video_adapter.device);
			}
			CEmuLoop::s_SpinLock.Release();

	    	video_adapter.render(video_adapter.device, &render_callback, &m_Options);
		}

		while ((ticks - audioTicks) >= (CLOCKHZ / SAMPLE_RATE)) {
			audioTicks += CLOCKHZ / SAMPLE_RATE;

			// Generate audio.
			if (audio_buffer_len < audio_buffer_size) {
				CEmuLoop::s_SpinLock.Acquire();
				{
					short sample = vxtu_ppi_generate_sample(ppi, SAMPLE_RATE);
					if (audio_adapter.device)
						sample += audio_adapter.generate_sample(audio_adapter.device, SAMPLE_RATE);
					audio_buffer[audio_buffer_len++] = sample;
				}
				CEmuLoop::s_SpinLock.Release();
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

	// TODO: Stop thread first!
	delete emuloop;

	vxt_system_destroy(s);

	if (has_floppy) f_close(&floppy_file);
	if (has_hd) f_close(&hd_file);
	f_unmount(DRIVE);
	
	return m_ShutdownMode;
}

void CKernel::InitializeAudio(void) {
	VXT_LOG("Initializing audio...");

	const char *pSoundDevice = m_Options.GetSoundDevice();
	if (pSoundDevice) {
		if (!strcmp(pSoundDevice, "sndpwm"))
			m_pSound = new CPWMSoundBaseDevice(&m_Interrupt, SAMPLE_RATE, CHUNK_SIZE);	
		else if (!strcmp(pSoundDevice, "sndhdmi"))
			m_pSound = new CHDMISoundBaseDevice(&m_Interrupt, SAMPLE_RATE, CHUNK_SIZE);
		#if RASPPI >= 4
			else if (!m_pSound && !strcmp(pSoundDevice, "sndusb"))
				m_pSound = new CUSBSoundBaseDevice(SAMPLE_RATE);
		#endif
	}

	// Use PWM or HDMI as default audio device.
	if (!m_pSound) {
		//#if RASPPI <= 4
			pSoundDevice = "sndpwm";
			m_pSound = new CPWMSoundBaseDevice(&m_Interrupt, SAMPLE_RATE, CHUNK_SIZE);
		//#else
		//	pSoundDevice = "sndhdmi";
		//	m_pSound = new CHDMISoundBaseDevice(&m_Interrupt, SAMPLE_RATE, CHUNK_SIZE);
		//#endif
	}
	
	VXT_LOG("Sound device: %s", pSoundDevice);
	m_pSound->SetWriteFormat(SoundFormatSigned16, 1);
	
	if (!m_pSound->AllocateQueue(AUDIO_LATENCY_MS))
		VXT_LOG("Cannot allocate sound queue!");

	if (!m_pSound->Start())
		VXT_LOG("Cannot start sound device!");
}

void CKernel::KeyStatusHandlerRaw(unsigned char ucModifiers, const unsigned char RawKeys[6]) {
	if (keyboard_updated)
		return;

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
	keyboard_updated = true;
}

void CKernel::KeyboardRemovedHandler(CDevice *pDevice, void *pContext) {
	assert(s_pThis);
	VXT_LOG("Keyboard removed!");
	s_pThis->m_pKeyboard = 0;
}

void CKernel::MouseStatusHandlerRaw(unsigned nButtons, int nDisplacementX, int nDisplacementY, int nWheelMove) {
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
	assert(s_pThis);
	VXT_LOG("Mouse removed!");
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
			VXT_LOG("Gamepad %d removed!", i + 1);
			pThis->m_pGamePad[i] = 0;
			return;
		}
	}
}