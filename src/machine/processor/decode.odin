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

package processor

import "vxt:machine/peripheral"

decode_prepare :: proc() {
	state.invert_quotient = false
	state.div_zero = false

	state.base_ds = .DATA
	state.base_ss = .STACK

	state.instruction = Instruction {
		valid = true, // This is set to false in the decode switch.
		stream = {ip = registers.ip, addr = get_physical_address(Segment.CODE, registers.ip)},
	}
}

decode_prefix :: proc() {
	using state, state.instruction
	for {
		opcode.raw = decode_fetch_byte()

		// TODO: Not sure about this. Perhaps handle this in a nicer way?
		registers.ip += 1
		stream.size = 0

		switch opcode.raw {
		case 0x26:
			// Segment Ovrride: ES
			base_ds = .EXTRA
			base_ss = .EXTRA
		case 0x2E:
			// Segment Ovrride: CS
			base_ds = .CODE
			base_ss = .CODE
		case 0x36:
			// Segment Ovrride: SS
			base_ds = .STACK
			base_ss = .STACK
		case 0x3E:
			// Segment Ovrride: DS
			base_ds = .DATA
			base_ss = .DATA
		case 0xF0: // LOCK
		case 0xF2, 0xF3:
			// REPNE, REP/REPE
			rep_prefix = opcode.raw
		case:
			if rep_prefix != 0 {
				switch opcode.raw {
				case 0xA4 ..= 0xA7, 0xAA ..= 0xAF:
					return // Opcode is valid to repeat.
				case 0xF6, 0xF7:
					invert_quotient = true // Not valid but has side effects for IDIV.
				}
				rep_prefix = 0
			}
			return
		}
	}
}

decode_fetch_byte :: proc() -> byte {
	using state.instruction

	data := read_segment_byte(.CODE, registers.ip + u16(stream.size))
	stream.data[stream.size] = data
	stream.size += 1

	assert(stream.size <= MAX_INSTRUCTION_SIZE)
	return data
}

decode_fetch_word :: proc() -> u16 {
	low := decode_fetch_byte()
	high := decode_fetch_byte()
	return (u16(high) << 8) | u16(low)
}

