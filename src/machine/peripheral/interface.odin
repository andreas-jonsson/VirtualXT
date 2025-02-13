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

package peripheral

import "core:log"
import "core:reflect"

MAIN_OSCILLATOR :: 14318180

Peripheral_Timer_ID :: int

Peripheral_Class :: enum {
	GENERIC  = 0x01,
	DEBUGGER = 0x02,
	PIC      = 0x04,
	DMA      = 0x08,
	PPI      = 0x10,
	PIT      = 0x20,
	UART     = 0x40,
	VIDEO    = 0x80,
}

Peripheral_Callbacks :: struct($ty: typeid) {
	class:   Peripheral_Class,
	config:  proc(_: ^ty, _: string, _: string, _: any) -> bool,
	install: proc(_: ^ty) -> bool,
	destroy: proc(_: ^ty),
	name:    proc(_: ^ty) -> string,
	reset:   proc(_: ^ty) -> bool,
	timer:   proc(_: ^ty, _: Peripheral_Timer_ID, _: uint),
	read:    proc(_: ^ty, _: u32) -> byte,
	write:   proc(_: ^ty, _: u32, _: byte),
	io_in:   proc(_: ^ty, _: u16) -> byte,
	io_out:  proc(_: ^ty, _: u16, _: byte),
	pic:     struct {
		next: proc(_: ^ty) -> int,
		irq:  proc(_: ^ty, _: uint),
	},
	dma:     struct {
		read:  proc(_: ^ty, _: uint) -> byte,
		write: proc(_: ^ty, _: uint, _: byte),
	},
}

Peripheral :: struct {}

@(private = "file")
Internal_Peripheral :: struct($ty: typeid) {
	cbs:  Peripheral_Callbacks(ty),
	tid:  typeid,
	pidx: uint,
	size: int,
	usr:  ty,
}

@(private = "file")
Timer_Internal :: struct {
	interval:    f64,
	ticks, pidx: uint,
}

peripheral_interface: struct {
	interrupt:  proc(num: uint),
	registers:  proc() -> ^Peripheral_CPU_Registers,
	frequency:  proc() -> uint,
	configure:  proc(id, key: string, value: any) -> bool,
	read:       proc(addr: u32) -> byte,
	write:      proc(addr: u32, data: byte),
	read_port:  proc(port: u16) -> byte,
	write_port: proc(port: u16, data: byte),
}

peripheral_manager: struct {
	peripherals: [dynamic]^Peripheral_Callbacks(Peripheral),
	timers:      [dynamic]Timer_Internal,
	memory_map:  [0x10000]u8,
	io_map:      [0x10000]u8,
}

@(private = "file")
get_internal :: proc(p: any) -> ^Internal_Peripheral(Peripheral) {
	rp := (cast(^rawptr)p.data)^
	pb := uintptr(rp) - offset_of(Internal_Peripheral(Peripheral), usr)
	return cast(^Internal_Peripheral(Peripheral))pb
}

cast_peripheral :: proc(p: any, $ty: typeid, loc := #caller_location) -> ^ty {
	pint := get_internal(p)
	if pint.tid != ty {
		log.panic("invalid peripheral pointer", location = loc)
	}
	return cast(^ty)&pint.usr
}

get_peripheral :: proc(p: ^Peripheral_Callbacks(Peripheral)) -> ^Peripheral {
	return &(cast(^Internal_Peripheral(Peripheral))p).usr
}

get_peripheral_from_class :: proc(class: Peripheral_Class) -> (^Peripheral, ^Peripheral_Callbacks(Peripheral), bool) {
	for p in peripheral_manager.peripherals {
		if p.class == class {
			return get_peripheral(p), p, true
		}
	}
	return nil, nil, false
}

address :: proc(#any_int segment, offset: u16) -> u32 {
	return u32(segment) * 0x10 + u32(offset)
}

allocate :: proc($ty: typeid) -> (^ty, ^Peripheral_Callbacks(ty)) {
	p := new(Internal_Peripheral(ty))
	p.tid = ty
	p.pidx = len(peripheral_manager.peripherals)
	p.size = size_of(p^)

	p.cbs.class = .GENERIC
	p.cbs.name = proc(_: ^ty) -> string {
		return "unknown"
	}

	append(&peripheral_manager.peripherals, cast(^Peripheral_Callbacks(Peripheral))p)
	return &p.usr, &p.cbs
}

register_memory_address_range :: proc(p: any, from, to: u32) {
	pint := get_internal(p)
	assert(pint.tid == reflect.typeid_elem(p.id))

	if ((from | (to + 1)) & 0xF) != 0 {
		log.panicf("trying to register unaligned address")
	}

	pfrom := (from >> 4) & 0xFFFF
	pto := (to >> 4) & 0xFFFF

	for pfrom <= pto {
		peripheral_manager.memory_map[pfrom] = u8(pint.pidx)
		pfrom += 1
	}
}

register_io_address_range :: proc(p: any, from, to: u16) {
	pfrom := u32(from)
	pto := u32(to)

	for pfrom <= pto {
		register_io_address_at(p, u16(pfrom))
		pfrom += 1
	}
}

register_io_address_at :: proc(p: any, port: u16) {
	pint := get_internal(p)
	assert(pint.tid == reflect.typeid_elem(p.id))
	peripheral_manager.io_map[port] = u8(pint.pidx)
}

register_timer :: proc(p: any, us: uint = 0) -> Peripheral_Timer_ID {
	pint := get_internal(p)
	assert(pint.tid == reflect.typeid_elem(p.id))

	id := Peripheral_Timer_ID(len(peripheral_manager.timers))
	append(&peripheral_manager.timers, Timer_Internal{interval = f64(us) / 1000000, pidx = pint.pidx})
	return id
}
