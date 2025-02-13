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

package machine

import "core:log"
import "core:math/rand"

import "vxt:machine/peripheral"

MAIN_MEMORY_SIZE :: 0x100000 // 1MB

cpu_frequency: uint = DEFAULT_CPU_FREQUENCY
interrupt_controler: ^peripheral.Peripheral_Callbacks(peripheral.Peripheral)

setup_default_peripheral :: proc() {
	Default_Peripheral :: struct {
		memory: [MAIN_MEMORY_SIZE]byte,
	}

	_, cb := peripheral.allocate(Default_Peripheral)
	using cb

	install = proc(default: ^Default_Peripheral) -> bool {
		peripheral.register_memory_address_range(default, 0, 0xFFFFF)
		peripheral.register_io_address_range(default, 0, 0xFFFF)
		_ = rand.read(default.memory[:])
		return true
	}

	name = proc(_: ^Default_Peripheral) -> string {
		return "Main Memory"
	}

	read = proc(default: ^Default_Peripheral, addr: u32) -> byte {
		return (int(addr) < len(default.memory)) ? default.memory[addr] : 0xFF
	}

	write = proc(default: ^Default_Peripheral, addr: u32, data: byte) {
		if int(addr) < len(default.memory) {
			default.memory[addr] = data
		}
	}

	io_in = proc(_: ^Default_Peripheral, port: u16) -> byte {
		log.debug("Reading from unmapped IO port: %4.X", port)
		return 0xFF
	}

	io_out = proc(_: ^Default_Peripheral, port: u16, _: byte) {
		log.debug("Writing to unmapped IO port: %4.X", port)
	}
}

update_timers :: proc(cycles: uint) {
	using peripheral.peripheral_manager

	for &timer, id in timers {
		using timer

		ticks += cycles
		if ticks >= uint(interval * f64(peripheral.peripheral_interface.frequency())) {
			p := peripherals[pidx]
			p.timer(peripheral.get_peripheral(p), peripheral.Peripheral_Timer_ID(id), ticks)
			ticks = 0
		}
	}
}

interrupt :: proc(num: uint) {
	p := peripheral.get_peripheral(interrupt_controler)
	interrupt_controler.pic.irq(p, num)
}

read_memory :: proc(addr: u32) -> byte {
	using peripheral.peripheral_manager
	a := addr & 0xFFFFF
	p := peripherals[memory_map[a >> 4]]
	return p.read(peripheral.get_peripheral(p), a)
}

write_memory :: proc(addr: u32, data: byte) {
	using peripheral.peripheral_manager
	a := addr & 0xFFFFF
	p := peripherals[memory_map[a >> 4]]
	p.write(peripheral.get_peripheral(p), a, data)
}

read_io_port :: proc(port: u16) -> byte {
	using peripheral.peripheral_manager
	p := peripherals[io_map[port]]
	return p.io_in(peripheral.get_peripheral(p), port)
}

write_io_port :: proc(port: u16, data: byte) {
	using peripheral.peripheral_manager
	p := peripherals[io_map[port]]
	p.io_out(peripheral.get_peripheral(p), port, data)
}
