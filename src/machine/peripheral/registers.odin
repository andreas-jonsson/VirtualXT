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

Peripheral_CPU_Flags :: bit_set[enum {
	CARRY,
	RESERVED_0,
	PARITY,
	RESERVED_1,	
	AUXILIARY,
	RESERVED_2,
	ZERO,
	SIGN,
	TRAP,
	INTERRUPT,
	DIRECTION,
	OVERFLOW,
	RESERVED_3,
	RESERVED_4,
	RESERVED_5,
	RESERVED_6,
}; u16]

VALID_LOW_FLAGS :: Peripheral_CPU_Flags {
	.CARRY,
	.PARITY,
	.AUXILIARY,
	.ZERO,
	.SIGN,
}

VALID_HIGH_FLAGS :: Peripheral_CPU_Flags {
	.TRAP,
	.INTERRUPT,
	.DIRECTION,
	.OVERFLOW,
}

VALID_FLAGS :: VALID_HIGH_FLAGS | VALID_LOW_FLAGS

Peripheral_CPU_Registers :: struct {
	using _: struct #raw_union {
		using _: struct #packed {
			al, ah: byte,
		},
		ax: u16,
	},
	using _: struct #raw_union {
		using _: struct #packed {
			bl, bh: byte,
		},
		bx: u16,
	},
	using _: struct #raw_union {
		using _: struct #packed {
			cl, ch: byte,
		},
		cx: u16,
	},
	using _: struct #raw_union {
		using _: struct #packed {
			dl, dh: byte,
		},
		dx: u16,
	},
	sp, bp, si, di: u16,
	cs, ss, ds, es: u16,
	ip:             u16,
	flags:          Peripheral_CPU_Flags,
	debug:          bool,
}
