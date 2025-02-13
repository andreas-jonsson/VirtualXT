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

package vga

import "core:log"

import "vxt:machine/peripheral"

PLANE_SIZE :: 0x10000
MEMORY_SIZE :: 0x40000
MEMORY_BASE :: 0xA0000
TEXTMODE_BASE :: 0x18000
SCANLINE_TIMING :: 16
CURSOR_TIMING :: 333333

VGA :: struct {
	mem:                           [MEMORY_SIZE]byte,
	is_dirty:                      bool,
	frame_buffer:                  []u32,
	modeset_callback:              proc(_: uint, _: uint),
	cursor_blink, cursor_visible:  bool,
	cursor_start, cursor_end:      byte,
	cursor_offset:                 u16,
	scanline_timer, retrace_timer, refresh_timer: peripheral.Peripheral_Timer_ID,
	width, height:                 uint,
	bpp:                           byte,
	textmode:                      bool,
	mem_latch:                     [4]byte,
	palette:                       [0x100]u32,
	regs:                          struct {
		feature_ctrl_reg, status_reg:                                     byte,
		flip_3C0:                                                         bool,
		misc_output, vga_enable, pixel_mask:                              byte,
		dac_state:                                                        byte,
		pal_rgb:                                                          u32,
		pal_read_index, pal_read_latch, pal_write_index, pal_write_latch: byte,
		crt_addr, attr_addr, seq_addr, gfx_addr:                          byte,
		crt_reg, attr_reg, seq_reg, gfx_reg:                              [0x100]byte,
	},
}

update_video_mode :: proc(vga: ^VGA) {
	using vga.regs

	dots: uint = bool(seq_reg[1] & 1) ? 8 : 9
	vga.width = uint((crt_reg[1] + 1) - ((crt_reg[5] & 0x60) >> 5)) * dots
	vga.height = (uint(crt_reg[0x12]) | (bool(crt_reg[7] & 2) ? 0x100 : 0) | (bool(crt_reg[7] & 0x40) ? 0x200 : 0)) + 1

	htotal := uint(crt_reg[0] + 5)
	vtotal := uint(crt_reg[6]) | (bool(crt_reg[7] & 1) ? 0x100 : 0) | (bool(crt_reg[7] & 0x20) ? 0x200 : 0)
	pixel_clock: f64 = bool(misc_output & 4) ? 28322000 : 25175000

	if bool(crt_reg[9] & 0x80) {
		vga.height >>= 1
	}

	vga.bpp = 4
	vga.textmode = true

	if bool(attr_reg[0x10] & 1) {
		vga.textmode = false

		switch (gfx_reg[5] >> 5) & 3 {
		case 0:
			vga.bpp = ((attr_reg[0x12] & 0xF) == 1) ? 1 : 4
		case 1:
			vga.bpp = 2
		case 2, 3:
			vga.bpp = 8

			// TODO: We should NOT have to adjust this here.
			vga.width = 320
			vga.height = 200
		}
	}

	// TODO: Fix this! We only run at 640 in textmode.
	//vga.width = clamp(vga.width, 160, 720)
	vga.width = clamp(vga.width, 160, 640)
	vga.height = clamp(vga.height, 100, 480)

	freq_div := f64(htotal * vtotal * dots)
	interval_us := (freq_div > 0) ? uint(500000 / (pixel_clock / freq_div)) : 0
	//vxt_system_set_timer_interval(VXT_GET_SYSTEM(v), v->retrace_timer, interval_us)

	freq_div = f64(htotal * dots)
	interval_us = (freq_div > 0) ? uint(500000 / (pixel_clock / freq_div)) : 0
	//vxt_system_set_timer_interval(VXT_GET_SYSTEM(v), v->scanline_timer, interval_us)

	vga.modeset_callback(vga.width, vga.height)

	log.debugf(
		"Video Mode: %dx%d %dbpp %s@ %.02fHz%s",
		vga.width,
		vga.height,
		vga.bpp,
		bool(seq_reg[4] & 8) ? "CHAINED " : "",
		pixel_clock / f64(htotal * vtotal * uint(dots)),
		vga.textmode ? " (textmode)" : "",
	)
}

install :: proc(vga: ^VGA) -> bool {
	using peripheral
	register_memory_address_range(vga, MEMORY_BASE, (MEMORY_BASE + 0x20000) - 1)

	register_timer(vga, CURSOR_TIMING)
	vga.retrace_timer = register_timer(vga)
	vga.scanline_timer = register_timer(vga)
	vga.refresh_timer = register_timer(vga, 1000000 / 60)

	register_io_address_at(vga, 0x3D4) // R/W: CRT Index
	register_io_address_at(vga, 0x3D5) // R/W: CRT Data
	register_io_address_at(vga, 0x3DA) // W: Feature Control

	register_io_address_at(vga, 0x3C0) // R/W: Attribute Controller Index
	register_io_address_at(vga, 0x3C1) // R/W: Attribute Data
	register_io_address_at(vga, 0x3C2) // W: Misc Output, R: Input Status 0
	register_io_address_at(vga, 0x3C3) // R/W: VGA Enable
	register_io_address_at(vga, 0x3C4) // R/W: Sequencer Index
	register_io_address_at(vga, 0x3C5) // R/W: Sequencer Data
	register_io_address_at(vga, 0x3C6) // R: DAC State Register or Pixel Mask
	register_io_address_at(vga, 0x3C7) // R: DAC State
	register_io_address_at(vga, 0x3C8) // R/W: Pixel Address
	register_io_address_at(vga, 0x3C9) // R/W: Color Data
	register_io_address_at(vga, 0x3CA) // R: Feature Control
	register_io_address_at(vga, 0x3CC) // R: Misc Output
	register_io_address_at(vga, 0x3CE) // R/W: Graphics Controller Index
	register_io_address_at(vga, 0x3CF) // R/W: Graphics Data

	register_io_address_at(vga, 0xAFFF) // R/W: Plane System Latch

	// Auto configure VGA
	switches: byte
	peripheral_interface.configure("chipset", "get_switches", &switches)
	peripheral_interface.configure("chipset", "set_switches", switches & 0xCF)
	
	return true
}

