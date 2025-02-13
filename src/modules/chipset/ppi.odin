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

package chipset

import "core:log"

import "vxt:machine/peripheral"

PPI :: struct {
	data_port, port_61, xt_switches:      byte,
	kb_reset, spk_enabled: 				  bool,
	spk_sample_index:                     i64,
	pit:                                  ^peripheral.Peripheral,
}

ppi_install :: proc(ppi: ^PPI) -> bool {
	using peripheral
	register_io_address_range(ppi, 0x60, 0x63)

	for p in peripheral_manager.peripherals {
		if p.class == .PIT {
			ppi.pit = get_peripheral(p)
			break
		}
	}

	assert(ppi.pit != nil)
	return true
}

ppi_config :: proc(ppi: ^PPI, name, key: string, value: any) -> (ok := true) {
	if name != "chipset" {
		return
	}

	switch key {
	case "set_switches":
		ppi.xt_switches = value.(byte)
	case "get_switches":
		value.(^byte)^ = ppi.xt_switches
	case:
		ok = false
	}
	return
}

ppi_io_in :: proc(using ppi: ^PPI, port: u16) -> byte {
	switch port {
	case 0x60:
		data := data_port
		if kb_reset {
			kb_reset = false
			data_port = 0
		}
		return data
	case 0x61:
		port_61 ~= 0x10 // Toggle refresh bit.
		return port_61
	case 0x62:
		return bool(port_61 & 8) ? (xt_switches >> 4) : (xt_switches & 0xF)
	case:
		return 0
	}
}

ppi_io_out :: proc(using ppi: ^PPI, port: u16, data_out: byte) {
	if port == 0x61 {
		if enable := (data_out & 3) == 3; enable != spk_enabled {
			spk_enabled = enable
			spk_sample_index = 0
		}

		do_reset := !bool(port_61 & 0xC0) && bool(data_out & 0xC0)
		kb_reset ||= do_reset

		if kb_reset && (data_port != 0xAA) {
			data_port = 0xAA
			peripheral.peripheral_interface.interrupt(1)
			log.info("Keyboard reset!")
		}

		port_61 = data_out
	}
}
