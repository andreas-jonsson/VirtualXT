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

import "vxt:machine/peripheral"

MAX_INSTRUCTION_SIZE :: 6

Segment :: enum {
	EXTRA,
	CODE,
	STACK,
	DATA,
}

Exception :: enum byte {
	DIV_ZERO_EXC   = 0,
	DEBUG_STEP_EXC = 1,
	DEBUG_TRAP_EXC = 3,
	OVERFLOW_EXC   = 4,
}

Opcode :: struct #raw_union {
	raw:     byte,
	using _: bit_field byte {
		op:   u8   | 6,
		dir:  bool | 1,
		wide: bool | 1,
	},
}

Instruction :: struct {
	valid:      bool,
	opcode:     Opcode,
	mode:       Mod_Reg_Rm,
	stream:     struct {
		data: [MAX_INSTRUCTION_SIZE]byte,
		size: uint,
		addr: u32,
		ip:   u16,
	},
	ea_offset:  u16,
	rep_prefix: byte,
	ib:         byte,
	iw1, iw2:   u16,
	reg_seg:    Segment, // Decoded segment register target
	reg_gen:    byte, // Decoded general register target
	exec:       proc(),
}

registers: peripheral.Peripheral_CPU_Registers
interrupt_controler: ^peripheral.Peripheral_Callbacks(peripheral.Peripheral)

state: struct {
	instruction:      			Instruction,
	base_ds, base_ss: 			Segment,
	shift_count:      			byte,
	halt, trap:   				bool,
	invert_quotient, div_zero:  bool,
}

check_interrupts :: proc() {
	trap := .TRAP in registers.flags
	interrupt := .INTERRUPT in registers.flags

	if trap && !state.trap {
		state.trap = interrupt
		throw_exception(.DEBUG_STEP_EXC)
	} else if interrupt {
		state.halt = false
		state.trap = false

		if interrupt_controler != nil {
			if n := interrupt_controler.pic.next(peripheral.get_peripheral(interrupt_controler)); n >= 0 {
				throw_exception(Exception(n))
			}
		}
	}
}

get_byte_register :: proc(reg: byte) -> ^byte {
	using registers
	switch reg {
	case 0:
		return &al
	case 1:
		return &cl
	case 2:
		return &dl
	case 3:
		return &bl
	case 4:
		return &ah
	case 5:
		return &ch
	case 6:
		return &dh
	case 7:
		return &bh
	case:
		panic("invalid general register")
	}
}

get_word_register :: proc(reg: byte) -> ^u16 {
	using registers
	switch reg {
	case 0:
		return &ax
	case 1:
		return &cx
	case 2:
		return &dx
	case 3:
		return &bx
	case 4:
		return &sp
	case 5:
		return &bp
	case 6:
		return &si
	case 7:
		return &di
	case:
		panic("invalid general register")
	}
}

get_ea_segment :: proc() -> Segment {
	using state.instruction

	switch mode.rm {
	case 0, 1, 4, 5, 7:
		return state.base_ds
	case 2, 3:
		return state.base_ss
	}

	return (mode.mod == 0) ? state.base_ds : state.base_ss
}

get_segment_register :: proc(seg: Segment) -> ^u16 {
	using registers

	#partial switch seg {
	case .EXTRA:
		return &es
	case .CODE:
		return &cs
	case .STACK:
		return &ss
	case .DATA:
		return &ds
	case:
		panic("invalid segment register")
	}
}

get_physical_address :: proc(seg: Segment, offset: u16) -> u32 {
	return (u32(get_segment_register(seg)^) << 4) + u32(offset)
}

read_segment_byte :: proc(seg: Segment, offset: u16) -> byte {
	return peripheral.peripheral_interface.read(get_physical_address(seg, offset))
}

read_segment_word :: proc(seg: Segment, offset: u16) -> u16 {
	return (u16(read_segment_byte(seg, offset + 1)) << 8) | u16(read_segment_byte(seg, offset))
}

write_segment_byte :: proc(seg: Segment, offset: u16, value: byte) {
	peripheral.peripheral_interface.write(get_physical_address(seg, offset), value)
}

write_segment_word :: proc(seg: Segment, offset: u16, value: u16) {
	write_segment_byte(seg, offset, byte(value & 0xFF))
	write_segment_byte(seg, offset + 1, byte(value >> 8))
}

@(private = "file")
stack_push_segment :: proc(seg: Segment) {
	stack_push_word(get_segment_register(seg)^)
}

@(private = "file")
stack_push_flags :: proc(flags: peripheral.Peripheral_CPU_Flags) {
	stack_push_word(transmute(u16)flags)
}

@(private = "file")
stack_push_word :: proc(data: u16) {
	using registers
	sp -= 2
	write_segment_word(.STACK, sp, data)
}

stack_push :: proc {
	stack_push_segment,
	stack_push_flags,
	stack_push_word,
}

stack_pop :: proc() -> u16 {
	using registers
	data := read_segment_word(.STACK, sp)
	sp += 2
	return data
}

@(private = "file")
branch_relative_byte :: proc(offset: i8) {
	branch_relative_word(i16(offset))
}

@(private = "file")
branch_relative_word :: proc(offset: i16) {
	branch_near(u16(i16(registers.ip) + offset))
}

@(private = "file")
branch_near :: proc(ip: u16) {
	registers.ip = ip
}

@(private = "file")
branch_far :: proc(seg, offset: u16) {
	using registers
	cs = seg
	ip = offset
}

branch :: proc {
	branch_relative_byte,
	branch_relative_word,
	branch_near,
	branch_far,
}

@(private = "file")
call_relative :: proc(offset: i16) {
	using registers
	stack_push(ip)
	branch(u16(i16(ip) + offset))
}

@(private = "file")
call_far :: proc(seg, offset: u16) {
	using registers
	stack_push(cs)
	stack_push(ip)
	branch(seg, offset)
}

call :: proc {
	call_relative,
	call_far,
}

return_near :: proc(offset: u16, pop: u16 = 0) {
	using registers
	ip = offset
	sp += pop
}

return_far :: proc(seg, offset: u16, pop: u16 = 0) {
	registers.cs = seg
	return_near(offset, pop)
}

update_si_di_direction :: proc(step: u16) {
	using registers

	if .DIRECTION in flags {
		si -= step
		di -= step
	} else {
		si += step
		di += step
	}
}

throw_exception :: proc(e: Exception) {
	using registers, state.instruction

	read_word :: proc(addr: u32) -> u16 {
		using peripheral.peripheral_interface
		return (u16(read(addr + 1)) << 8) | u16(read(addr))
	}

	stack_push(validate_flags(flags))
	stack_push(cs)

	if rep_prefix != 0 {
		stack_push(stream.ip)
		rep_prefix = 0
	} else {
		stack_push(ip)
	}
	
	if e == .DIV_ZERO_EXC {
		state.div_zero = true
	}

	n := u32(e)
	flags -= {.INTERRUPT, .TRAP}
	branch(read_word(n * 4 + 2), read_word(n * 4))
}
