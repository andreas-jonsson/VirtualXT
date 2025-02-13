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

import "core:slice"

FONT_OFFSETS := [?]int{ 0x0000, 0x4000, 0x8000, 0xC000, 0x2000, 0x6000, 0xA000, 0xE000 }

color_lookup :: proc(using vga: ^VGA, index: byte) -> u32 {
	color_select := regs.attr_reg[0x14]
	idx := (regs.attr_reg[16 + index] & 0x3F) | ((color_select & 0xC) << 4)

	mode_ctrl := regs.attr_reg[0x10]
	if bool(mode_ctrl & 0x80) {
		idx = (idx & 0xCF) | ((color_select & 3) << 4)
	}

	// TODO: Fix this!
	color := palette[idx]
	red := (color & 0xFF0000) >> 16
	green := (color & 0xFF00) >> 8
	blue := color & 0xFF

	s := slice.bytes_from_ptr(rawptr(&color), 4)
	s[2] = byte(red)
	s[1] = byte(green)
	s[0] = byte(blue)
	s[3] = 0xFF
	
	return (^u32)(rawptr(&s[0]))^
}

blit_char :: proc(vga: ^VGA, ch: int, attr: byte, x, y: int) {
	using vga.regs

	bg_color_index := (attr & 0x70) >> 4
	fg_color_index := attr & 0xF

	if bool(attr & 0x80) {
		mode_ctrl := attr_reg[0x10]
		if bool(mode_ctrl & 8) {
			fg_color_index = vga.cursor_blink ? bg_color_index : fg_color_index
		} else {
			// High intensity!
			bg_color_index += 8
		}
	}

	bg_color := color_lookup(vga, bg_color_index)
	fg_color := color_lookup(vga, fg_color_index)

	char_map_reg := seq_reg[0x3]
	font_a := ((char_map_reg >> 3) & 4) | ((char_map_reg >> 2) & 3)
	font_b := ((char_map_reg >> 2) & 4) | (char_map_reg & 3)
	font := bool(attr & 8) ? FONT_OFFSETS[font_b] : FONT_OFFSETS[font_a]

	// TODO: Fix this! We only run at 640 in textmode.
	width := (vga.width >= 640) ? 640 : 320
	ch_idx := ch

	start := 0
	end := 15

	if ch < 0 {
		ch_idx = 0xDB
		start = int(vga.cursor_start)
		end = int(vga.cursor_end)
	}

	for {
		n := start % 16
		glyph_line := vga.mem[font + ch_idx * 32 + n]

		for j := 0; j < 8; j += 1 {
			mask := byte(0x80) >> uint(j)
			color := bool(glyph_line & mask) ? fg_color : bg_color
			offset := width * (y + n) + x + j
			vga.frame_buffer[offset] = color
		}

		if n == end {
			break
		}
		start += 1
	}
}

render_textmode :: proc(vga: ^VGA) {
	using vga, vga.regs

	if !is_dirty || !textmode {
		return
	}
	
	is_dirty = false
	video_page := (int(crt_reg[0xC]) << 8) + int(crt_reg[0xD])
	num_col := (width > 320) ? 80 : 40
	num_char := num_col * 25
	
	for i := 0; i < num_char; i += 1 {
		cell_offset := TEXTMODE_BASE + video_page + i * 2
		ch := mem[sanitaze_address(cell_offset)]
		attr := mem[sanitaze_address(cell_offset + 1)]
		
		blit_char(vga, int(ch), attr, (i % num_col) * 8, (i / num_col) * 16)
	}

	if cursor_blink && cursor_visible {
		x := int(cursor_offset) % num_col
		y := int(cursor_offset) / num_col
		
		if (x < num_col && y < 25) {
			offset := sanitaze_address(video_page + (num_col * 2 * y + x * 2 + 1))
			attr := (mem[sanitaze_address(offset)] & 0x70) | 0xF
			
			blit_char(vga, -1, attr, x * 8, y * 16)
		}
	}
}
