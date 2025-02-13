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

@(private = "file")
ADD_b :: proc(a, b: byte) -> byte {
	res := a + b
	set_psz_flags(res)
	set_flags({.OVERFLOW}, (a ~ b ~ 0x80) & (res ~ a) & 0x80)
	set_flags({.AUXILIARY}, ((a ~ b) ~ res) & 0x10)
	set_flags({.CARRY}, res < a)
	return res
}

@(private = "file")
ADD_w :: proc(a, b: u16) -> u16 {
	res := a + b
	set_psz_flags(res)
	set_flags({.OVERFLOW}, (a ~ b ~ 0x8000) & (res ~ a) & 0x8000)
	set_flags({.AUXILIARY}, ((a ~ b) ~ res) & 0x10)
	set_flags({.CARRY}, res < a)
	return res
}

ADD :: proc {
	ADD_b,
	ADD_w,
}

PUSH_SR :: proc() {
	stack_push(state.instruction.reg_seg)
}

POP_SR :: proc() {
	get_segment_register(state.instruction.reg_seg)^ = stack_pop()
}

@(private = "file")
OR_b :: proc(a, b: byte) -> byte {
	res := a | b
	set_psz_flags(res)
	set_flags({.OVERFLOW, .CARRY}, false)
	return res
}

@(private = "file")
OR_w :: proc(a, b: u16) -> u16 {
	res := a | b
	set_psz_flags(res)
	set_flags({.OVERFLOW, .CARRY}, false)
	return res
}

OR :: proc {
	OR_b,
	OR_w,
}

@(private = "file")
ADC_b :: proc(a, b: byte) -> byte {
	c: byte = (.CARRY in registers.flags) ? 1 : 0
	res := a + b + c

	set_psz_flags(res)
	set_flags({.OVERFLOW}, (a ~ b ~ 0x80) & (res ~ a) & 0x80)
	set_flags({.AUXILIARY}, ((a ~ b) ~ res) & 0x10)
	set_flags({.CARRY}, (res < a) || ((.CARRY in registers.flags) && res == a))
	return res
}

@(private = "file")
ADC_w :: proc(a, b: u16) -> u16 {
	c: u16 = (.CARRY in registers.flags) ? 1 : 0
	res := a + b + c

	set_psz_flags(res)
	set_flags({.OVERFLOW}, (a ~ b ~ 0x8000) & (res ~ a) & 0x8000)
	set_flags({.AUXILIARY}, ((a ~ b) ~ res) & 0x10)
	set_flags({.CARRY}, (res < a) || ((.CARRY in registers.flags) && res == a))
	return res
}

ADC :: proc {
	ADC_b,
	ADC_w,
}

@(private = "file")
SBB_b :: proc(a, b: byte) -> byte {
	c: byte = (.CARRY in registers.flags) ? 1 : 0
	res := a - (b + c)

	set_psz_flags(res)
	set_flags({.OVERFLOW}, (a ~ b) & (res ~ a) & 0x80)
	set_flags({.AUXILIARY}, ((a ~ b) ~ res) & 0x10)
	set_flags({.CARRY}, (res > a) || ((.CARRY in registers.flags) && b == 0xFF))
	return res
}

@(private = "file")
SBB_w :: proc(a, b: u16) -> u16 {
	c: u16 = (.CARRY in registers.flags) ? 1 : 0
	res := a - (b + c)

	set_psz_flags(res)
	set_flags({.OVERFLOW}, (a ~ b) & (res ~ a) & 0x8000)
	set_flags({.AUXILIARY}, ((a ~ b) ~ res) & 0x10)
	set_flags({.CARRY}, (res > a) || ((.CARRY in registers.flags) && b == 0xFFFF))
	return res
}

SBB :: proc {
	SBB_b,
	SBB_w,
}

@(private = "file")
AND_b :: proc(a, b: byte) -> byte {
	res := a & b
	set_psz_flags(res)
	set_flags({.OVERFLOW, .CARRY}, false)
	return res
}

@(private = "file")
AND_w :: proc(a, b: u16) -> u16 {
	res := a & b
	set_psz_flags(res)
	set_flags({.OVERFLOW, .CARRY}, false)
	return res
}

AND :: proc {
	AND_b,
	AND_w,
}

DAA :: proc() {
	using registers

	reg := al
	af := .AUXILIARY in flags

	if ((reg & 0xF) > 9) || (.AUXILIARY in flags) {
		al += 6
		flags += {.AUXILIARY}
	} else {
		flags -= {.AUXILIARY}
	}

	if (reg > (af ? 0x9F : 0x99)) || (.CARRY in flags) {
		al += 0x60
		flags += {.CARRY}
	} else {
		flags -= {.CARRY}
	}
	set_psz_flags(al)
}

