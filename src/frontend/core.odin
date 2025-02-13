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

package frontend

import "base:runtime"
import "core:c"
import "core:log"
import "core:strconv"
import "core:strings"
import "core:time"

import "modules:vga"
import "modules:cga"
import "modules:chipset"
import "modules:disk"
import "modules:gdb"
import "modules:rom"
import "modules:ems"

import retro "vxt:frontend/libretro"
import "vxt:machine"

VXT_VERSION :: "1.4.0"
MAX_DISK_IMAGES :: 256
AUDIO_FREQUENCY :: 44100
DEFAULT_DISK_IMAGE :: "boot:svardos_hd.img"

delta_time: retro.usec_t

glabios := true
enable_vga := false
enable_ems := true

reset_default_disk, floppy_boot_prio: bool
gdb_server, gdb_halt: bool

disk_images: [dynamic]string
disk_image_index: uint

frame_buffer: struct {
	memory:        [dynamic]u32,
	width, height: uint,
}

retro_callbacks: struct {
	environment: retro.environment_t,
	video:       retro.video_refresh_t,
	audio:       retro.audio_sample_t,
	input_poll:  retro.input_poll_t,
	input_state: retro.input_state_t,
	vfs:         ^retro.vfs_interface,
}

options := [?]retro.variable {
	{"virtualxt_reset_default_disk", "Reset default disk; false|true"},
	{"virtualxt_boot_priority", "Boot priority; FD|HD"},
	{"virtualxt_video", "Video standard; CGA|VGA"},
	{"virtualxt_cpu_frequency", "CPU frequency; 4.77MHz|7.15MHz|14.3MHz"},
	{"virtualxt_ems", "EMS memory; true|false"},
	{"virtualxt_bios", "BIOS; GLaBIOS 0.2.6|TurboXT 3.1"},
	{"virtualxt_gdb", "GDB server; " + ("false|true" when #config(VXT_GDBSTUB, false) else "false")},
	{"virtualxt_gdb_halt", "Wait for debugger; " + ("false|true" when #config(VXT_GDBSTUB, false) else "false")},
	{},
}

write_default_disk_image :: proc(reset := false) -> string {
	using retro_callbacks.vfs

	save_dir: cstring
	if !retro_callbacks.environment(retro.ENVIRONMENT_GET_SAVE_DIRECTORY, &save_dir) {
		log.error("Could not get save directory!")
		return ""
	}

	str := [?]string{string(save_dir), "virtualxt_default.img"}
	img_path := strings.join(str[:], "/", context.temp_allocator)
	cimg_path := strings.clone_to_cstring(img_path, context.temp_allocator)

	data: []byte
	when !#config(VXT_EXTERNAL_HEAP, false) {
		data = #load(DEFAULT_DISK_IMAGE, []byte)
	}

	fp := open(cimg_path, retro.VFS_FILE_ACCESS_READ, 0)
	defer close(fp)

	if ((fp == nil) || reset) && (len(data) > 0) {
		if fp = open(cimg_path, retro.VFS_FILE_ACCESS_WRITE, 0); fp == nil {
			log.error("Could not open default disk image for write!")
			return ""
		}

		if write(fp, &data[0], u64(len(data))) != i64(len(data)) {
			log.error("Could not open default disk image for write!")
			return ""
		}
		log.info("Default disk image copied!")
	}
	return img_path
}

set_eject_state :: proc "c" (ejected: c.bool) -> c.bool {
	context = default_context

	mounted: byte // 0 == First floppy drive
	machine.configure("disk", "mounted", &mounted)

	if bool(mounted) != ejected {
		return true
	}

	if ejected {
		return machine.configure("disk", "umount", byte(0))
	} else {
		if int(disk_image_index) >= len(disk_images) {
			return false
		}
		return machine.configure("disk", "A", disk_images[disk_image_index])
	}
}

get_eject_state :: proc "c" () -> c.bool {
	context = default_context

	mounted: byte
	machine.configure("disk", "mounted", &mounted)
	return mounted == 0
}

get_image_index :: proc "c" () -> c.uint {
	return c.uint(disk_image_index)
}

set_image_index :: proc "c" (index: c.uint) -> c.bool {
	if int(index) >= len(disk_images) {
		return false
	}
	disk_image_index = uint(index)
	return true
}

get_num_images :: proc "c" () -> c.uint {
	return c.uint(len(disk_images))
}

replace_image_index :: proc "c" (index: c.uint, #by_ptr info: retro.game_info) -> c.bool {
	context = default_context

	assert(int(index) < len(disk_images))
	if info.path == nil {
		return false
	}

	delete(disk_images[index])
	disk_images[index] = strings.clone(string(info.path))
	log.infof("Disk index %d: %s", index, info.path)
	return true
}

add_image_index :: proc "c" () -> c.bool {
	context = default_context
	append(&disk_images, strings.clone(""))
	return true
}

@(export)
retro_set_environment :: proc "c" (cb: retro.environment_t) {
	using retro, runtime.Logger_Level
	context = default_context

	retro_callbacks.environment = cb

	logging: log_callback
	if cb(ENVIRONMENT_GET_LOG_INTERFACE, &logging) {
		logger_proc :: proc(data: rawptr, level: runtime.Logger_Level, text: string, options: runtime.Logger_Options, location := #caller_location) {
			lv: log_level
			switch (level) {
			case .Debug:
				lv = .LOG_DEBUG
			case .Info:
				lv = .LOG_INFO
			case .Warning:
				lv = .LOG_WARN
			case .Error, .Fatal:
				lv = .LOG_ERROR
			}

			cstr := strings.clone_to_cstring(text)
			log_printf_t(data)(lv, "%s\n", cstr)
			delete(cstr)
		}

		default_context.logger = runtime.Logger{logger_proc, rawptr(logging.log), .Debug, nil}
		context = default_context
	}

	cb(ENVIRONMENT_SET_VARIABLES, &options)

	save_dir: cstring
	no_game := retro_callbacks.environment(ENVIRONMENT_GET_SAVE_DIRECTORY, &save_dir)
	cb(ENVIRONMENT_SET_SUPPORT_NO_GAME, &no_game)
}

@(export)
retro_reset :: proc "c" () {
	context = default_context
	check_variables()
	machine.reset()
}

check_variables :: proc() {
	var := retro.variable {
		key = "virtualxt_cpu_frequency",
	}
	if (retro_callbacks.environment(retro.ENVIRONMENT_GET_VARIABLE, &var) && (var.value != nil)) {
		log.infof("Configure CPU frequency: %s", var.value)
		n, _, ok := strconv.parse_f64_prefix(string(var.value))
		assert(ok)
		machine.configure("machine", "cpu_frequency", uint(n * 1000000))
	}

	var = retro.variable {
		key = "virtualxt_reset_default_disk",
	}
	if (retro_callbacks.environment(retro.ENVIRONMENT_GET_VARIABLE, &var) && (var.value != nil)) {
		reset_default_disk, _ = strconv.parse_bool(string(var.value))
	}

	var = retro.variable {
		key = "virtualxt_boot_priority",
	}
	if (retro_callbacks.environment(retro.ENVIRONMENT_GET_VARIABLE, &var) && (var.value != nil)) {
		floppy_boot_prio = var.value == "FD"
	}

	var = retro.variable {
		key = "virtualxt_video",
	}
	if (retro_callbacks.environment(retro.ENVIRONMENT_GET_VARIABLE, &var) && (var.value != nil)) {
		enable_vga = var.value == "VGA"
	}

	var = retro.variable {
		key = "virtualxt_bios",
	}
	if (retro_callbacks.environment(retro.ENVIRONMENT_GET_VARIABLE, &var) && (var.value != nil)) {
		glabios = strings.has_prefix(string(var.value), "GLaBIOS")
	}

	var = retro.variable {
		key = "virtualxt_ems",
	}
	if (retro_callbacks.environment(retro.ENVIRONMENT_GET_VARIABLE, &var) && (var.value != nil)) {
		enable_ems, _ = strconv.parse_bool(string(var.value))
	}

	var = retro.variable {
		key = "virtualxt_gdb",
	}
	if (retro_callbacks.environment(retro.ENVIRONMENT_GET_VARIABLE, &var) && (var.value != nil)) {
		gdb_server, _ = strconv.parse_bool(string(var.value))
	}

	var = retro.variable {
		key = "virtualxt_gdb_halt",
	}
	if (retro_callbacks.environment(retro.ENVIRONMENT_GET_VARIABLE, &var) && (var.value != nil)) {
		gdb_halt, _ = strconv.parse_bool(string(var.value))
	}
}

setup_machine :: proc(info: ^retro.game_info) {
	using machine

	create()
	check_variables()

	rom.create("bios")
	configure("bios", "name", "BIOS")
	configure("bios", "base", u32(0xFE000))
	if glabios {
		configure("bios", "mem", #load("bios:GLABIOS.ROM", []byte))
	} else {
		configure("bios", "mem", #load("bios:pcxtbios.bin", []byte))
	}

	rom.create("vxtx")
	configure("vxtx", "name", "Disk Extension")
	configure("vxtx", "mem", #load("bios:vxtx.bin", []byte))
	configure("vxtx", "base", u32(0xFD800))

	{
		disk.create()
		configure("disk", "vfs", retro_callbacks.vfs)
		if info != nil {
			configure("disk", "auto", string(info.path))
		} else if path := write_default_disk_image(reset_default_disk); path != "" {
			configure("disk", "auto", path)
		}

		// Check if floppy drive 0 was mounted.
		mounted: byte
		machine.configure("disk", "mounted", &mounted)

		machine.configure("disk", "boot", byte((bool(mounted) && floppy_boot_prio) ? 0 : 0x80))
		if bool(mounted) {
			append(&disk_images, strings.clone(string(info.path)))
		}
	}

	set_framebuffer_size :: proc(w, h: uint) {
		frame_buffer.width = w
		frame_buffer.height = h
	}

	if enable_vga {
		rom.create("vgabios")
		configure("vgabios", "name", "VGA BIOS")
		configure("vgabios", "base", u32(0xC0000))
		configure("vgabios", "mem", #load("bios:vgabios.bin", []byte))
		
		vga.create()
		configure("vga", "framebuffer", frame_buffer.memory[:])
		configure("vga", "modeset_callback", set_framebuffer_size)
	} else {
		cga.create()
		configure("cga", "framebuffer", frame_buffer.memory[:])
		configure("cga", "modeset_callback", set_framebuffer_size)
	}
	
	chipset.create()

	if enable_ems {
		ems.create()
	}

	if gdb_server {
		gdb.create()
		configure("gdb", "halt", gdb_halt)
	}

	check_variables()
	initialize()
	print_status()
}

@(export)
retro_load_game :: proc "c" (info: ^retro.game_info) -> c.bool {
	context = default_context

	fmt := retro.pixel_format.PIXEL_FORMAT_XRGB8888
	if !retro_callbacks.environment(retro.ENVIRONMENT_SET_PIXEL_FORMAT, &fmt) {
		log.error("XRGB8888 is not supported!")
		return false
	}

	disk_control := retro.disk_control_callback {
		set_eject_state,
		get_eject_state,
		get_image_index,
		set_image_index,
		get_num_images,
		replace_image_index,
		add_image_index,
	}
	retro_callbacks.environment(retro.ENVIRONMENT_SET_DISK_CONTROL_INTERFACE, &disk_control)

	frame_time := retro.frame_time_callback{frame_time_callback, 1000000 / 60}
	if !retro_callbacks.environment(retro.ENVIRONMENT_SET_FRAME_TIME_CALLBACK, &frame_time) {
		log.error("Require the frame time interface!")
		return false
	}

	vfs_info: retro.vfs_interface_info
	if retro_callbacks.environment(retro.ENVIRONMENT_GET_VFS_INTERFACE, &vfs_info) && (vfs_info.iface != nil) {
		retro_callbacks.vfs = vfs_info.iface
	} else {
		log.error("Require the VFS interface!")
		return false
	}

	frame_buffer.memory = make([dynamic]u32, 720 * 480)
	setup_machine(info)

	kbcb := retro.keyboard_callback{keyboard_callback}
	retro_callbacks.environment(retro.ENVIRONMENT_SET_KEYBOARD_CALLBACK, &kbcb)

	acb := retro.audio_callback{audio_callback, nil}
	retro_callbacks.environment(retro.ENVIRONMENT_SET_AUDIO_CALLBACK, &acb)

	show_message("Ensure you have 'Game Focus' mode set to 'Detect' under Setting > Input, or press the 'Scroll Lock' key", 6 * time.Second)
	return true
}

frame_time_callback :: proc "c" (usec: retro.usec_t) {
	delta_time = usec
}

@(export)
retro_run :: proc "c" () {
	context = default_context
	defer free_all(context.temp_allocator)

	updated := false
	if retro_callbacks.environment(retro.ENVIRONMENT_GET_VARIABLE_UPDATE, &updated) && updated {
		check_variables()
	}

	retro_callbacks.input_poll()

	cpu_freq := i64(machine.frequency())
	cycles := i64(delta_time) * (cpu_freq / 1000000)

	// Cap the number of cycles to what would be executed during a 30hz refresh rate.
	// So if we drop below 30fps the emulated clock would slow down.
	if n := cpu_freq / 30; cycles > n {
		log.warnf("Can't keep up! Dropping cycles: %d (%dms)", cycles - n, uint((f64(cycles - n) / f64(cpu_freq)) * 1000))
		cycles = n
	}

	if _, ok := machine.step(uint(cycles)); !ok {
		@(static) msg_timer: time.Time
		if time.since(msg_timer) > (5 * time.Second) {
			msg_timer = time.now()
			show_message("Invalid opcodes! This could be because you are running incompatible software")
		}
	}

	using frame_buffer
	retro_callbacks.video(&memory[0], u32(width), u32(height), width * 4)
}

@(export)
retro_unload_game :: proc "c" () {
	context = default_context
	machine.destroy()
	delete(frame_buffer.memory)
}

@(export)
retro_get_system_info :: proc "c" (info: ^retro.system_info) {
	info^ = retro.system_info {
		library_name     = "VirtualXT",
		library_version  = VXT_VERSION,
		block_extract    = true,
		need_fullpath    = true,
		valid_extensions = "img",
	}
}

@(export)
retro_get_system_av_info :: proc "c" (info: ^retro.system_av_info) {
	info^ = retro.system_av_info {
		geometry = retro.game_geometry{base_width = 640, base_height = 200, max_width = 720, max_height = 480, aspect_ratio = 4.0 / 3.0},
		timing = retro.system_timing{sample_rate = AUDIO_FREQUENCY, fps = 60},
	}
}

@(export)
retro_set_audio_sample :: proc "c" (cb: retro.audio_sample_t) {
	retro_callbacks.audio = cb
}

@(export)
retro_set_input_poll :: proc "c" (cb: retro.input_poll_t) {
	retro_callbacks.input_poll = cb
}

@(export)
retro_set_input_state :: proc "c" (cb: retro.input_state_t) {
	retro_callbacks.input_state = cb
}

@(export)
retro_set_video_refresh :: proc "c" (cb: retro.video_refresh_t) {
	retro_callbacks.video = cb
}

show_message :: proc(message: string, duration := time.Second * 3) {
	msg := retro.message{strings.clone_to_cstring(message), c.uint(time.duration_seconds(duration) * 60)}
	retro_callbacks.environment(retro.ENVIRONMENT_SET_MESSAGE, &msg)
	delete(msg.msg)
}

audio_callback :: proc "c" () {
	context = default_context
	ppi, ok := machine.peripheral_from_class(machine.Peripheral_Class.PPI)
	assert(ok)

	sample := chipset.ppi_generate_sample(ppi, AUDIO_FREQUENCY)
	retro_callbacks.audio(sample, sample)
}

keyboard_callback :: proc "c" (down: c.bool, keycode: retro.key, character: c.uint32_t, key_modifiers: c.uint16_t) {
	context = default_context
	using retro

	xt_key: byte
	#partial switch keycode {
	case .K_ESCAPE:
		xt_key = 0x01
	case .K_1:
		xt_key = 0x02
	case .K_2:
		xt_key = 0x03
	case .K_3:
		xt_key = 0x04
	case .K_4:
		xt_key = 0x05
	case .K_5:
		xt_key = 0x06
	case .K_6:
		xt_key = 0x07
	case .K_7:
		xt_key = 0x08
	case .K_8:
		xt_key = 0x09
	case .K_9:
		xt_key = 0x0A
	case .K_0:
		xt_key = 0x0B
	case .K_MINUS:
		xt_key = 0x0C
	case .K_EQUALS:
		xt_key = 0xD
	case .K_BACKSPACE:
		xt_key = 0x0E
	case .K_TAB:
		xt_key = 0x0F
	case .K_q:
		xt_key = 0x10
	case .K_w:
		xt_key = 0x11
	case .K_e:
		xt_key = 0x12
	case .K_r:
		xt_key = 0x13
	case .K_t:
		xt_key = 0x14
	case .K_y:
		xt_key = 0x15
	case .K_u:
		xt_key = 0x16
	case .K_i:
		xt_key = 0x17
	case .K_o:
		xt_key = 0x18
	case .K_p:
		xt_key = 0x19
	case .K_LEFTBRACKET:
		xt_key = 0x1A
	case .K_RIGHTBRACKET:
		xt_key = 0x1B
	case .K_RETURN:
		xt_key = 0x1C
	case .K_LCTRL, .K_RCTRL:
		xt_key = 0x1D
	case .K_a:
		xt_key = 0x1E
	case .K_s:
		xt_key = 0x1F
	case .K_d:
		xt_key = 0x20
	case .K_f:
		xt_key = 0x21
	case .K_g:
		xt_key = 0x22
	case .K_h:
		xt_key = 0x23
	case .K_j:
		xt_key = 0x24
	case .K_k:
		xt_key = 0x25
	case .K_l:
		xt_key = 0x26
	case .K_SEMICOLON:
		xt_key = 0x27
	case .K_QUOTE:
		xt_key = 0x28
	case .K_BACKQUOTE:
		xt_key = 0x29
	case .K_LSHIFT:
		xt_key = 0x2A
	case .K_BACKSLASH:
		xt_key = 0x2B // INT2
	case .K_z:
		xt_key = 0x2C
	case .K_x:
		xt_key = 0x2D
	case .K_c:
		xt_key = 0x2E
	case .K_v:
		xt_key = 0x2F
	case .K_b:
		xt_key = 0x30
	case .K_n:
		xt_key = 0x31
	case .K_m:
		xt_key = 0x32
	case .K_COMMA:
		xt_key = 0x33
	case .K_PERIOD:
		xt_key = 0x34
	case .K_SLASH:
		xt_key = 0x35
	case .K_RSHIFT:
		xt_key = 0x36
	case .K_PRINT:
		xt_key = 0x37
	case .K_LALT, .K_RALT:
		xt_key = 0x38
	case .K_SPACE:
		xt_key = 0x39
	case .K_CAPSLOCK:
		xt_key = 0x3A
	case .K_F1:
		xt_key = 0x3B
	case .K_F2:
		xt_key = 0x3C
	case .K_F3:
		xt_key = 0x3D
	case .K_F4:
		xt_key = 0x3E
	case .K_F5:
		xt_key = 0x3F
	case .K_F6:
		xt_key = 0x40
	case .K_F7:
		xt_key = 0x41
	case .K_F8:
		xt_key = 0x42
	case .K_F9:
		xt_key = 0x43
	case .K_F10:
		xt_key = 0x44
	case .K_NUMLOCK:
		xt_key = 0x45
	case .K_SCROLLOCK:
		xt_key = 0x46
	case .K_KP7, .K_HOME:
		xt_key = 0x47
	case .K_KP8, .K_UP:
		xt_key = 0x48
	case .K_KP9, .K_PAGEUP:
		xt_key = 0x49
	case .K_KP_MINUS:
		xt_key = 0x4A
	case .K_KP4, .K_LEFT:
		xt_key = 0x4B
	case .K_KP5:
		xt_key = 0x4C
	case .K_KP6, .K_RIGHT:
		xt_key = 0x4D
	case .K_KP_PLUS:
		xt_key = 0x4E
	case .K_KP1, .K_END:
		xt_key = 0x4F
	case .K_KP2, .K_DOWN:
		xt_key = 0x50
	case .K_KP3, .K_PAGEDOWN:
		xt_key = 0x51
	case .K_KP0, .K_INSERT:
		xt_key = 0x52
	case .K_KP_PERIOD, .K_DELETE:
		xt_key = 0x53
	}

	if xt_key != 0 {
		if !down {
			xt_key |= 0x80
		}

		ppi, ok := machine.peripheral_from_class(machine.Peripheral_Class.PPI)
		assert(ok)
		chipset.ppi_push_event(ppi, xt_key)
	}
}
