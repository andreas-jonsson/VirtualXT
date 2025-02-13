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

package rom

import "core:log"
import "core:slice"

import "vxt:machine/peripheral"

ROM :: struct {
	id, name: string,
	base:     u32,
	mem:      []byte,
}

config :: proc(rom: ^ROM, name, key: string, value: any) -> bool {
	if name != rom.id {
		return true
	}

	switch key {
	case "name":
		rom.name = value.(string)
	case "mem":
		rom.mem = slice.clone(value.([]byte))
	case "base":
		rom.base = value.(u32)
		assert(rom.base & 0x7FF == 0, "ROM must be 2K aligned")
	case:
		return false
	}
	return true
}

install :: proc(using rom: ^ROM) -> bool {
	peripheral.register_memory_address_range(rom, base, base + u32(len(mem)) - 1)
	return true
}

name :: proc(rom: ^ROM) -> string {
	return rom.name
}

read :: proc(using rom: ^ROM, addr: u32) -> byte {
	return mem[addr - base]
}

write :: proc(rom: ^ROM, _: u32, _: byte) {
	log.warnf("ROM (%s) is not writable!", rom.name)
}

destroy :: proc(rom: ^ROM) {
	delete(rom.mem)
}
