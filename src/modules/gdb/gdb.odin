#+private
#+build !freestanding

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

package gdb

import "base:runtime"
import "core:c"
import "core:log"
import "core:os"
import "core:time"

import "vxt:machine/peripheral"

when #config(VXT_GDBSTUB, false) {
	foreign import gdbstub "gdbstub.a"

	@(default_calling_convention = "c")
	foreign gdbstub {
		has_data :: proc(_: c.int) -> c.bool ---
		accept_client :: proc(_: ^GDB_State) -> c.bool ---
		open_server_socket :: proc(_: ^GDB_State) -> c.int ---
		close_socket :: proc(_: c.int) ---

		gdb_main :: proc(_: ^GDB_State) -> c.int ---
		gdb_sys_getc :: proc(_: ^GDB_State) -> c.int ---
		gdb_sys_putchar :: proc(_: ^GDB_State, _: c.int) -> c.int ---
	}
} else {
	has_data :: proc(_: c.int) -> c.bool {return false}
	accept_client :: proc(_: ^GDB_State) -> c.bool {return false}
	open_server_socket :: proc(_: ^GDB_State) -> c.int {return -1}
	close_socket :: proc(_: c.int) {}

	gdb_main :: proc(_: ^GDB_State) -> c.int {return GDB_EOF}
	gdb_sys_getc :: proc(_: ^GDB_State) -> c.int {return GDB_EOF}
	gdb_sys_putchar :: proc(_: ^GDB_State, _: c.int) -> c.int {return GDB_EOF}
}

GDB_EOF :: -1

GDB_Register :: enum {
	REG_EAX       = 0,
	REG_ECX       = 1,
	REG_EDX       = 2,
	REG_EBX       = 3,
	REG_ESP       = 4,
	REG_EBP       = 5,
	REG_ESI       = 6,
	REG_EDI       = 7,
	REG_PC        = 8,
	REG_PS        = 9,
	REG_CS        = 10,
	REG_SS        = 11,
	REG_DS        = 12,
	REG_ES        = 13,
	REG_FS        = 14,
	REG_GS        = 15,
	NUM_REGISTERS = 16,
}

current_context := runtime.default_context()

// DO NOT CHANGE THIS STRUCT!
GDB_State :: struct {
	server, client:         c.int,
	port:                   u16,
	gdb:                    ^GDB,
	current_cs, current_ip: u16,
	signum, noack:          c.int,
	registers:              [GDB_Register.NUM_REGISTERS]c.uint,
}

GDB :: struct {
	state:           GDB_State,
	halt_on_startup: bool,
}

install :: proc(gdb: ^GDB) -> bool {
	peripheral.register_timer(gdb)

	gdb.state.port = 1234
	if err := open_server_socket(&gdb.state); err != 0 {
		log.errorf("Could not open server socket! (Error: %d)", err)
		return false
	}

	if gdb.halt_on_startup {
		log.info("Wait for client to connect...")
		for !accept_client(&gdb.state) {
			time.sleep(time.Millisecond * 100)
		}
		peripheral.peripheral_interface.registers().debug = true
	}
	return false
}

config :: proc(gdb: ^GDB, name, key: string, value: any) -> bool {
	if name != "gdb" {
		return true
	}

	switch key {
	case "halt":
		gdb.halt_on_startup = value.(bool)
	case:
		return false
	}
	return true
}

