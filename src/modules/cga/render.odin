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

blit_char :: proc(using cga: ^CGA, ch: int, attr: byte, x, y: int) {
	bg_color_index := (attr & 0x70) >> 4
	fg_color_index := attr & 0xF

	if bool(attr & 0x80) {
		if bool(mode_ctrl_reg & 0x20) {
			fg_color_index = cursor_blink ? bg_color_index : fg_color_index
		} else {
			// High intensity!
			bg_color_index += 8
		}
	}

	bg_color := palette[bg_color_index]
	fg_color := palette[fg_color_index]
	width := bool(mode_ctrl_reg & 1) ? 640 : 320
	ch_idx := ch

	start := 0
	end := 7

	if ch < 0 {
		ch_idx = 0xDB
		start = int(cursor_start)
		end = int(cursor_end)
	}

	for {
		n := start % 8
		glyph_line := font[ch_idx * 8 + n]

		for j := 0; j < 8; j += 1 {
			mask := byte(0x80) >> uint(j)
			color := bool(glyph_line & mask) ? fg_color : bg_color
			offset := width * (y + n) + x + j
			frame_buffer[offset] = color
		}

		if n == end {
			break
		}
		start += 1
	}
}

render_scanline :: proc(using cga: ^CGA, y: uint) {
	if (y >= 200) || !bool(mode_ctrl_reg & 2) {
		return
	}

	is_dirty = true
	border_color := color_ctrl_reg & 0xF

	// In high-resolution mode?
	if bool(mode_ctrl_reg & 0x10) {	
		for x: uint; x < 640; x += 1 {
			addr := (y >> 1) * 80 + (y & 1) * 8192 + (x >> 3)
			pixel := (mem[sanitaze_address(addr)] >> (7 - (x & 7))) & 1
			color := palette[pixel * border_color]
			frame_buffer[y * 640 + x] = color
		}	
	} else {
		intensity := ((color_ctrl_reg >> 4) & 1) << 3
		pal5 := bool(mode_ctrl_reg & 4)
		color_index := pal5 ? 16 : ((color_ctrl_reg >> 5) & 1)

		for x: uint; x < 320; x += 1 {
			addr := (y >> 1) * 80 + (y & 1) * 8192 + (x >> 2)
			pixel := (mem[sanitaze_address(addr)] >> (6 - (x & 3) * 2)) & 3
			color := palette[(pixel != 0) ? (pixel * 2 + color_index + intensity) : border_color]
			frame_buffer[y * 320 + x] = color
		}
	}
}

render_textmode :: proc(using cga: ^CGA) {
	if !is_dirty || bool(mode_ctrl_reg & 2) {
		return
	}
	
	is_dirty = false
	video_page := (int(crt_reg[0xC]) << 8) + int(crt_reg[0xD])
	num_col := bool(mode_ctrl_reg & 1) ? 80 : 40
	num_char := num_col * 25
	
	for i := 0; i < num_char; i += 1 {
		cell_offset := video_page + i * 2
		ch := mem[sanitaze_address(cell_offset)]
		attr := mem[sanitaze_address(cell_offset + 1)]
		
		blit_char(cga, int(ch), attr, (i % num_col) * 8, (i / num_col) * 8)
	}

	if cursor_blink && cursor_visible {
		x := int(cursor_offset) % num_col
		y := int(cursor_offset) / num_col
		
		if (x < num_col && y < 25) {
			offset := sanitaze_address(video_page + (num_col * 2 * y + x * 2 + 1))
			attr := (mem[sanitaze_address(offset)] & 0x70) | 0xF
			
			blit_char(cga, -1, attr, x * 8, y * 8)
		}
	}
}
