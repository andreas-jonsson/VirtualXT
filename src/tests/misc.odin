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

package tests

import "core:testing"
import "modules:rom"
import "vxt:machine"

@(test)
cpu_registers :: proc(t: ^testing.T) {
	machine.create()
	defer machine.destroy()
	machine.initialize()

	using regs := machine.registers()

	ax = 0x102
	testing.expect_value(t, ah, 1)
	testing.expect_value(t, al, 2)

	bx = 0x304
	testing.expect_value(t, bh, 3)
	testing.expect_value(t, bl, 4)
	testing.expect_value(t, bx, 0x304)

	// Make sure AX was not affected by BX.
	testing.expect_value(t, ah, 1)
	testing.expect_value(t, al, 2)
	testing.expect_value(t, ax, 0x102)

	cx = 0x506
	testing.expect_value(t, ch, 5)
	testing.expect_value(t, cl, 6)
	testing.expect_value(t, cx, 0x506)

	dx = 0x708
	testing.expect_value(t, dh, 7)
	testing.expect_value(t, dl, 8)
	testing.expect_value(t, dx, 0x708)
}

@(test)
allocate_peripheral :: proc(t: ^testing.T) {
	using machine

	create()
	rom.create("none")
	initialize()
	destroy()
}
