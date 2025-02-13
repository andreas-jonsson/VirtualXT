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

import "core:log"
import "vxt:machine/peripheral"

get_registers :: proc() -> ^peripheral.Peripheral_CPU_Registers {
	return &registers
}

reset :: proc() {
	state.instruction.rep_prefix = 0

	registers = peripheral.Peripheral_CPU_Registers {
		debug = registers.debug, // Preserve flag for external debugger.
		flags = flags_to_set(validate_flags(byte(0))),
		ip    = 0,
		cs    = 0xFFFF,
	}

	ok: bool
	if _, interrupt_controler, ok = peripheral.get_peripheral_from_class(.PIC); !ok {
		log.warn("Interrupt controller is not connected!")
	}
}

step :: proc() -> (cycles: uint = 1, repeat, div_zero: bool, ok := true) {
	using state.instruction

	if rep_prefix == 0 {
		decode_prepare()
		decode_prefix()
		decode_opcode()

		write_cpu_trace()
		registers.ip += u16(stream.size)
	}

	// TODO: Remove!
	@(static) opcode0_count: uint
	if opcode.raw == 0 {
		opcode0_count += 1
		if opcode0_count > 3 {
			//valid = false
			opcode0_count = 0
			//log.error("Opcode zero repeat!")
		}
	} else {
		opcode0_count = 0
	}

	if valid {
		if (rep_prefix != 0) && (registers.cx == 0) {
			rep_prefix = 0
		} else {
			exec()
			div_zero = state.div_zero
		}
	} else {
		registers.debug = true
		rep_prefix = 0 // Break repeat here!
		ok = false
	}

	// This all happes after opcode is executed.
	if rep_prefix != 0 {
		using registers
		cx -= 1

		switch opcode.raw {
		case 0xA6, 0xA7, 0xAE, 0xAF:
			// Has flag conditions.
			if rep_prefix == 0xF2 {
				// REPNE/REPNZ
				rep_prefix &= (.ZERO in flags) ? 0 : 0xFF
			} else if rep_prefix == 0xF3 {
				// REP/REPE
				rep_prefix &= (.ZERO not_in flags) ? 0 : 0xFF
			}
		}
	}

	check_interrupts()
	
	cycles += 12 // TODO: Fix this!
	repeat = rep_prefix != 0
	return
}

destroy :: proc() {
	close_cpu_trace()
}