@(private = "file")
SUB_b :: proc(a, b: byte) -> byte {
	res := a - b
	set_psz_flags(res)
	set_flags({.OVERFLOW}, (a ~ b) & (res ~ a) & 0x80)
	set_flags({.AUXILIARY}, ((a ~ b) ~ res) & 0x10)
	set_flags({.CARRY}, a < b)
	return res
}

@(private = "file")
SUB_w :: proc(a, b: u16) -> u16 {
	res := a - b
	set_psz_flags(res)
	set_flags({.OVERFLOW}, (a ~ b) & (res ~ a) & 0x8000)
	set_flags({.AUXILIARY}, ((a ~ b) ~ res) & 0x10)
	set_flags({.CARRY}, a < b)
	return res
}

SUB :: proc {
	SUB_b,
	SUB_w,
}

DAS :: proc() {
	using registers

	reg := al
	af := .AUXILIARY in flags

	if ((al & 0xF) > 9) || (.AUXILIARY in flags) {
		al -= 6
		flags += {.AUXILIARY}
	} else {
		flags -= {.AUXILIARY}
	}

	if (reg > (af ? 0x9F : 0x99)) || (.CARRY in flags) {
		al -= 0x60
		flags += {.CARRY}
	} else {
		flags -= {.CARRY}
	}
	set_psz_flags(al)
}

@(private = "file")
XOR_b :: proc(a, b: byte) -> byte {
	res := a ~ b
	set_psz_flags(res)
	set_flags({.OVERFLOW, .CARRY}, false)
	return res
}

@(private = "file")
XOR_w :: proc(a, b: u16) -> u16 {
	res := a ~ b
	set_psz_flags(res)
	set_flags({.OVERFLOW, .CARRY}, false)
	return res
}

XOR :: proc {
	XOR_b,
	XOR_w,
}

ASCII :: proc(dir: i8) {
	using registers

	if ((al & 0xF) > 9) || (.AUXILIARY in flags) {
		al += byte(6 * dir)
		ah += byte(dir)
		flags += {.AUXILIARY, .CARRY}
	} else {
		flags -= {.AUXILIARY, .CARRY}
	}
	al &= 0xF
}

INC_w :: proc(a: u16) -> u16 {
	res := a + 1
	set_psz_flags(res)
	set_flags({.AUXILIARY}, (res & 0xF) == 0)
	set_flags({.OVERFLOW}, res == 0x8000)
	return res
}

INC_eb :: proc() {
	res := load_eb() + 1
	store_eb(res)

	set_psz_flags(res)
	set_flags({.AUXILIARY}, (res & 0xF) == 0)
	set_flags({.OVERFLOW}, res == 0x80)
}

DEC_w :: proc(a: u16) -> u16 {
	res := a - 1
	set_psz_flags(res)
	set_flags({.AUXILIARY}, (res & 0xF) == 0xF)
	set_flags({.OVERFLOW}, res == 0x7FFF)
	return res
}

DEC_eb :: proc() {
	res := load_eb() - 1
	store_eb(res)

	set_psz_flags(res)
	set_flags({.AUXILIARY}, (res & 0xF) == 0xF)
	set_flags({.OVERFLOW}, res == 0x7F)
}

AAM :: proc() {
	using registers, state.instruction

	if ib == 0 {
		// The juggling with the flags here is just to make the tests happy.
		flags &= { .RESERVED_0, .RESERVED_1, .RESERVED_2, .TRAP, .INTERRUPT, .DIRECTION, .RESERVED_3, .RESERVED_4, .RESERVED_5, .RESERVED_6 }
		flags += { .PARITY, .ZERO }

		throw_exception(.DIV_ZERO_EXC)
		return
	}

	ah = al / ib
	al = al % ib
	set_psz_flags(al)
}

MUL_eb :: proc() {
	using registers
	ax = u16(load_eb()) * u16(al)

	set_psz_flags(al)
	set_flags({.CARRY, .OVERFLOW}, ah)
	set_flags({.ZERO}, false)
}

MUL_ew :: proc() {
	using registers
	res := u32(load_ew()) * u32(ax)
	dx = u16(res >> 16)
	ax = u16(res & 0xFFFF)

	set_psz_flags(ax)
	set_flags({.CARRY, .OVERFLOW}, dx)
	set_flags({.ZERO}, false)
}

