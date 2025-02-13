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

package cga

import "core:math/rand"

import "vxt:machine/peripheral"

create :: proc() {
	cga, cb := peripheral.allocate(CGA)
	_ = rand.read(cga.mem[:])
	
	cb.class = .VIDEO
	cb.install = install
	cb.config = config
	cb.timer = timer
	cb.read = read
	cb.write = write
	cb.io_in = io_in
	cb.io_out = io_out
	cb.reset = reset

	cb.name = proc(^CGA) -> string {
		return "CGA Compatible Video Adapter"
	}
}
