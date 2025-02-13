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

PPI_TONE_VOLUME :: 8192

ppi_generate_sample :: proc(p: ^peripheral.Peripheral, freq: uint) -> i16 {
	ppi := peripheral.cast_peripheral(p, PPI)
	assert(ppi.pit != nil)

	tone_hz := pit_get_frequency(ppi.pit, 2)
	if !ppi.spk_enabled || (tone_hz <= 0) {
		return 0
	}

	square_wave_period := i64(f64(freq) / tone_hz)
	half_square_wave_period := square_wave_period / 2

	if half_square_wave_period == 0 {
		return 0
	}

	ppi.spk_sample_index += 1
	return bool((ppi.spk_sample_index / half_square_wave_period) % 2) ? PPI_TONE_VOLUME : -PPI_TONE_VOLUME
}

ppi_push_event :: proc(p: ^peripheral.Peripheral, scan: byte) {
	ppi := peripheral.cast_peripheral(p, PPI)
	assert(ppi.pit != nil)

	if !ppi.kb_reset {
		ppi.data_port = scan
		peripheral.peripheral_interface.interrupt(1)
	}
}

pit_get_frequency :: proc(p: ^peripheral.Peripheral, channel: int) -> f64 {
	switch channel {
	case 0 ..= 2:
		pit := peripheral.cast_peripheral(p, PIT)
		fd := f64(pit.channels[channel].chdata)

		if fd == 0 {
			fd = f64(0x10000)
		}
		return PIT_FREQUENCY / f64(fd)
	case:
		return 0
	}
}

create :: proc() {
	{
		_, cb := peripheral.allocate(PIT)
		cb.class = .PIT

		cb.install = pit_install
		cb.timer = pit_timer
		cb.io_in = pit_io_in
		cb.io_out = pit_io_out

		cb.name = proc(_: ^PIT) -> string {
			return "PIT (Intel 8253)"
		}

		cb.reset = proc(pit: ^PIT) -> bool {
			pit^ = PIT{}
			return true
		}
	}
	{
		_, cb := peripheral.allocate(PIC)

		cb.class = .PIC

		cb.install = pic_install
		cb.io_in = pic_io_in
		cb.io_out = pic_io_out

		cb.pic.next = pic_next
		cb.pic.irq = pic_irq

		cb.name = proc(_: ^PIC) -> string {
			return "PIC (Intel 8259)"
		}

		cb.reset = proc(pic: ^PIC) -> bool {
			pic^ = PIC{}
			return true
		}
	}
	{
		ppi, cb := peripheral.allocate(PPI)
		ppi.xt_switches = 0x2E // 640K ram, 80 column CGA, 1 floppy drive, no fpu.
	
		cb.class = .PPI
		cb.install = ppi_install
		cb.config = ppi_config
		cb.io_in = ppi_io_in
		cb.io_out = ppi_io_out

		cb.name = proc(_: ^PPI) -> string {
			return "PPI (Intel 8255)"
		}

		cb.reset = proc(ppi: ^PPI) -> bool {
			ppi^ = PPI {
				xt_switches   = ppi.xt_switches,
				pit           = ppi.pit,
			}
			return true
		}
	}
	{
		_, cb := peripheral.allocate(DMA)
		cb.class = .DMA

		cb.install = dma_install
		cb.reset = dma_reset
		cb.io_in = dma_io_in
		cb.io_out = dma_io_out

		cb.dma.read = dma_read
		cb.dma.write = dma_write

		cb.name = proc(_: ^DMA) -> string {
			return "DMA (Intel 8237)"
		}
	}
}
