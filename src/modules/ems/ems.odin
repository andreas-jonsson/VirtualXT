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

package ems

import "core:log"

import "vxt:machine/peripheral"

// The Lo-tech EMS board driver is hardcoded to 2MB.
MEMORY_SIZE :: 0x200000

EMS :: struct {
	mem: [MEMORY_SIZE]byte,
	mem_base: u32,
	io_base: u16,
	page_selectors: [4]byte,
}

install :: proc(using ems: ^EMS) -> bool {
	peripheral.register_memory_address_range(ems, mem_base, mem_base + 0xFFFF)
	peripheral.register_io_address_range(ems, io_base, io_base + 3)
	return true
}

config :: proc(ems: ^EMS, name, key: string, value: any) -> (ok := true) {
	if name != "ems" {
		return
	}

	switch key {
	case "address":
		ems.mem_base = value.(u32)
	case "port":
		ems.io_base = value.(u16)
	case:
		ok = false
	}
	return
}

physical_address :: proc(ems: ^EMS,  #any_int addr: u32) -> u32 {
	frame_addr := addr - ems.mem_base
	page_addr := frame_addr & 0x3FFF
	selector := ems.page_selectors[(frame_addr >> 14) & 3]
	return u32(selector) * 0x4000 + page_addr
}

read :: proc(ems: ^EMS, addr: u32) -> byte {
	phys_addr := physical_address(ems, addr)
	return (phys_addr < MEMORY_SIZE) ? ems.mem[phys_addr] : 0xFF
}

write :: proc(ems: ^EMS, addr: u32, data: byte) {
	phys_addr := physical_address(ems, addr)
	if phys_addr < MEMORY_SIZE {
		ems.mem[phys_addr] = data
	}
}

io_in :: proc(ems: ^EMS, port: u16) -> byte {
	log.warn("Register read is not supported!")
	return 0xFF
}

io_out :: proc(ems: ^EMS, port: u16, data: byte) {
	sel := port - ems.io_base
	ems.page_selectors[sel & 3] = data
}
