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

DMA :: struct {
	flip, m2m: bool,
	channels:  [4]struct {
		masked, auto_init, request: bool,
		operation, mode:            byte,
		count, reload_count:        u32,
		addr, reload_addr:          u32,
		addr_step:                  u32,
		page:                       u32,
	},
}

dma_install :: proc(dma: ^DMA) -> bool {
	peripheral.register_io_address_range(dma, 0x0, 0xF)
	peripheral.register_io_address_range(dma, 0x80, 0x8F)
	return true
}

dma_reset :: proc(dma: ^DMA) -> bool {
	dma^ = DMA{}
	for &ch in dma.channels {
		ch.masked = true
	}
	return true
}


dma_io_in :: proc(dma: ^DMA, port: u16) -> byte {
	if port >= 0x80 {
		ch: uint
		switch port & 0xF {
		case 0x1:
			ch = 2
		case 0x2:
			ch = 3
		case 0x3:
			ch = 1
		case 0x7:
			ch = 0
		case:
			return 0xFF
		}
		return byte(dma.channels[ch].page >> 16)
	} else {
		if mp := port & 0xF; mp < 8 {
			channel := &dma.channels[(mp >> 1) & 3]
			target := bool(mp & 1) ? &channel.count : &channel.addr
			data := byte(target^ >> (dma.flip ? 8 : 0))
			dma.flip = !dma.flip
			return data
		} else if mp == 8 {
			return 0xF
		}
		return 0xFF
	}
}

dma_io_out :: proc(dma: ^DMA, port: u16, data: byte) {
	if port >= 0x80 {
		ch: uint
		switch port & 0xF {
		case 0x1:
			ch = 2
		case 0x2:
			ch = 3
		case 0x3:
			ch = 1
		case 0x7:
			ch = 0
		case:
			return
		}
		dma.channels[ch].page = u32(data) << 16
	} else {
		switch mp := port & 0xF; mp {
		case 0 ..= 7:
			channel := &dma.channels[(mp >> 1) & 3]
			target := bool(mp & 1) ? &channel.count : &channel.addr

			if dma.flip {
				target^ = (target^ & 0xFF) | (u32(data) << 8)
			} else {
				target^ = (target^ & 0xFF00) | u32(data)
			}

			if bool(mp & 1) {
				channel.reload_count = target^
			} else {
				channel.reload_addr = target^
			}
			dma.flip = !dma.flip
		case 0x8:
			// Command register
			dma.m2m = bool(data & 1)
		case 0x9:
			// Request register
			dma.channels[data & 3].request = bool((data >> 2) & 1)
		case 0xA:
			// Mask register
			dma.channels[data & 3].masked = bool((data >> 2) & 1)
		case 0xB:
			// Mode register
			channel := dma.channels[data & 3]
			channel.operation = (data >> 2) & 3
			channel.mode = (data >> 6) & 3
			channel.auto_init = bool((data >> 4) & 1)
			channel.addr_step = bool(data & 0x20) ? 0xFFFFFFFF : 1
		case 0xC:
			// Clear flip flop
			dma.flip = false
		case 0xD:
			// Master reset
			dma_reset(dma)
		case 0xF:
			// Write mask register
			for &ch, i in dma.channels {
				ch.masked = bool((data >> uint(i)) & 1)
			}
		}
	}
}

dma_update_count :: proc(dma: ^DMA, channel: uint) {
	using ch := &dma.channels[channel & 3]
	addr += addr_step
	count -= 1

	if (count == 0xFFFF) && auto_init {
		count = reload_count
		addr = reload_addr
	}
}

dma_read :: proc(dma: ^DMA, channel: uint) -> byte {
	ch := dma.channels[channel & 3]
	data := peripheral.peripheral_interface.read(ch.page + ch.addr)
	dma_update_count(dma, channel)
	return data
}

dma_write :: proc(dma: ^DMA, channel: uint, data: byte) {
	ch := dma.channels[channel & 3]
	peripheral.peripheral_interface.write(ch.page + ch.addr, data)
	dma_update_count(dma, channel)
}
