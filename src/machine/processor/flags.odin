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

VALID_LOW_FLAGS :: peripheral.VALID_LOW_FLAGS
VALID_HIGH_FLAGS :: peripheral.VALID_HIGH_FLAGS
VALID_FLAGS :: peripheral.VALID_FLAGS

PARITY_TABLE := [0x100]bool{
	true, false, false, true, false, true, true, false,
	false, true, true, false, true, false, false, true,
	false, true, true, false, true, false, false, true,
	true, false, false, true, false, true, true, false,
	false, true, true, false, true, false, false, true,
	true, false, false, true, false, true, true, false,
	true, false, false, true, false, true, true, false,
	false, true, true, false, true, false, false, true,
	false, true, true, false, true, false, false, true,
	true, false, false, true, false, true, true, false,
	true, false, false, true, false, true, true, false,
	false, true, true, false, true, false, false, true,
	true, false, false, true, false, true, true, false,
	false, true, true, false, true, false, false, true,
	false, true, true, false, true, false, false, true,
	true, false, false, true, false, true, true, false,
	false, true, true, false, true, false, false, true,
	true, false, false, true, false, true, true, false,
	true, false, false, true, false, true, true, false,
	false, true, true, false, true, false, false, true,
	true, false, false, true, false, true, true, false,
	false, true, true, false, true, false, false, true,
	false, true, true, false, true, false, false, true,
	true, false, false, true, false, true, true, false,
	true, false, false, true, false, true, true, false,
	false, true, true, false, true, false, false, true,
	false, true, true, false, true, false, false, true,
	true, false, false, true, false, true, true, false,
	false, true, true, false, true, false, false, true,
	true, false, false, true, false, true, true, false,
	true, false, false, true, false, true, true, false,
	false, true, true, false, true, false, false, true,
}

@(private="file")
set_flags_bool :: proc(flags: peripheral.Peripheral_CPU_Flags, v: bool) {
	registers.flags = v ? (registers.flags + flags) : (registers.flags - flags)
}

@(private="file")
set_flags_byte :: proc(flags: peripheral.Peripheral_CPU_Flags, v: byte) {
	set_flags_bool(flags, v != 0)
}

@(private="file")
set_flags_word :: proc(flags: peripheral.Peripheral_CPU_Flags, v: u16) {
	set_flags_bool(flags, v != 0)
}

set_flags :: proc {
	set_flags_bool,
	set_flags_byte,
	set_flags_word,
}

@(private="file")
set_psz_flags_byte :: proc(v: byte) {	
	set_flags({.PARITY}, PARITY_TABLE[v])
	set_flags({.SIGN}, v & 0x80)
	set_flags({.ZERO}, v == 0)
}

@(private="file")
set_psz_flags_word :: proc(v: u16) {
	set_flags({.PARITY}, PARITY_TABLE[v & 0xFF])
	set_flags({.SIGN}, v & 0x8000)
	set_flags({.ZERO}, v == 0)
}

set_psz_flags :: proc {
	set_psz_flags_byte,
	set_psz_flags_word,
}

flags_to_set :: proc(flags: u16) -> peripheral.Peripheral_CPU_Flags {
	return transmute(peripheral.Peripheral_CPU_Flags)flags
}

@(private="file")
validate_flags_byte :: proc(flags: u8) -> u16 {
	return validate_flags_word(u16(flags))
}

@(private="file")
validate_flags_word :: proc(flags: u16) -> u16 {
	return validate_flags_set(transmute(peripheral.Peripheral_CPU_Flags)flags)
}

@(private="file")
validate_flags_set :: proc(flags: peripheral.Peripheral_CPU_Flags) -> u16 {
	return transmute(u16)((flags & VALID_FLAGS) + { .RESERVED_0, .RESERVED_3, .RESERVED_4, .RESERVED_5, .RESERVED_6 })
}

validate_flags :: proc {
	validate_flags_byte,
	validate_flags_word,
	validate_flags_set,
}
