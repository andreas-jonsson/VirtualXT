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

import "base:runtime"
import "core:log"

import "vxt:machine/peripheral"
import "vxt:machine/processor"

DEFAULT_CPU_FREQUENCY :: peripheral.MAIN_OSCILLATOR / 3

Step :: struct {
	cycles:           uint,
	repeat, div_zero: bool,
}

Peripheral :: peripheral.Peripheral
Peripheral_Class :: peripheral.Peripheral_Class

registers :: processor.get_registers

create :: proc() -> bool {
	using peripheral

	peripheral_interface.registers = processor.get_registers
	peripheral_interface.interrupt = interrupt
	peripheral_interface.frequency = frequency
	peripheral_interface.configure = configure
	peripheral_interface.read = read_memory
	peripheral_interface.write = write_memory
	peripheral_interface.read_port = read_io_port
	peripheral_interface.write_port = write_io_port

	runtime.mem_zero(&peripheral_manager.peripherals, size_of(peripheral_manager.peripherals))
	runtime.mem_zero(&peripheral_manager.timers, size_of(peripheral_manager.timers))

	setup_default_peripheral()
	return true
}

initialize :: proc() -> bool {
	for p in peripheral.peripheral_manager.peripherals {
		if p.install == nil {
			continue
		}

		usr := peripheral.get_peripheral(p)
		if !p.install(usr) {
			log.warnf("could not install: %s", p.name(usr))
			return false
		}

		if p.class == .PIC {
			interrupt_controler = p
		}
	}

	reset()
	return true
}

destroy :: proc() {
	using peripheral

	for p in peripheral_manager.peripherals {
		if p.destroy != nil {
			p.destroy(get_peripheral(p))
		}
		free(p)
	}

	processor.destroy()

	delete(peripheral_manager.peripherals)
	delete(peripheral_manager.timers)
}

reset :: proc() -> bool {
	for p in peripheral.peripheral_manager.peripherals {
		if p.reset != nil {
			p.reset(peripheral.get_peripheral(p)) or_return
		}
	}

	processor.reset()
	return true
}

configure :: proc(id, key: string, value: any) -> bool {
	if id == "machine" {
		if key == "cpu_frequency" {
			cpu_frequency = value.(uint)
		}
	}

	for p in peripheral.peripheral_manager.peripherals {
		if p.config != nil {
			p.config(peripheral.get_peripheral(p), id, key, value) or_return
		}
	}
	return true
}

print_status :: proc() {
	using peripheral

	log.info("----------------------------------------")

	log.infof("CPU: 8088 @ %.2fMHz", f64(frequency()) / 1000000)
	log.info("Peripherals:")

	for p, idx in peripheral_manager.peripherals {
		if idx > 0 {
			log.infof("  %s", p.name(get_peripheral(p)))
		}
	}

	log.info("IO map:")

	prev_idx: byte
	start_addr: u16

	for idx, port in peripheral_manager.io_map {
		if prev_idx > 0 && idx != prev_idx {
			p := peripheral_manager.peripherals[prev_idx]
			log.infof("  %4.X..%4.X\t%s", start_addr, port - 1, p.name(get_peripheral(p)))
			start_addr = u16(port)
		} else if idx == 0 {
			start_addr = u16(port + 1)
		}
		prev_idx = idx
	}

	log.info("Memory map:")

	prev_idx = 0
	start_addr = 0
	pname: string

	for idx, addr in peripheral_manager.memory_map {
		end := addr == 0xFFFF
		if idx != prev_idx || end {
			p := peripheral_manager.peripherals[prev_idx]
			pname = p.name(get_peripheral(p))

			log.infof("  %5.X..%5.X\t%s", u32(start_addr) << 4, (addr << 4) + ((end ? 0x10 : 0) - 1), pname)
			start_addr = u16(addr)
		}
		prev_idx = idx
	}

	log.info("----------------------------------------")
}

step :: proc(cycles: uint) -> (res: Step, ok := true) {
	using peripheral.peripheral_manager

	for res.cycles < cycles {
		n, r, z, s := processor.step()
		assert(n > 0)
		if !s {
			ok = s
		}
		res.cycles += n
		res.repeat = r
		res.div_zero = z

		update_timers(n)
	}
	return
}

peripheral_from_class :: proc(class: Peripheral_Class) -> (p: ^Peripheral, ok: bool) {
	p, _, ok = peripheral.get_peripheral_from_class(class)
	return
}

frequency :: proc() -> uint {
	return cpu_frequency
}