decode_opcode :: proc() {
	using state.instruction

	switch opcode.raw {
	case 0x00:
		// ADD eb,rb - Add byte register into EA byte
		exec = proc() {
			store_eb(ADD(load_eb(), load_rb()))
		}
		decode_mod_reg_rm()
	case 0x01:
		// ADD ew,rw - Add word register into EA word
		exec = proc() {
			store_ew(ADD(load_ew(), load_rw()))
		}
		decode_mod_reg_rm()
	case 0x02:
		// ADD rb,eb - Add EA byte into byte register
		exec = proc() {
			store_rb(ADD(load_rb(), load_eb()))
		}
		decode_mod_reg_rm()
	case 0x03:
		// ADD rw,ew - Add EA word into word register
		exec = proc() {
			store_rw(ADD(load_rw(), load_ew()))
		}
		decode_mod_reg_rm()
	case 0x04:
		// ADD AL,ib - Add immediate byte into AL
		exec = proc() {
			using registers
			al = ADD(al, state.instruction.ib)
		}
		ib = decode_fetch_byte()
	case 0x05:
		// ADD AX,iw - Add immediate word into AX
		exec = proc() {
			using registers
			ax = ADD(ax, state.instruction.iw1)
		}
		iw1 = decode_fetch_word()
	case 0x06:
		// PUSH ES
		exec = PUSH_SR
		reg_seg = .EXTRA
	case 0x07:
		// POP ES
		exec = POP_SR
		reg_seg = .EXTRA
	case 0x08:
		// OR eb,rb - Logical OR byte register into EA byte
		exec = proc() {
			store_eb(OR(load_eb(), load_rb()))
		}
		decode_mod_reg_rm()
	case 0x09:
		// OR ew,rw - Logical OR word register into EA word
		exec = proc() {
			store_ew(OR(load_ew(), load_rw()))
		}
		decode_mod_reg_rm()
	case 0x0A:
		// OR rb,eb - Logical OR EA byte into byte register
		exec = proc() {
			store_rb(OR(load_rb(), load_eb()))
		}
		decode_mod_reg_rm()
	case 0x0B:
		// OR rw,ew - Logical OR EA word into word register
		exec = proc() {
			store_rw(OR(load_rw(), load_ew()))
		}
		decode_mod_reg_rm()
	case 0x0C:
		// OR AL,ib - Logical OR immediate byte into AL
		exec = proc() {
			using registers
			al = OR(al, state.instruction.ib)
		}
		ib = decode_fetch_byte()
	case 0x0D:
		// OR AX,iw - Logical OR immediate word into AX
		exec = proc() {
			using registers
			ax = OR(ax, state.instruction.iw1)
		}
		iw1 = decode_fetch_word()
	case 0x0E:
		// PUSH CS
		exec = PUSH_SR
		reg_seg = .CODE
	case 0x10:
		// ADC eb,rb - Add with carry byte register into EA byte
		exec = proc() {
			store_eb(ADC(load_eb(), load_rb()))
		}
		decode_mod_reg_rm()
	case 0x11:
		// ADC ew,rw - Add with carry word register into EA word
		exec = proc() {
			store_ew(ADC(load_ew(), load_rw()))
		}
		decode_mod_reg_rm()
	case 0x12:
		// ADC rb,eb - Add with carry EA byte into byte register
		exec = proc() {
			store_rb(ADC(load_rb(), load_eb()))
		}
		decode_mod_reg_rm()
	case 0x13:
		// ADC rw,ew - Add with carry EA word into word register
		exec = proc() {
			store_rw(ADC(load_rw(), load_ew()))
		}
		decode_mod_reg_rm()
	case 0x14:
		// ADC AL,ib - Add with carry immediate byte into AL
		exec = proc() {
			using registers
			al = ADC(al, state.instruction.ib)
		}
		ib = decode_fetch_byte()
	case 0x15:
		// ADC AX,iw - Add with carry immediate word into AX
		exec = proc() {
			using registers
			ax = ADC(ax, state.instruction.iw1)
		}
		iw1 = decode_fetch_word()
	case 0x16:
		// PUSH SS
		exec = PUSH_SR
		reg_seg = .STACK
	case 0x17:
		// POP SS
		exec = POP_SR
		reg_seg = .STACK
	case 0x18:
		// SBB eb,rb - Subtract with borrow byte register into EA byte
		exec = proc() {
			store_eb(SBB(load_eb(), load_rb()))
		}
		decode_mod_reg_rm()
	case 0x19:
		// SBB ew,rw - Subtract with borrow word register into EA word
		exec = proc() {
			store_ew(SBB(load_ew(), load_rw()))
		}
		decode_mod_reg_rm()
	case 0x1A:
		// SBB rb,eb - Subtract with borrow EA byte into byte register
		exec = proc() {
			store_rb(SBB(load_rb(), load_eb()))
		}
		decode_mod_reg_rm()
	case 0x1B:
		// SBB rw,ew - Subtract with borrow EA word into word register
		exec = proc() {
			store_rw(SBB(load_rw(), load_ew()))
		}
		decode_mod_reg_rm()
	case 0x1C:
		// SBB AL,ib - Subtract with borrow immediate byte into AL
		exec = proc() {
			using registers
			al = SBB(al, state.instruction.ib)
		}
		ib = decode_fetch_byte()
	case 0x1D:
		// SBB AX,iw - Subtract with borrow immediate word into AX
		exec = proc() {
			using registers
			ax = SBB(ax, state.instruction.iw1)
		}
		iw1 = decode_fetch_word()
	case 0x1E:
		// PUSH DS
		exec = PUSH_SR
		reg_seg = .DATA
	case 0x1F:
		// POP DS
		exec = POP_SR
		reg_seg = .DATA
	case 0x20:
		// AND eb,rb - Logical AND byte register into EA byte
		exec = proc() {
			store_eb(AND(load_eb(), load_rb()))
		}
		decode_mod_reg_rm()
	case 0x21:
		// AND ew,rw - Logical AND word register into EA word
		exec = proc() {
			store_ew(AND(load_ew(), load_rw()))
		}
		decode_mod_reg_rm()
	case 0x22:
		// AND rb,eb - Logical AND EA byte into byte register
		exec = proc() {
			store_rb(AND(load_rb(), load_eb()))
		}
		decode_mod_reg_rm()
	case 0x23:
		// AND rw,ew - Logical AND EA word into word register
		exec = proc() {
			store_rw(AND(load_rw(), load_ew()))
		}
		decode_mod_reg_rm()
	case 0x24:
		// AND AL,ib - Logical AND immediate byte into AL
		exec = proc() {
			using registers
			al = AND(al, state.instruction.ib)
		}
		ib = decode_fetch_byte()
	case 0x25:
		// AND AX,iw - Logical AND immediate word into AX
		exec = proc() {
			using registers
			ax = AND(ax, state.instruction.iw1)
		}
		iw1 = decode_fetch_word()
	case 0x27:
		// DAA - Decimal adjust AL after addition
		exec = DAA
	case 0x28:
		// SUB eb,rb - Subtract byte register into EA byte
		exec = proc() {
			store_eb(SUB(load_eb(), load_rb()))
		}
		decode_mod_reg_rm()
	case 0x29:
		// SUB ew,rw - Subtract word register into EA word
		exec = proc() {
			store_ew(SUB(load_ew(), load_rw()))
		}
		decode_mod_reg_rm()
	case 0x2A:
		// SUB rb,eb - Subtract EA byte into byte register
		exec = proc() {
			store_rb(SUB(load_rb(), load_eb()))
		}
		decode_mod_reg_rm()
	case 0x2B:
		// SUB rw,ew - Subtract EA word into word register
		exec = proc() {
			store_rw(SUB(load_rw(), load_ew()))
		}
		decode_mod_reg_rm()
	case 0x2C:
		// SUB AL,ib - Subtract immediate byte into AL
		exec = proc() {
			using registers
			al = SUB(al, state.instruction.ib)
		}
		ib = decode_fetch_byte()
	case 0x2D:
		// SUB AX,iw - Subtract immediate word into AX
		exec = proc() {
			using registers
			ax = SUB(ax, state.instruction.iw1)
		}
		iw1 = decode_fetch_word()
	case 0x2F:
		// DAS - Decimal adjust AL after subtraction
		exec = DAS
	case 0x30:
		// XOR eb,rb - Logical XOR byte register into EA byte
		exec = proc() {
			store_eb(XOR(load_eb(), load_rb()))
		}
		decode_mod_reg_rm()
	case 0x31:
		// XOR ew,rw - Logical XOR word register into EA word
		exec = proc() {
			store_ew(XOR(load_ew(), load_rw()))
		}
		decode_mod_reg_rm()
	case 0x32:
		// XOR rb,eb - Logical XOR EA byte into byte register
		exec = proc() {
			store_rb(XOR(load_rb(), load_eb()))
		}
		decode_mod_reg_rm()
	case 0x33:
		// XOR rw,ew - Logical XOR EA word into word register
		exec = proc() {
			store_rw(XOR(load_rw(), load_ew()))
		}
		decode_mod_reg_rm()
	case 0x34:
		// XOR AL,ib - Logical XOR immediate byte into AL
		exec = proc() {
			using registers
			al = XOR(al, state.instruction.ib)
		}
		ib = decode_fetch_byte()
	case 0x35:
		// XOR AX,iw - Logical XOR immediate word into AX
		exec = proc() {
			using registers
			ax = XOR(ax, state.instruction.iw1)
		}
		iw1 = decode_fetch_word()
	case 0x37:
		// AAA - ASCII adjust AL after addition
		exec = proc() {
			ASCII(1)
		}
	case 0x38:
		// CMP eb,rb - Compare byte register from EA byte
		exec = proc() {
			SUB(load_eb(), load_rb())
		}
		decode_mod_reg_rm()
	case 0x39:
		// CMP eb,rb - Compare word register from EA word
		exec = proc() {
			SUB(load_ew(), load_rw())
		}
		decode_mod_reg_rm()
	case 0x3A:
		// CMP rb,eb - Compare EA byte from byte register
		exec = proc() {
			SUB(load_rb(), load_eb())
		}
		decode_mod_reg_rm()
	case 0x3B:
		// CMP rw,ew - Compare word from word register
		exec = proc() {
			SUB(load_rw(), load_ew())
		}
		decode_mod_reg_rm()
	case 0x3C:
		// CMP AL,ib - Compare immediate byte from AL
		exec = proc() {
			SUB(registers.al, state.instruction.ib)
		}
		ib = decode_fetch_byte()
	case 0x3D:
		// CMP AX,iw - Compare immediate word from AX
		exec = proc() {
			SUB(registers.ax, state.instruction.iw1)
		}
		iw1 = decode_fetch_word()
	case 0x3F:
		// AAS - ASCII adjust AL after subtraction
		exec = proc() {
			ASCII(-1)
		}
	case 0x40 ..= 0x47:
		// INC rw - Increment word register
		reg_gen = opcode.raw - 0x40
		exec = proc() {
			store_rw_op(INC_w(load_rw_op()))
		}
	case 0x48 ..= 0x4F:
		// DEC rw - Decrement word register
		reg_gen = opcode.raw - 0x48
		exec = proc() {
			store_rw_op(DEC_w(load_rw_op()))
		}
	case 0x50 ..= 0x53, 0x55 ..= 0x57:
		// PUSH rw - Push word register
		reg_gen = opcode.raw - 0x50
		exec = proc() {
			stack_push(load_rw_op())
		}
	case 0x54:
		// PUSH SP
		exec = proc() {
			using registers
			sp -= 2
			write_segment_word(.STACK, sp, sp)
		}
	case 0x58 ..= 0x5B, 0x5D ..= 0x5F:
		// POP rw - Pop word register
		reg_gen = opcode.raw - 0x58
		exec = proc() {
			store_rw_op(stack_pop())
		}
	case 0x5C:
		// POP SP
		exec = proc() {
			using registers
			sp = read_segment_word(.STACK, sp)
		}
	case 0x70:
		// JO cb - Jump short if overflow
		exec = proc() {
			if .OVERFLOW in registers.flags {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x71:
		// JNO cb - Jump short if not overflow
		exec = proc() {
			if .OVERFLOW not_in registers.flags {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x72:
		// JC cb - Jump short if carry
		exec = proc() {
			if .CARRY in registers.flags {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x73:
		// JNC cb - Jump short if not carry
		exec = proc() {
			if .CARRY not_in registers.flags {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x74:
		// JE cb - Jump short if equal/zero
		exec = proc() {
			if .ZERO in registers.flags {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x75:
		// JNE cb - Jump short if not equal/zero
		exec = proc() {
			if .ZERO not_in registers.flags {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x76:
		// JBE cb - Jump short if below or equal
		exec = proc() {
			using registers
			if (.CARRY in flags) || (.ZERO in flags) {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x77:
		// JA cb - Jump short if above
		exec = proc() {
			using registers
			if (.CARRY not_in flags) && (.ZERO not_in flags) {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x78:
		// JS cb - Jump short if sign
		exec = proc() {
			if .SIGN in registers.flags {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x79:
		// JNS cb - Jump short if not sign
		exec = proc() {
			if .SIGN not_in registers.flags {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x7A:
		// JPE cb - Jump short if parity even
		exec = proc() {
			if .PARITY in registers.flags {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x7B:
		// JPO cb - Jump short if parity odd
		exec = proc() {
			if .PARITY not_in registers.flags {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x7C:
		// JL cb - Jump short if less
		exec = proc() {
			using registers
			if (.SIGN in flags) != (.OVERFLOW in flags) {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x7D:
		// JNL cb - Jump short if not less
		exec = proc() {
			using registers
			if (.SIGN in flags) == (.OVERFLOW in flags) {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x7E:
		// JLE cb - Jump short if less or equal
		exec = proc() {
			using registers
			if (.SIGN in flags) != (.OVERFLOW in flags) || (.ZERO in flags) {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x7F:
		// JNLE cb - Jump short if not less or equal
		exec = proc() {
			using registers
			if (.SIGN in flags) == (.OVERFLOW in flags) && (.ZERO not_in flags) {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0x80, 0x82:
		decode_mod_reg_rm()
		ib = decode_fetch_byte()

		switch mode.reg {
		case 0:
			// ADD eb,ib
			exec = proc() {
				store_eb(ADD(load_eb(), state.instruction.ib))
			}
		case 1:
			// OR eb,ib
			exec = proc() {
				store_eb(OR(load_eb(), state.instruction.ib))
			}
		case 2:
			// ADC eb,ib
			exec = proc() {
				store_eb(ADC(load_eb(), state.instruction.ib))
			}
		case 3:
			// SBB eb,ib
			exec = proc() {
				store_eb(SBB(load_eb(), state.instruction.ib))
			}
		case 4:
			// AND eb,ib
			exec = proc() {
				store_eb(AND(load_eb(), state.instruction.ib))
			}
		case 5:
			// SUB eb,ib
			exec = proc() {
				store_eb(SUB(load_eb(), state.instruction.ib))
			}
		case 6:
			// XOR eb,ib
			exec = proc() {
				store_eb(XOR(load_eb(), state.instruction.ib))
			}
		case 7:
			// CMP eb,ib
			exec = proc() {
				SUB(load_eb(), state.instruction.ib)
			}
		}
	case 0x81:
		decode_mod_reg_rm()
		iw1 = decode_fetch_word()

		switch mode.reg {
		case 0:
			// ADD ew,iw
			exec = proc() {
				store_ew(ADD(load_ew(), state.instruction.iw1))
			}
		case 1:
			// OR ew,iw
			exec = proc() {
				store_ew(OR(load_ew(), state.instruction.iw1))
			}
		case 2:
			// ADC ew,iw
			exec = proc() {
				store_ew(ADC(load_ew(), state.instruction.iw1))
			}
		case 3:
			// SBB ew,iw
			exec = proc() {
				store_ew(SBB(load_ew(), state.instruction.iw1))
			}
		case 4:
			// AND ew,iw
			exec = proc() {
				store_ew(AND(load_ew(), state.instruction.iw1))
			}
		case 5:
			// SUB ew,iw
			exec = proc() {
				store_ew(SUB(load_ew(), state.instruction.iw1))
			}
		case 6:
			// XOR ew,iw
			exec = proc() {
				store_ew(XOR(load_ew(), state.instruction.iw1))
			}
		case 7:
			// CMP ew,iw
			exec = proc() {
				SUB(load_ew(), state.instruction.iw1)
			}
		}
	case 0x83:
		decode_mod_reg_rm()
		ib = decode_fetch_byte()

		switch mode.reg {
		case 0:
			// ADD ew,ib
			exec = proc() {
				store_ew(ADD(load_ew(), u16(i8(state.instruction.ib))))
			}
		case 1:
			// OR ew,ib
			exec = proc() {
				store_ew(OR(load_ew(), u16(i8(state.instruction.ib))))
			}
		case 2:
			// ADC ew,ib
			exec = proc() {
				store_ew(ADC(load_ew(), u16(i8(state.instruction.ib))))
			}
		case 3:
			// SBB ew,ib
			exec = proc() {
				store_ew(SBB(load_ew(), u16(i8(state.instruction.ib))))
			}
		case 4:
			// AND ew,ib
			exec = proc() {
				store_ew(AND(load_ew(), u16(i8(state.instruction.ib))))
			}
		case 5:
			// SUB ew,ib
			exec = proc() {
				store_ew(SUB(load_ew(), u16(i8(state.instruction.ib))))
			}
		case 6:
			// XOR ew,ib
			exec = proc() {
				store_ew(XOR(load_ew(), u16(i8(state.instruction.ib))))
			}
		case 7:
			// CMP ew,ib
			exec = proc() {
				SUB(load_ew(), u16(i8(state.instruction.ib)))
			}
		}
	case 0x84:
		// TEST eb,rb - AND byte register into EA byte (flags only)
		exec = proc() {
			AND(load_eb(), load_rb())
		}
		decode_mod_reg_rm()
	case 0x85:
		// TEST ew,rw - AND word register into EA word (flags only)
		exec = proc() {
			AND(load_ew(), load_rw())
		}
		decode_mod_reg_rm()
	case 0x86:
		// XCHG eb,rb - Exchange byte register with EA byte
		exec = proc() {
			v := load_eb()
			store_eb(load_rb())
			store_rb(v)
		}
		decode_mod_reg_rm()
	case 0x87:
		// XCHG ew,rw - Exchange word register with EA word
		exec = proc() {
			v := load_ew()
			store_ew(load_rw())
			store_rw(v)
		}
		decode_mod_reg_rm()
	case 0x88:
		// MOV eb,rb - Move byte register into EA byte
		exec = proc() {
			store_eb(load_rb())
		}
		decode_mod_reg_rm()
	case 0x89:
		// MOV ew,rw - Move word register into EA word
		exec = proc() {
			store_ew(load_rw())
		}
		decode_mod_reg_rm()
	case 0x8A:
		// MOV rb,eb - Move EA byte into byte register
		exec = proc() {
			store_rb(load_eb())
		}
		decode_mod_reg_rm()
	case 0x8B:
		// MOV rw,ew - Move EA word into word register
		exec = proc() {
			store_rw(load_ew())
		}
		decode_mod_reg_rm()
	case 0x8C:
		// MOV ew,SR - Move segment register into EA word
		exec = proc() {
			store_ew(load_sr())
		}
		decode_mod_reg_rm()
	case 0x8D:
		// LEA rw,m - Calculate EA offset given by m and place in rw
		exec = proc() {
			store_rw(state.instruction.ea_offset)
		}
		decode_mod_reg_rm()
	case 0x8E:
		// MOV SR,mw - Move memory word into segment register
		exec = proc() {
			store_sr(load_ew())
		}
		decode_mod_reg_rm()
	case 0x8F:
		// POP mw - Pop top of stack into memory word
		exec = proc() {
			store_ew(stack_pop())
		}
		decode_mod_reg_rm()
	case 0x90:
		// NOP
		exec = proc() {}
	case 0x91 ..= 0x97:
		// XCHG AX,rw - Exchange word register with AX
		reg_gen = opcode.raw - 0x90
		exec = proc() {
			using registers
			v := load_rw_op()
			store_rw_op(ax)
			ax = v
		}
	case 0x98:
		// CBW - Convert byte into word
		exec = proc() {
			using registers
			ah = (al & 0x80 != 0) ? 0xFF : 0
		}
	case 0x99:
		// CWD - Convert word to doubleword
		exec = proc() {
			using registers
			dx = (ax & 0x8000 != 0) ? 0xFFFF : 0
		}
	case 0x9A:
		// CALL cd - Call inter-segment, immediate 4-byte address
		exec = proc() {
			using state.instruction
			call(iw2, iw1)
		}
		iw1 = decode_fetch_word()
		iw2 = decode_fetch_word()
	case 0x9B:
		// WAIT
		exec = proc() {}
	case 0x9C:
		// PUSHF
		exec = proc() {
			stack_push(registers.flags)
		}
	case 0x9D:
		// POPF
		exec = proc() {
			registers.flags = flags_to_set(validate_flags(stack_pop()))
		}
	case 0x9E:
		// SAHF - Store AH into flags
		exec = proc() {
			using registers
			flags = (flags & VALID_HIGH_FLAGS) + flags_to_set(validate_flags(ah))
		}
	case 0x9F:
		// LAHF - Load flags into AH
		exec = proc() {
			using registers
			ah = u8(transmute(u16)flags)
		}
	case 0xA0:
		// MOV AL,xb - Move byte variable at segment:offset into AL
		exec = proc() {
			using state
			registers.al = read_segment_byte(base_ds, instruction.iw1)
		}
		iw1 = decode_fetch_word()
	case 0xA1:
		// MOV AX,xw - Move word variable at segment:offset into AX
		exec = proc() {
			using state
			registers.ax = read_segment_word(base_ds, instruction.iw1)
		}
		iw1 = decode_fetch_word()
	case 0xA2:
		// MOV xb,AL - Move AL into byte variable at segment:offset
		exec = proc() {
			using state
			write_segment_byte(base_ds, instruction.iw1, registers.al)
		}
		iw1 = decode_fetch_word()
	case 0xA3:
		// MOV xw,AX - Move AX into word register at segment:offset
		exec = proc() {
			using state
			write_segment_word(base_ds, instruction.iw1, registers.ax)
		}
		iw1 = decode_fetch_word()
	case 0xA4:
		// MOVSB - Move byte from string to string
		exec = proc() {
			using registers
			write_segment_byte(.EXTRA, di, read_segment_byte(state.base_ds, si))
			update_si_di_direction(1)
		}
	case 0xA5:
		// MOVSW - Move word from string to string
		exec = proc() {
			using registers
			write_segment_word(.EXTRA, di, read_segment_word(state.base_ds, si))
			update_si_di_direction(2)
		}
	case 0xA6:
		// CMPSB - Compare bytes ES:[DI] from DS:[SI], advance SI, DI
		exec = proc() {
			using registers
			SUB(read_segment_byte(state.base_ds, si), read_segment_byte(.EXTRA, di))
			update_si_di_direction(1)
		}
	case 0xA7:
		// CMPSW - Compare words ES:[DI] from DS:[SI], advance SI, DI
		exec = proc() {
			using registers
			SUB(read_segment_word(state.base_ds, si), read_segment_word(.EXTRA, di))
			update_si_di_direction(2)
		}
	case 0xA8:
		// TEST AL,ib - AND immediate byte into AL (flags only)
		exec = proc() {
			AND(registers.al, state.instruction.ib)
		}
		ib = decode_fetch_byte()
	case 0xA9:
		// TEST AX,iw - AND immediate word into AX (flags only)
		exec = proc() {
			AND(registers.ax, state.instruction.iw1)
		}
		iw1 = decode_fetch_word()
	case 0xAA:
		// STOSB - Store AL to byte ES:[DI], advance DI
		exec = proc() {
			using registers
			write_segment_byte(.EXTRA, di, al)
			di = (.DIRECTION in flags) ? (di - 1) : (di + 1)
		}
	case 0xAB:
		// STOSW - Store AX to word ES:[DI], advance DI
		exec = proc() {
			using registers
			write_segment_word(.EXTRA, di, ax)
			di = (.DIRECTION in flags) ? (di - 2) : (di + 2)
		}
	case 0xAC:
		// LODSB - Load byte DS:[SI] into AL, advance SI
		exec = proc() {
			using registers
			al = read_segment_byte(state.base_ds, si)
			si = (.DIRECTION in flags) ? (si - 1) : (si + 1)
		}
	case 0xAD:
		// LODSW - Load word DS:[SI] into AX, advance SI
		exec = proc() {
			using registers
			ax = read_segment_word(state.base_ds, si)
			si = (.DIRECTION in flags) ? (si - 2) : (si + 2)
		}
	case 0xAE:
		// SCASB - Compare bytes AL from ES:[DI], advance DI
		exec = proc() {
			using registers
			SUB(al, read_segment_byte(.EXTRA, di))
			di = (.DIRECTION in flags) ? (di - 1) : (di + 1)
		}
	case 0xAF:
		// SCASW - Compare words AX from ES:[DI], advance DI
		exec = proc() {
			using registers
			SUB(ax, read_segment_word(.EXTRA, di))
			di = (.DIRECTION in flags) ? (di - 2) : (di + 2)
		}
	case 0xB0 ..= 0xB7:
		// MOV rb,ib - Move imm byte into byte register
		exec = proc() {
			store_rb_op(state.instruction.ib)
		}
		reg_gen = opcode.raw - 0xB0
		ib = decode_fetch_byte()
	case 0xB8 ..= 0xBF:
		// MOV rw,iw - Move imm word into word register
		exec = proc() {
			store_rw_op(state.instruction.iw1)
		}
		reg_gen = opcode.raw - 0xB8
		iw1 = decode_fetch_word()
	case 0xC2:
		// RET iw - Return near, pop iw bytes pushed before call
		exec = proc() {
			return_near(stack_pop(), state.instruction.iw1)
		}
		iw1 = decode_fetch_word()
	case 0xC3:
		// RET - Return near
		exec = proc() {
			return_near(stack_pop())
		}
	case 0xC4:
		// LES rw,mp - Load ES:r16 with pointer from memory
		exec = proc() {
			reg, seg := load_m1616()
			registers.es = seg
			store_rw(reg)
		}
		decode_mod_reg_rm()
	case 0xC5:
		// LDS rw,mp - Load DS:r16 with pointer from memory
		exec = proc() {
			reg, seg := load_m1616()
			registers.ds = seg
			store_rw(reg)
		}
		decode_mod_reg_rm()
	case 0xC6:
		// MOV eb,ib - Move immediate byte into EA byte
		exec = proc() {
			store_eb(state.instruction.ib)
		}
		decode_mod_reg_rm()
		ib = decode_fetch_byte()
	case 0xC7:
		// MOV ew,iw - Move immediate word into EA word
		exec = proc() {
			store_ew(state.instruction.iw1)
		}
		decode_mod_reg_rm()
		iw1 = decode_fetch_word()
	case 0xCA:
		// RET iw - Return to far caller, pop iw bytes
		iw1 = decode_fetch_word()
		fallthrough
	case 0xCB:
		// RET - Return to far caller
		exec = proc() {
			ip := stack_pop()
			cs := stack_pop()
			return_far(cs, ip, state.instruction.iw1)
		}
	case 0xCC:
		// INT 3 - Debug trap
		exec = proc() {
			throw_exception(.DEBUG_TRAP_EXC)
		}
	case 0xCD:
		// INT ib - Interrupt numbered by immediate byte
		exec = proc() {
			throw_exception(Exception(state.instruction.ib))
		}
		ib = decode_fetch_byte()
	case 0xCE:
		// INTO - Overflow
		exec = proc() {
			if .OVERFLOW in registers.flags {
				throw_exception(.OVERFLOW_EXC)
			}
		}
	case 0xCF:
		// IRET - Interrupt return
		exec = proc() {
			ip := stack_pop()
			cs := stack_pop()
			registers.flags = flags_to_set(validate_flags(stack_pop()))
			branch(cs, ip)
		}
	case 0xD0, 0xD2:
		decode_mod_reg_rm()
		state.shift_count = (opcode.raw == 0xD0) ? 1 : registers.cl

		switch mode.reg {
		case 0:
			// ROL eb,1
			exec = proc() {
				store_eb(ROL(load_eb(), state.shift_count))
			}
		case 1:
			// ROR eb,1
			exec = proc() {
				store_eb(ROR(load_eb(), state.shift_count))
			}
		case 2:
			// RCL eb,1
			exec = proc() {
				store_eb(RCL(load_eb(), state.shift_count))
			}
		case 3:
			// RCR eb,1
			exec = proc() {
				store_eb(RCR(load_eb(), state.shift_count))
			}
		case 4, 6:
			// SHL/SAL eb,1
			exec = proc() {
				store_eb(SHL(load_eb(), state.shift_count))
			}
		case 5:
			// SHR eb,1
			exec = proc() {
				store_eb(SHR(load_eb(), state.shift_count))
			}
		case 7:
			// SAR eb,1
			exec = proc() {
				store_eb(SAR(load_eb(), state.shift_count))
			}
		}
	case 0xD1, 0xD3:
		decode_mod_reg_rm()
		state.shift_count = (opcode.raw == 0xD1) ? 1 : registers.cl

		switch mode.reg {
		case 0:
			// ROL ew,1
			exec = proc() {
				store_ew(ROL(load_ew(), state.shift_count))
			}
		case 1:
			// ROR ew,1
			exec = proc() {
				store_ew(ROR(load_ew(), state.shift_count))
			}
		case 2:
			// RCL ew,1
			exec = proc() {
				store_ew(RCL(load_ew(), state.shift_count))
			}
		case 3:
			// RCR ew,1
			exec = proc() {
				store_ew(RCR(load_ew(), state.shift_count))
			}
		case 4, 6:
			// SHL/SAL ew,1
			exec = proc() {
				store_ew(SHL(load_ew(), state.shift_count))
			}
		case 5:
			// SHR ew,1
			exec = proc() {
				store_ew(SHR(load_ew(), state.shift_count))
			}
		case 7:
			// SAR ew,1
			exec = proc() {
				store_ew(SAR(load_ew(), state.shift_count))
			}
		}
	case 0xD4:
		// AAM - ASCII adjust AX after multiply
		exec = AAM
		ib = decode_fetch_byte()
	case 0xD5:
		// AAD - ASCII adjust AX before division
		exec = proc() {
			using registers
			ax = (u16(ah) * u16(state.instruction.ib) + u16(al)) & 0xFF
			set_psz_flags(al)
		}
		ib = decode_fetch_byte()
	case 0xD6:
		// SALC - Set AL If Carry
		exec = proc() {
			using registers
			al = (.CARRY in flags) ? 0xFF : 0x0
		}
	case 0xD7:
		// XLATB - Set AL to memory byte DS:[BX + AL]
		exec = proc() {
			using registers
			al = read_segment_byte(get_ea_segment(), bx + u16(al))
		}
	case 0xD8 ..= 0xDF:
		// ESC - FPU opcode
		exec = proc() {}
		decode_mod_reg_rm()
	case 0xE0:
		// LOOPNZ cb - DEC CX, jump short if CX<>0 and ZF=0
		exec = proc() {
			using registers
			cx -= 1
			if (cx != 0) && (.ZERO not_in flags) {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0xE1:
		// LOOPZ cb - DEC CX, jump short if CX<>0 and ZF=1
		exec = proc() {
			using registers
			cx -= 1
			if (cx != 0) && (.ZERO in flags) {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0xE2:
		// LOOP cb - DEC CX, jump short if CX<>0
		exec = proc() {
			using registers
			cx -= 1
			if cx != 0 {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0xE3:
		// JCXZ cb - Jump short if CX is zero
		exec = proc() {
			if registers.cx == 0 {
				branch(i8(state.instruction.ib))
			}
		}
		ib = decode_fetch_byte()
	case 0xE4:
		// IN AL,ib - Input byte from immediate port into AL
		exec = proc() {
			registers.al = peripheral.peripheral_interface.read_port(u16(state.instruction.ib))
		}
		ib = decode_fetch_byte()
	case 0xE5:
		// IN AX,ib - Input word from immediate port into AX
		exec = proc() {
			registers.ax = u16(peripheral.peripheral_interface.read_port(u16(state.instruction.ib))) | 0xFF00
		}
		ib = decode_fetch_byte()
	case 0xE6:
		// OUT ib,AL - Output byte AL to immediate port number ib
		exec = proc() {
			peripheral.peripheral_interface.write_port(u16(state.instruction.ib), registers.al)
		}
		ib = decode_fetch_byte()
	case 0xE7:
		// OUT ib,AX Output word AX to immediate port number ib
		exec = proc() {
			using registers, state.instruction, peripheral.peripheral_interface
			write_port(u16(ib), byte(ax))
			write_port(u16(ib) + 1, byte(ax >> 8))
		}
		ib = decode_fetch_byte()
	case 0xE8:
		// CALL cw - Call near, offset relative to next instruction
		exec = proc() {
			call(i16(state.instruction.iw1))
		}
		iw1 = decode_fetch_word()
	case 0xE9:
		// JMP cw - Jump near displacement relative to next instruction
		exec = proc() {
			branch(i16(state.instruction.iw1))
		}
		iw1 = decode_fetch_word()
	case 0xEA:
		// JMP cd - Jump far
		exec = proc() {
			using state.instruction
			branch(iw2, iw1)
		}
		iw1 = decode_fetch_word()
		iw2 = decode_fetch_word()
	case 0xEB:
		// JMP cb - Jump short
		exec = proc() {
			branch(i8(state.instruction.ib))
		}
		ib = decode_fetch_byte()
	case 0xEC:
		// IN AL,DX - Input byte from port DX into AL
		exec = proc() {
			using registers
			al = peripheral.peripheral_interface.read_port(dx)
		}
	case 0xED:
		// IN AX,DX - Input word from port DX into AX
		exec = proc() {
			using registers, peripheral.peripheral_interface
			ax = (u16(read_port(dx + 1)) << 8) | u16(read_port(dx))
		}
	case 0xEE:
		// OUT DX,AL - Output byte AL to port number DX
		exec = proc() {
			using registers
			peripheral.peripheral_interface.write_port(dx, al)
		}
	case 0xEF:
		// OUT DX,AX - Output word AX to port number DX
		exec = proc() {
			using registers, peripheral.peripheral_interface
			write_port(dx, al)
			write_port(dx + 1, ah)
		}
	case 0xF4:
		// HALT
		exec = proc() {}
	case 0xF5:
		// CMC - Complement carry flag
		exec = proc() {
			set_flags({.CARRY}, .CARRY not_in registers.flags)
		}
	case 0xF6:
		decode_mod_reg_rm()

		switch mode.reg {
		case 0, 1:
			// TEST eb,ib - AND immediate byte into EA byte (flags only)
			ib = decode_fetch_byte()
			exec = proc() {
				AND(load_eb(), state.instruction.ib)
			}
		case 2:
			// NOT eb - Reverse each bit of EA byte
			exec = proc() {
				store_eb(~load_eb())
			}
		case 3:
			// NEG eb - Two's complement negate EA byte
			exec = proc() {
				v := load_eb()
				r := ~v + 1
				SUB(0, v)
				set_flags({.CARRY}, r)
				store_eb(r)
			}
		case 4:
			// MUL eb - Unsigned multiply (AX = AL * EA byte)
			exec = MUL_eb
		case 5:
			// IMUL eb - Signed multiply (AX = AL * EA byte)
			exec = IMUL_eb
		case 6:
			// DIV eb - Unsigned divide AX by EA byte
			exec = DIV_eb
		case 7:
			// IDIV eb - Signed divide AX by EA byte (AL=Quo,AH=Rem)
			exec = IDIV_eb
		}
	case 0xF7:
		decode_mod_reg_rm()

		switch mode.reg {
		case 0, 1:
			// TEST ew,iw - AND immediate word into EA word (flags only)
			iw1 = decode_fetch_word()
			exec = proc() {
				AND(load_ew(), state.instruction.iw1)
			}
		case 2:
			// NOT ew - Reverse each bit of EA word
			exec = proc() {
				store_ew(~load_ew())
			}
		case 3:
			// NEG ew - Two's complement negate EA word
			exec = proc() {
				v := load_ew()
				r := ~v + 1
				SUB(0, v)
				set_flags({.CARRY}, r)
				store_ew(r)
			}
		case 4:
			// MUL ew - Unsigned multiply (DXAX = AX * EA word)
			exec = MUL_ew
		case 5:
			// IMUL ew - Signed multiply (DXAX = AX * EA word)
			exec = IMUL_ew
		case 6:
			// DIV ew - Unsigned divide DX:AX by EA word
			exec = DIV_ew
		case 7:
			// IDIV ew - Signed divide DX:AX by EA word (AX=Quo,DX=Rem)
			exec = IDIV_ew
		}
	case 0xF8:
		// CLC - Clear carry flag
		exec = proc() {
			registers.flags -= {.CARRY}
		}
	case 0xF9:
		// STC - Set carry flag
		exec = proc() {
			registers.flags += {.CARRY}
		}
	case 0xFA:
		// CLI - Clear interrupt flag (interrupts disabled)
		exec = proc() {
			registers.flags -= {.INTERRUPT}
		}
	case 0xFB:
		// STI - Set interrupt enable flag (interrupts enabled)
		exec = proc() {
			registers.flags += {.INTERRUPT}
		}
	case 0xFC:
		// CLD - Clear direction flag, SI and DI will increment
		exec = proc() {
			registers.flags -= {.DIRECTION}
		}
	case 0xFD:
		// STD - Set direction flag so SI and DI will decrement
		exec = proc() {
			registers.flags += {.DIRECTION}
		}
	case 0xFE:
		decode_mod_reg_rm()

		switch mode.reg {
		case 0:
			// INC eb - Increment EA byte by 1
			exec = INC_eb
		case 1:
			// DEC eb - Decrement EA byte by 1
			exec = DEC_eb
		case 2 ..= 7:
			valid = false
		}
	case 0xFF:
		decode_mod_reg_rm()

		switch mode.reg {
		case 0:
			// INC ew - Increment EA word by 1
			exec = proc() {
				store_ew(INC_w(load_ew()))
			}
		case 1:
			// DEC ew - Decrement EA word by 1
			exec = proc() {
				store_ew(DEC_w(load_ew()))
			}
		case 2:
			// CALL ew - Call near, offset absolute at EA word
			exec = proc() {
				ip := load_ew()
				stack_push(registers.ip)
				branch(ip)
			}
		case 3:
			// CALL ed - Call inter-segment, address at EA doubleword
			exec = proc() {
				using state.instruction

				ea_seg := get_ea_segment()
				cs := read_segment_word(ea_seg, ea_offset + 2)
				ip := read_segment_word(ea_seg, ea_offset)

				stack_push(registers.cs)
				stack_push(registers.ip)
				branch(cs, ip)
			}
		case 4:
			// JMP ew - Jump near to EA word (absolute offset)
			exec = proc() {
				branch(load_ew())
			}
		case 5:
			// JMP ed - Jump far (4-byte effective address in memory doubleword)
			exec = proc() {
				using state.instruction
				ea_seg := get_ea_segment()
				branch(read_segment_word(ea_seg, ea_offset + 2), read_segment_word(ea_seg, ea_offset))
			}
		case 6, 7:
			// PUSH mw - Push memory word
			exec = proc() {
				using registers
				sp -= 2
				write_segment_word(.STACK, sp, load_ew())
			}
		}
	case 0x26, 0x2E, 0x36, 0x3E, 0xF0, 0xF2, 0xF3:
		panic("prefixes should not be decoded here")
	case:
		valid = false
	}
}
