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

package disk

import "vxt:machine/peripheral"

create :: proc() {
	_, cb := peripheral.allocate(Disk)

	cb.install = install
	cb.destroy = destroy
	cb.config = config
	cb.io_in = io_in
	cb.io_out = io_out

	cb.name = proc(_: ^Disk) -> string {
		return "Disk Controller"
	}

	cb.reset = proc(disk: ^Disk) -> bool {
		for &drive in disk.drives {
			drive.status = 0
			drive.error = false
		}
		return true
	}
}
