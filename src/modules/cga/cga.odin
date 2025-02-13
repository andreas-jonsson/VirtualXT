#+private

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

package cga

import "vxt:machine/peripheral"

MEMORY_SIZE :: 0x10000
MEMORY_BASE :: 0xB8000
SCANLINE_TIMING :: 16
CURSOR_TIMING :: 333333

palette := []u32 {
	0x000000,
	0x0000AA,
	0x00AA00,
	0x00AAAA,
	0xAA0000,
	0xAA00AA,
	0xAA5500,
	0xAAAAAA,
	0x555555,
	0x5555FF,
	0x55FF55,
	0x55FFFF,
	0xFF5555,
	0xFF55FF,
	0xFFFF55,
	0xFFFFFF,

	// This is the CGA (black/cyan/red/white) palette.
	0x000000,
	0x000000,
	0x00AAAA,
	0x000000,
	0xAA0000,
	0x000000,
	0xAAAAAA,
	0x000000,
	0x000000,
	0x000000,
	0x55FFFF,
	0x000000,
	0xFF5555,
	0x000000,
	0xFFFFFF,
	0x000000,
}

CGA :: struct {
	mem:                                                 [MEMORY_SIZE]byte,
	is_dirty:                                            bool,
	frame_buffer:                                        []u32,
	modeset_callback:                                    proc(_: uint, _: uint),
	cursor_blink, cursor_visible:                        bool,
	cursor_start, cursor_end:                            byte,
	cursor_offset:                                       u16,
	scanline_timer:                                      peripheral.Peripheral_Timer_ID,
	scanline, retrace:                                   uint,
	mode_ctrl_reg, color_ctrl_reg, status_reg, crt_addr: byte,
	crt_reg:                                             [0x100]byte,
}

install :: proc(cga: ^CGA) -> bool {
	peripheral.register_memory_address_range(cga, MEMORY_BASE, (MEMORY_BASE + MEMORY_SIZE) - 1)
	peripheral.register_io_address_range(cga, 0x3D0, 0x3DF)

	peripheral.register_timer(cga, CURSOR_TIMING)
	cga.scanline_timer = peripheral.register_timer(cga, SCANLINE_TIMING)

	return true
}

config :: proc(cga: ^CGA, name, key: string, value: any) -> (ok := true) {
	if name != "cga" {
		return
	}

	switch key {
	case "framebuffer":
		cga.frame_buffer = value.([]u32)
		assert(len(cga.frame_buffer) >= 640 * 200)
	case "modeset_callback":
		cga.modeset_callback = value.(proc(w, h: uint))
		cga.modeset_callback(640, 200)
	case:
		ok = false
	}
	return
}

sanitaze_address :: proc(#any_int ptr: u32) -> u32 {
	return ptr & (MEMORY_SIZE - 1)
}

read :: proc(cga: ^CGA, addr: u32) -> byte {
	return cga.mem[sanitaze_address((addr - MEMORY_BASE) & 0x3FFF)]
}

write :: proc(cga: ^CGA, addr: u32, data: byte) {
	cga.mem[sanitaze_address((addr - MEMORY_BASE) & 0x3FFF)] = data
	cga.is_dirty = true
}

io_in :: proc(using cga: ^CGA, port: u16) -> byte {
	switch port {
	case 0x3D0, 0x3D2, 0x3D4, 0x3D6:
		return crt_addr
	case 0x3D1, 0x3D3, 0x3D5, 0x3D7:
		return crt_reg[crt_addr]
	case 0x3D8:
		return mode_ctrl_reg
	case 0x3D9:
		return color_ctrl_reg
	case 0x3DA:
		return status_reg
	case:
		return 0
	}
}

io_out :: proc(using cga: ^CGA, port: u16, data: byte) {
	is_dirty = true

	switch port {
	case 0x3D0, 0x3D2, 0x3D4, 0x3D6:
		crt_addr = data
	case 0x3D1, 0x3D3, 0x3D5, 0x3D7:
		crt_reg[crt_addr] = data

		switch crt_addr {
		case 0xA:
			cursor_start = data & 0x1F
			cursor_visible = !bool(data & 0x20) && (cursor_start < 8)
		case 0xB:
			cursor_end = data
		case 0xE:
			cursor_offset = (cursor_offset & 0x00FF) | (u16(data) << 8)
		case 0xF:
			cursor_offset = (cursor_offset & 0xFF00) | u16(data)
		}
	case 0x3D8:
		mode_ctrl_reg = data
		if bool(data & 2) {
			modeset_callback(bool(data & 0x10) ? 640 : 320, 200)
		} else {
			modeset_callback(bool(data & 1) ? 640 : 320, 200)
		}
	case 0x3D9:
		color_ctrl_reg = data
	}
}

timer :: proc(using cga: ^CGA, id: peripheral.Peripheral_Timer_ID, _: uint) {
	if scanline_timer == id {
		status_reg = 6
		status_reg |= (retrace == 3) ? 1 : 0
		status_reg |= (scanline >= 224) ? 8 : 0

		retrace += 1
		if retrace == 4 {
			render_scanline(cga, scanline)
			retrace = 0
			scanline += 1
		}

		if scanline == 256 {
			render_textmode(cga)
			scanline = 0
		}
	} else {
		cursor_blink = !cursor_blink
		is_dirty = true
	}
}

reset :: proc(using cga: ^CGA) -> bool {
	cursor_visible = true
	cursor_start = 6
	cursor_end = 7
	cursor_offset = 0
	is_dirty = true

	mode_ctrl_reg = 1
	color_ctrl_reg = 0x20
	status_reg = 0

	return true
}