timer :: proc(using gdb: ^GDB, id: peripheral.Peripheral_Timer_ID, cycles: uint) {
	using cpu_reg := peripheral.peripheral_interface.registers()
	current_context = context

	// Reconnect...
	if accept_client(&state) {
		log.info("Client connected!")
		debug = true
	}

	if state.client == -1 {
		return
	}

	if !debug && has_data(state.client) {
		if gdb_sys_getc(&state) == 3 {
			log.info("Ctrl+C received from GDB client!")
			debug = true
		} else {
			log.warn("Unexpected data received from GDB client!")
		}
	}

	if debug {
		// This helps us step over repeat prefixes.
		if (state.current_cs == cs) && (state.current_ip == ip) {
			return
		}

		log.infof("Debug trap: %4.X:%4.X", cs, ip)
		gdb_reg := &state.registers

		gdb_reg[GDB_Register.REG_EAX] = c.uint(ax)
		gdb_reg[GDB_Register.REG_EBX] = c.uint(bx)
		gdb_reg[GDB_Register.REG_ECX] = c.uint(cx)
		gdb_reg[GDB_Register.REG_EDX] = c.uint(dx)

		gdb_reg[GDB_Register.REG_EBP] = c.uint(bp)
		gdb_reg[GDB_Register.REG_ESI] = c.uint(si)
		gdb_reg[GDB_Register.REG_EDI] = c.uint(di)

		gdb_reg[GDB_Register.REG_CS] = c.uint(cs)
		gdb_reg[GDB_Register.REG_SS] = c.uint(ss)
		gdb_reg[GDB_Register.REG_DS] = c.uint(ds)
		gdb_reg[GDB_Register.REG_ES] = c.uint(es)

		gdb_reg[GDB_Register.REG_PS] = c.uint(u32(transmute(u16)flags))
		gdb_reg[GDB_Register.REG_PC] = c.uint(u32(cs) * 16 + u32(ip))
		gdb_reg[GDB_Register.REG_ESP] = c.uint(u32(ss) * 16 + u32(sp))
		gdb_reg[GDB_Register.REG_FS] = 0
		gdb_reg[GDB_Register.REG_GS] = 0

		for {
			if sig := gdb_main(&state); sig < 0 {
				log.info("GDB client disconnected!", sig)

				state.client = -1
				debug = false
				break
			} else if sig == 13 { 	// SIGPIPE
				log.info("Writing memory dump...")

				fp, err := os.open("memory.dump", os.O_WRONLY | os.O_CREATE, 0o644)
				assert(err == nil)
				defer os.close(fp)

				for addr: u32; addr < 0x100000; addr += 1 {
					os.write_byte(fp, peripheral.peripheral_interface.read(addr))
				}
			} else {
				break
			}
		}

		ax = u16(gdb_reg[GDB_Register.REG_EAX])
		bx = u16(gdb_reg[GDB_Register.REG_EBX])
		cx = u16(gdb_reg[GDB_Register.REG_ECX])
		dx = u16(gdb_reg[GDB_Register.REG_EDX])

		bp = u16(gdb_reg[GDB_Register.REG_EBP])
		si = u16(gdb_reg[GDB_Register.REG_ESI])
		di = u16(gdb_reg[GDB_Register.REG_EDI])

		cs = u16(gdb_reg[GDB_Register.REG_CS])
		ss = u16(gdb_reg[GDB_Register.REG_SS])
		ds = u16(gdb_reg[GDB_Register.REG_DS])
		es = u16(gdb_reg[GDB_Register.REG_ES])

		flag_set := transmute(peripheral.Peripheral_CPU_Flags)u16(gdb_reg[GDB_Register.REG_PS])
		flags = (flag_set & peripheral.VALID_FLAGS) + {.RESERVED_0, .RESERVED_3, .RESERVED_4, .RESERVED_5, .RESERVED_6}

		ip = u16(gdb_reg[GDB_Register.REG_PC] - gdb_reg[GDB_Register.REG_CS] * 16)
		sp = u16(gdb_reg[GDB_Register.REG_ESP] - gdb_reg[GDB_Register.REG_SS] * 16)

		state.current_cs = cs
		state.current_ip = ip
	}
}

@(export)
gdb_sys_mem_readb :: proc "c" (state: ^GDB_State, addr: c.uint, val: ^c.char) -> c.int {
	context = current_context
	val^ = c.char(peripheral.peripheral_interface.read(u32(addr)))
	return 0
}

@(export)
gdb_sys_mem_writeb :: proc "c" (state: ^GDB_State, addr: c.uint, val: c.char) -> c.int {
	context = current_context
	peripheral.peripheral_interface.write(u32(addr), byte(val))
	return 0
}

@(export)
gdb_sys_continue :: proc "c" (state: ^GDB_State) -> c.int {
	context = current_context
	peripheral.peripheral_interface.registers().debug = false
	return 0
}

@(export)
gdb_sys_step :: proc "c" (state: ^GDB_State) -> c.int {
	return 0
}

@(export)
gdb_sys_insert :: proc "c" (state: ^GDB_State, ty: c.uint, addr: c.uint, kind: c.uint) -> c.int {
	return 0
}

@(export)
gdb_sys_remove :: proc "c" (state: ^GDB_State, ty: c.uint, addr: c.uint, kind: c.uint) -> c.int {
	return 0
}