IMUL_eb :: proc() {
	using registers

	res := i16(i8(al)) * i16(i8(load_eb()))
	ax = u16(res)

	set_psz_flags(byte(res & 0xFF))
	set_flags({.CARRY, .OVERFLOW}, res != i16(i8(res)))
	set_flags({.ZERO}, false)
}

IMUL_ew :: proc() {
	using registers

	res := i32(i16(ax)) * i32(i16(load_ew()))
	ax = u16(res & 0xFFFF)
	dx = u16(res >> 16)

	set_psz_flags(ax)
	set_flags({.CARRY, .OVERFLOW}, res != i32(i16(res)))
	set_flags({.ZERO}, false)
}

DIV_eb :: proc() {
	v := u16(load_eb())
	if v == 0 {
		throw_exception(.DIV_ZERO_EXC)
		return
	}

	a := registers.ax
	q := a / v
	r := a % v
	q8 := q & 0xFF

	if q != q8 {
		throw_exception(.DIV_ZERO_EXC)
		return
	}

	registers.ah = byte(r)
	registers.al = byte(q8)
}

DIV_ew :: proc() {
	v := u32(load_ew())
	if v == 0 {
		throw_exception(.DIV_ZERO_EXC)
		return
	}

	a := (u32(registers.dx) << 16) | u32(registers.ax)
	q := a / u32(v)
	r := a % v
	q16 := q & 0xFFFF

	if q != q16 {
		throw_exception(.DIV_ZERO_EXC)
		return
	}

	registers.dx = u16(r)
	registers.ax = u16(q16)
}

IDIV_eb :: proc() {
	using registers

	a := i16(ax)
	if a == transmute(i16)u16(0x8000) {
		throw_exception(.DIV_ZERO_EXC)
		return
	}

	v := i16(load_eb())
	if v == 0 {
		throw_exception(.DIV_ZERO_EXC)
		return
	}

	q16 := a / v
	q16 *= state.invert_quotient ? -1 : 1 // This is 8088 specific.
	
	r8 := i8(a % v)
	q8 := i8(q16 & 0xFF)

	if q16 != i16(q8) {
		throw_exception(.DIV_ZERO_EXC)
		return
	}

	al = byte(q8)
	ah = byte(r8)
}

IDIV_ew :: proc() {
	using registers

	a := i32((u32(dx) << 16) | u32(ax))
	if a == transmute(i32)u32(0x80000000) {
		throw_exception(.DIV_ZERO_EXC)
		return
	}

	v := i32(load_ew())
	if v == 0 {
		throw_exception(.DIV_ZERO_EXC)
		return
	}

	q32 := a / v
	q32 *= state.invert_quotient ? -1 : 1 // This is 8088 specific.
	
	r16 := i16(a % v)
	q16 := i16(q32 & 0xFFFF)

	if q32 != i32(q16) {
		throw_exception(.DIV_ZERO_EXC)
		return
	}

	ax = u16(q16)
	dx = u16(r16)
}

@(private = "file")
flags_overflow_left :: proc(s: u16) {
	set_flags({.OVERFLOW}, (transmute(u16)registers.flags & 1) ~ s)
}

@(private = "file")
flags_overflow_right :: proc(s: u16) {
	set_flags({.OVERFLOW}, (s >> 1) ~ (s & 1))
}

@(private = "file")
ROL_b :: proc(v, c: byte) -> byte {
	if c == 0 {
		return v
	}

	r := v
	for i: byte = 0; i < c; i += 1 {
		s := r & 0x80
		set_flags({.CARRY}, s)
		r = (r << 1) | (s >> 7)
	}

	flags_overflow_left(u16(r >> 7))
	return r
}

@(private = "file")
ROL_w :: proc(v: u16, c: byte) -> u16 {
	if c == 0 {
		return v
	}

	r := v
	for i: byte = 0; i < c; i += 1 {
		s := r & 0x8000
		set_flags({.CARRY}, s)
		r = (r << 1) | (s >> 0xF)
	}

	flags_overflow_left(r >> 0xF)
	return r
}

ROL :: proc {
	ROL_b,
	ROL_w,
}

@(private = "file")
ROR_b :: proc(v, c: byte) -> byte {
	if c == 0 {
		return v
	}

	r := v
	for i: byte = 0; i < c; i += 1 {
		s := r & 1
		set_flags({.CARRY}, s)
		r = (r >> 1) | (s << 7)
	}

	flags_overflow_right(u16(r >> 6))
	return r
}

@(private = "file")
ROR_w :: proc(v: u16, c: byte) -> u16 {
	if c == 0 {
		return v
	}

	r := v
	for i: byte = 0; i < c; i += 1 {
		s := r & 1
		set_flags({.CARRY}, s)
		r = (r >> 1) | (s << 0xF)
	}

	flags_overflow_right(r >> 0xE)
	return r
}

