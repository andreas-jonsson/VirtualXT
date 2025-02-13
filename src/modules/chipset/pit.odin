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

PIT_FREQUENCY :: peripheral.MAIN_OSCILLATOR / 12

Channel_Mode :: enum byte {
	MODE_LATCH_COUNT,
	MODE_LOW_BYTE,
	MODE_HIGH_BYTE,
	MODE_TOGGLE,
}

Channel :: struct {
	enabled, toggle:        bool,
	counter, latch, chdata: u16,
	mode:                   Channel_Mode,
}

PIT :: struct {
	channels: [3]Channel,
	ticker:   f64,
}

pit_install :: proc(pit: ^PIT) -> bool {
	using peripheral
	register_io_address_range(pit, 0x40, 0x43)
	register_timer(pit)
	return true
}

pit_io_in :: proc(pit: ^PIT, port: u16) -> byte {
	if port == 0x43 {
		return 0
	}

	using ch := &pit.channels[port & 3]
	flip := (mode == .MODE_LATCH_COUNT) || (mode == .MODE_TOGGLE)

	if mode != .MODE_LATCH_COUNT {
		latch = counter
	}

	ret: byte
	if (mode == .MODE_LOW_BYTE) || (flip && !toggle) {
		ret = byte(latch & 0xFF)
	} else if (mode == .MODE_HIGH_BYTE) || (flip && toggle) {
		ret = byte(latch >> 8)
	}

	if flip {
		toggle = !toggle
	}
	return ret
}

pit_io_out :: proc(pit: ^PIT, port: u16, data: byte) {
	// Mode/Command register.
	if port == 0x43 {
		using ch := &pit.channels[(data >> 6) & 3]

		toggle = false
		mode = Channel_Mode((data >> 4) & 3)
		if (mode == .MODE_LATCH_COUNT) {
			latch = counter
		}
		return
	}

	using ch := &pit.channels[port & 3]
	flip := (mode == .MODE_LATCH_COUNT) || (mode == .MODE_TOGGLE)

	if (mode == .MODE_LOW_BYTE) || (flip && !toggle) {
		chdata = (chdata & 0xFF00) | u16(data)
		enabled = false
	} else if (mode == .MODE_HIGH_BYTE) || (flip && toggle) {
		chdata = (chdata & 0x00FF) | (u16(data) << 8)
		enabled = true
		if (chdata == 0) {
			chdata = 0xFFFF
		}
	}

	if flip {
		toggle = !toggle
	}
}

pit_timer :: proc(pit: ^PIT, id: peripheral.Peripheral_Timer_ID, cycles: uint) {
	using peripheral.peripheral_interface
	INTERVAL :: 1 / (PIT_FREQUENCY / 1000000)

	// Elapsed time in microseconds.
	pit.ticker += f64(cycles) * (1000000 / f64(frequency()))

	for pit.ticker >= INTERVAL {
		for i := 0; i < 3; i += 1 {
			using ch := &pit.channels[i]
			if !enabled {
				continue
			}

			if counter == 0 {
				counter = chdata
				if i == 0 {
					interrupt(0)
				}
			} else {
				counter -= 1
			}
		}
		pit.ticker -= INTERVAL
	}
}