config :: proc(vga: ^VGA, name, key: string, value: any) -> (ok := true) {
	if name != "vga" {
		return
	}

	switch key {
	case "framebuffer":
		vga.frame_buffer = value.([]u32)
		assert(len(vga.frame_buffer) >= 720 * 480)
	case "modeset_callback":
		vga.modeset_callback = value.(proc(w, h: uint))
		vga.modeset_callback(640, 200)
	case:
		ok = false
	}
	return
}

sanitaze_address :: proc(#any_int ptr: u32) -> u32 {
	return ptr & (MEMORY_SIZE - 1)
}

read :: proc(vga: ^VGA, addr: u32) -> byte {
	a := sanitaze_address(addr - MEMORY_BASE)
	if vga.textmode || bool(vga.regs.seq_reg[4] & 8) {
		return vga.mem[a]
	}
	
	return 0
}

write :: proc(vga: ^VGA, addr: u32, data: byte) {
	a := sanitaze_address(addr - MEMORY_BASE)
	vga.is_dirty = true

	if vga.textmode || bool(vga.regs.seq_reg[4] & 8) {
		vga.mem[a] = data
		return
	}
	
	vga.mem[a] = 0
}

io_in :: proc(vga: ^VGA, port: u16) -> byte {
	using vga, vga.regs

	switch port {
	case 0x3C0:
		return attr_addr
	case 0x3C1:
		return attr_reg[attr_addr]
	case 0x3C2, 0x3DA:
		flip_3C0 = false
		return status_reg // Should be status 0?
	case 0x3C3:
		return vga_enable
	case 0x3C4:
		return seq_addr
	case 0x3C5:
		return seq_reg[seq_addr]
	case 0x3C6:
		return pixel_mask
	case 0x3C7:
		return dac_state
	case 0x3C8:
		return pal_read_index
	case 0x3C9:
		switch pal_read_latch {
		case 0:
			color := palette[pal_read_index]
			pal_read_latch += 1
			return byte(color >> 18) & 0x3F
		case 1:
			color := palette[pal_read_index]
			pal_read_latch += 1
			return byte(color >> 10) & 0x3F
		case:
			color := palette[pal_read_index]
			pal_read_index += 1
			pal_read_latch = 0
			return byte(color >> 2) & 0x3F
		}
	case 0x3CA:
		return feature_ctrl_reg
	case 0x3CC:
		return misc_output
	case 0x3CE:
		return gfx_addr
	case 0x3CF:
		return gfx_reg[gfx_addr]
	case 0x3D4:
		return crt_addr
	case 0x3D5:
		return crt_reg[crt_addr]
	case 0xAFFF:
		return mem_latch[gfx_addr & 3]
	case:
		return 0
	}
}

io_out :: proc(vga: ^VGA, port: u16, data: byte) {
	using vga, vga.regs
	is_dirty = true

	switch port {
	case 0x3C0, 0x3C1:
		if (flip_3C0) {
			attr_reg[attr_addr] = data
		} else {
			attr_addr = data
		}
		flip_3C0 = !flip_3C0
	case 0x3C2:
		misc_output = data
	case 0x3C3:
		vga_enable = data
	case 0x3C4:
		seq_addr = data
	case 0x3C5:
		seq_reg[seq_addr] = data
		update_video_mode(vga)
	case 0x3C7:
		pal_read_index = data
		pal_read_latch = 0
		dac_state = 0
	case 0x3C8:
		pal_write_index = data
		pal_write_latch = 0
		dac_state = 3
	case 0x3C9:
		value := data & 0x3F
		switch pal_write_latch {
		case 0:
			pal_rgb = u32(value) << 18
			pal_write_latch += 1
		case 1:
			pal_rgb |= u32(value) << 10
			pal_write_latch += 1
		case 2:
			pal_rgb |= u32(value) << 2
			palette[pal_write_index] = pal_rgb
			pal_write_index += 1
			pal_write_latch = 0
		}
	case 0x3CE:
		gfx_addr = data
	case 0x3CF:
		gfx_reg[gfx_addr] = data
		update_video_mode(vga)
	case 0x3D4:
		crt_addr = data
	case 0x3D5:
		crt_reg[crt_addr] = data
		switch crt_addr {
		case 0xA:
			cursor_start = data & 0x1F
			cursor_visible = !bool(data & 0x20) && (cursor_start < 16)
		case 0xB:
			cursor_end = data
		case 0xE:
			cursor_offset = (cursor_offset & 0x00FF) | (u16(data) << 8)
		case 0xF:
			cursor_offset = (cursor_offset & 0xFF00) | u16(data)
		case:
			update_video_mode(vga)
		}
	case 0x3DA:
		feature_ctrl_reg = data
	case 0xAFFF:
		mem_latch[gfx_addr & 3] = data
	}
}

timer :: proc(using vga: ^VGA, id: peripheral.Peripheral_Timer_ID, _: uint) {
	if scanline_timer == id {
		regs.status_reg ~= 1
	} else if retrace_timer == id {
		regs.status_reg ~= 8
	} else if refresh_timer == id {
		render_textmode(vga)
	} else {
		cursor_blink = !cursor_blink
		is_dirty = true
	}
	regs.status_reg |= 6
}

reset :: proc(vga: ^VGA) -> bool {
	vga.is_dirty = true
	vga.regs.status_reg = 0
	return true
}