ROR :: proc {
	ROR_b,
	ROR_w,
}

@(private = "file")
RCL_b :: proc(v, c: byte) -> byte {
	if c == 0 {
		return v
	}

	r := v
	for i: byte = 0; i < c; i += 1 {
		s := r & 0x80
		r <<= 1
		if .CARRY in registers.flags {
			r |= 1
		}
		set_flags({.CARRY}, s)
	}

	flags_overflow_left(u16(r >> 7))
	return r
}

@(private = "file")
RCL_w :: proc(v: u16, c: byte) -> u16 {
	if c == 0 {
		return v
	}

	r := v
	for i: byte = 0; i < c; i += 1 {
		s := r & 0x8000
		r <<= 1
		if .CARRY in registers.flags {
			r |= 1
		}
		set_flags({.CARRY}, s)
	}

	flags_overflow_left(r >> 0xF)
	return r
}

RCL :: proc {
	RCL_b,
	RCL_w,
}

@(private = "file")
RCR_b :: proc(v, c: byte) -> byte {
	if c == 0 {
		return v
	}

	r := v
	for i: byte = 0; i < c; i += 1 {
		s := r & 1
		r >>= 1
		if .CARRY in registers.flags {
			r |= 0x80
		}
		set_flags({.CARRY}, s)
	}

	flags_overflow_right(u16(r >> 6))
	return r
}

@(private = "file")
RCR_w :: proc(v: u16, c: byte) -> u16 {
	if c == 0 {
		return v
	}

	r := v
	for i: byte = 0; i < c; i += 1 {
		s := r & 1
		r >>= 1
		if .CARRY in registers.flags {
			r |= 0x8000
		}
		set_flags({.CARRY}, s)
	}

	flags_overflow_right(r >> 0xE)
	return r
}

RCR :: proc {
	RCR_b,
	RCR_w,
}

@(private = "file")
SHL_b :: proc(v, c: byte) -> byte {
	if c == 0 {
		return v
	}

	r := v
	for i: byte = 0; i < c; i += 1 {
		set_flags({.CARRY}, r & 0x80)
		r <<= 1
	}

	set_flags({.OVERFLOW}, (r >> 7) != byte(transmute(u16)registers.flags & 1))
	set_psz_flags(r)
	return r
}

@(private = "file")
SHL_w :: proc(v: u16, c: byte) -> u16 {
	if c == 0 {
		return v
	}

	r := v
	for i: byte = 0; i < c; i += 1 {
		set_flags({.CARRY}, r & 0x8000)
		r <<= 1
	}

	set_flags({.OVERFLOW}, (r >> 0xF) != transmute(u16)registers.flags & 1)
	set_psz_flags(r)
	return r
}

SHL :: proc {
	SHL_b,
	SHL_w,
}

@(private = "file")
SHR_b :: proc(v, c: byte) -> byte {
	if c == 0 {
		return v
	}

	r := v
	for i: byte = 0; i < c; i += 1 {
		set_flags({.CARRY}, r & 1)
		r >>= 1
	}

	set_flags({.OVERFLOW}, (c == 1) && ((v & 0x80) != 0))
	set_psz_flags(r)
	return r
}

@(private = "file")
SHR_w :: proc(v: u16, c: byte) -> u16 {
	if c == 0 {
		return v
	}

	r := v
	for i: byte = 0; i < c; i += 1 {
		set_flags({.CARRY}, r & 1)
		r >>= 1
	}

	set_flags({.OVERFLOW}, (c == 1) && ((v & 0x8000) != 0))
	set_psz_flags(r)
	return r
}

SHR :: proc {
	SHR_b,
	SHR_w,
}

@(private = "file")
SAR_b :: proc(v, c: byte) -> byte {
	if c == 0 {
		return v
	}

	r := v
	for i: byte = 0; i < c; i += 1 {
		s := r & 0x80
		set_flags({.CARRY}, r & 1)
		r = (r >> 1) | s
	}

	registers.flags -= {.OVERFLOW}
	set_psz_flags(r)
	return r
}

@(private = "file")
SAR_w :: proc(v: u16, c: byte) -> u16 {
	if c == 0 {
		return v
	}

	r := v
	for i: byte = 0; i < c; i += 1 {
		s := r & 0x8000
		set_flags({.CARRY}, r & 1)
		r = (r >> 1) | s
	}

	registers.flags -= {.OVERFLOW}
	set_psz_flags(r)
	return r
}

SAR :: proc {
	SAR_b,
	SAR_w,
}
