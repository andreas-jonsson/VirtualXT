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

import "vxt:machine/peripheral"

PIC :: struct {
	mask_reg, request_reg, service_reg, icw_step, read_mode: byte,
	icw:                                                     [5]byte,
}

pic_install :: proc(pic: ^PIC) -> bool {
	peripheral.register_io_address_range(pic, 0x20, 0x21)
	return true
}

pic_io_in :: proc(using pic: ^PIC, port: u16) -> byte {
	switch port {
	case 0x20:
		return (read_mode != 0) ? service_reg : request_reg
	case 0x21:
		return mask_reg
	}
	return 0
}

pic_io_out :: proc(using pic: ^PIC, port: u16, data: byte) {
	switch port {
	case 0x20:
		if bool(data & 0x10) {
			icw_step = 1
			mask_reg = 0
			icw[icw_step] = data
			icw_step += 1
			return
		}

		if ((data & 0x98) == 8) && bool(data & 2) {
			read_mode = data & 2
		}

		if bool(data & 0x20) {
			for i: byte; i < 8; i += 1 {
				if bool((service_reg >> i) & 1) {
					service_reg ~= 1 << i
					return
				}
			}
		}
	case 0x21:
		if (icw_step == 3) && bool(icw[1] & 2) {
			icw_step = 4
		}

		if icw_step < 5 {
			icw[icw_step] = data
			icw_step += 1
			return
		}
		mask_reg = data
	}
}

pic_next :: proc(using pic: ^PIC) -> int {
	has := request_reg & (~mask_reg)

	for i: byte; i < 8; i += 1 {
		mask: byte = 1 << i
		if !bool(has & mask) {
			continue
		}

		if bool(request_reg & mask) && !bool(service_reg & mask) {
			request_reg ~= mask
			service_reg |= mask

			if !bool(icw[4] & 2) { 	// Not auto EOI?
				service_reg |= mask
			}
			return int(icw[2] + i)
		}
	}
	return -1
}

pic_irq :: proc(pic: ^PIC, n: uint) {
	pic.request_reg |= byte(1 << n)
}
