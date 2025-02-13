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

package tests

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:testing"

import "vxt:machine"
import "vxt:machine/peripheral"

Flags :: peripheral.Peripheral_CPU_Flags

format_flags_message :: proc(builder: ^strings.Builder, a, b: Flags) -> string {
	write_flags :: proc(builder: ^strings.Builder, reg, exp: Flags) {
		flags := []string{"C", "-", "P", "-", "A", "-", "Z", "S", "T", "I", "D", "O"}
		for c, i in flags {
			mask := transmute(Flags)u16(1 << u16(i))
			mreg := mask & reg
			mexp := mask & exp

			if mreg != mexp {
				fmt.sbprint(builder, "*")
			}

			if mreg != nil {
				fmt.sbprint(builder, c)
			} else if mreg == mexp {
				fmt.sbprint(builder, "-")
			}
		}
	}

	fmt.sbprintf(builder, "expected flags to be 0x%X [", transmute(u16)b)
	write_flags(builder, b, b) // Don't mark errors.
	fmt.sbprintf(builder, "] but it was 0x%X [", transmute(u16)a)
	write_flags(builder, a, b)
	fmt.sbprint(builder, "]")

	return strings.to_string(builder^)
}

check_memory :: proc(addr: u32, res, value: byte, divz: bool) -> bool {
	if divz {
		// TODO: Better check here!
		log.debug("Div zero interrupt detected! Skipping memory validation.")
		return true
	}
	return res == value
}

execute_test :: proc(t: ^testing.T, test: json.Object, idx: int, flag_mask: Flags) {
	machine.create()
	defer machine.destroy()
	machine.initialize()

	using peripheral.peripheral_interface
	using regs := registers()

	// INT 0
	write(0, 0)
	write(1, 0x40)
	write(2, 0)
	write(3, 0)

	log.infof("Test %d \"%s\"", idx, test["name"])

	initial := test["initial"].(json.Object)
	ireg := initial["regs"].(json.Object)

	ax = u16(ireg["ax"].(f64))
	bx = u16(ireg["bx"].(f64))
	dx = u16(ireg["dx"].(f64))
	cx = u16(ireg["cx"].(f64))

	cs = u16(ireg["cs"].(f64))
	ss = u16(ireg["ss"].(f64))
	ds = u16(ireg["ds"].(f64))
	es = u16(ireg["es"].(f64))

	sp = u16(ireg["sp"].(f64))
	bp = u16(ireg["bp"].(f64))
	si = u16(ireg["si"].(f64))
	di = u16(ireg["di"].(f64))

	flags = transmute(Flags)u16(ireg["flags"].(f64))
	ip = u16(ireg["ip"].(f64))

	data := initial["ram"].(json.Array)
	for mop in data {
		pair := mop.(json.Array)
		write(u32(pair[0].(f64)), byte(pair[1].(f64)))
	}

	div_zero: bool
	for {
		step, ok := machine.step(1)
		div_zero = step.div_zero

		if !ok {
			log.error("invalid instruction")
			testing.fail(t)
			return
		}

		if !step.repeat {
			break
		}
	}

	final := test["final"].(json.Object)
	freg := final["regs"].(json.Object)

	get_reg :: proc(reg: string, ireg, freg: json.Object) -> u16 {
		v := freg[reg]
		return u16((v != nil) ? v.(f64) : ireg[reg].(f64))
	}

	testing.expect_value(t, ax, get_reg("ax", ireg, freg))
	testing.expect_value(t, bx, get_reg("bx", ireg, freg))
	testing.expect_value(t, cx, get_reg("cx", ireg, freg))
	testing.expect_value(t, dx, get_reg("dx", ireg, freg))

	testing.expect_value(t, cs, get_reg("cs", ireg, freg))
	testing.expect_value(t, ss, get_reg("ss", ireg, freg))
	testing.expect_value(t, ds, get_reg("ds", ireg, freg))
	testing.expect_value(t, es, get_reg("es", ireg, freg))

	testing.expect_value(t, sp, get_reg("sp", ireg, freg))
	testing.expect_value(t, bp, get_reg("bp", ireg, freg))
	testing.expect_value(t, si, get_reg("si", ireg, freg))
	testing.expect_value(t, di, get_reg("di", ireg, freg))

	testing.expect_value(t, ip, get_reg("ip", ireg, freg))

	{
		builder: strings.Builder
		defer strings.builder_destroy(&builder)

		a := flags & flag_mask
		b := transmute(Flags)get_reg("flags", ireg, freg) & flag_mask

		testing.expect(t, a == b, format_flags_message(&builder, a, b))
	}

	data = final["ram"].(json.Array)
	for mop in data {
		pair := mop.(json.Array)
		value := byte(pair[1].(f64))
		addr := u32(pair[0].(f64))
		res := read(addr)

		if !check_memory(addr, res, value, div_zero) {
			log.errorf("expected memory at 0x%X to be 0x%X (%d) but it was 0x%X (%d)", addr, value, value, res, res)
			testing.fail_now(t) // Lets not spam the console. One error is enough.
		}
	}
}

run_opcode_tests :: proc(t: ^testing.T, file_path: string, flag_mask: Flags) {
	data, ok := os.read_entire_file_from_filename(file_path)
	testing.expect(t, ok, "failed to load test file")
	defer delete(data)

	json_data, err := json.parse(data)
	testing.expect(t, err == .None, "failed to parse json data")
	defer json.destroy_value(json_data)

	for op, idx in json_data.(json.Array) {
		execute_test(t, op.(json.Object), idx, flag_mask)
	}
}
