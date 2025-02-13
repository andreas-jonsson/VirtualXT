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

package processor

Mod_Reg_Rm :: struct {
	using _: bit_field byte {
		rm:  u8 | 3,
		reg: u8 | 3,
		mod: u8 | 2,
	},
	disp:    u16,
}

decode_ea_offset :: proc() {
	using registers, state.instruction

	switch mode.rm {
	case 0:
		ea_offset = bx + si + mode.disp
	case 1:
		ea_offset = bx + di + mode.disp
	case 2:
		ea_offset = bp + si + mode.disp
	case 3:
		ea_offset = bp + di + mode.disp
	case 4:
		ea_offset = si + mode.disp
	case 5:
		ea_offset = di + mode.disp
	case 6:
		ea_offset = (mode.mod == 0) ? mode.disp : bp + mode.disp
	case 7:
		ea_offset = bx + mode.disp
	}
}

decode_mod_reg_rm :: proc() {
	using state.instruction

	d := decode_fetch_byte()
	mode.mod = (d >> 6) & 3
	mode.reg = (d >> 3) & 7
	mode.rm = d & 7
	mode.disp = 0

	if (mode.mod == 0) && (mode.rm == 6) {
		mode.disp = decode_fetch_word()
	} else if (mode.mod == 0) || (mode.mod == 3) {
		mode.disp = 0
	} else if mode.mod == 1 {
		mode.disp = u16(i8(decode_fetch_byte()))
	} else if mode.mod == 2 {
		mode.disp = decode_fetch_word()
	}

	if mode.mod < 3 {
		decode_ea_offset()
	}
}

load_eb :: proc() -> byte {
	using state.instruction
	if mode.mod == 3 {
		return get_byte_register(mode.rm)^
	}
	return read_segment_byte(get_ea_segment(), ea_offset)
}

load_rb :: proc() -> byte {
	return get_byte_register(state.instruction.mode.reg)^
}

load_ew :: proc() -> u16 {
	using state.instruction
	if mode.mod == 3 {
		return get_word_register(mode.rm)^
	}
	return read_segment_word(get_ea_segment(), ea_offset)
}

load_rw :: proc() -> u16 {
	return get_word_register(state.instruction.mode.reg)^
}

load_rw_op :: proc() -> u16 {
	return get_word_register(state.instruction.reg_gen)^
}

load_sr :: proc() -> u16 {
	return get_segment_register(Segment(state.instruction.mode.reg & 3))^
}

load_m1616 :: proc() -> (reg, seg: u16) {
	using state
	ea_seg := get_ea_segment()
	reg = read_segment_word(ea_seg, instruction.ea_offset)
	seg = read_segment_word(ea_seg, instruction.ea_offset + 2)
	return
}

store_eb :: proc(v: byte) {
	using state.instruction
	if mode.mod == 3 {
		get_byte_register(mode.rm)^ = v
		return
	}
	write_segment_byte(get_ea_segment(), ea_offset, v)
}

store_rb :: proc(v: byte) {
	get_byte_register(state.instruction.mode.reg)^ = v
}

store_ew :: proc(v: u16) {
	using state.instruction
	if mode.mod == 3 {
		get_word_register(mode.rm)^ = v
		return
	}
	write_segment_word(get_ea_segment(), ea_offset, v)
}

store_rw :: proc(v: u16) {
	get_word_register(state.instruction.mode.reg)^ = v
}

store_rb_op :: proc(v: byte) {
	get_byte_register(state.instruction.reg_gen)^ = v
}

store_rw_op :: proc(v: u16) {
	get_word_register(state.instruction.reg_gen)^ = v
}

store_sr :: proc(v: u16) {
	get_segment_register(Segment(state.instruction.mode.reg & 3))^ = v
}
