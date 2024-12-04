// Copyright (c) 2019-2024 Andreas T Jonsson <mail@andreasjonsson.se>
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

/*
References: https://github.com/andreas-jonsson/escsitoolbox
            http://www.frogaspi.org/download/aspi32.pdf
*/

#include <vxt/vxtu.h>

#include "aspi.h"
#include "scsidefs.h"

union SRB {
	struct SRB_Header header;
	struct SRB_HAInquiry inquiry;
	struct SRB_GDEVBlock device;
	struct SRB_ExecSCSICmd6 cmd6;
	struct SRB_ExecSCSICmd10 cmd10;
	struct SRB_ExecSCSICmd12 cmd12;
	struct SRB_BusDeviceReset reset;
	struct SRB_Abort abort;
};

struct scsi {
	int _;
};

static void memread(vxt_system *s, void *dest, vxt_pointer src, int size) {
	for (int i = 0; i < size; i++)
		((vxt_byte*)dest)[i] = vxt_system_read_byte(s, src + i);
}

static void memwrite(vxt_system *s, vxt_pointer dest, void *src, int size) {
	for (int i = 0; i < size; i++)
		vxt_system_write_byte(s, dest + i, ((vxt_byte*)src)[i]);
}

static void handle_scsi(struct scsi *a, union SRB *srb) {
	vxt_system *s = VXT_GET_SYSTEM(a);

	if (srb->cmd6.SRB_Target || srb->cmd6.SRB_Lun) {
		srb->cmd6.SRB_Status = SS_NO_DEVICE;
		return;
	}

	VXT_LOG("SRB_Flags: %X", srb->cmd6.SRB_Flags);
	VXT_LOG("SRB_SenseLen: %d", srb->cmd6.SRB_SenseLen);

	switch (*srb->cmd6.CDBByte) {
		case SCSI_TST_U_RDY:
			srb->cmd6.SRB_Status = SS_COMP;
			break;
		case SCSI_INQUIRY:
		{
			VXT_LOG("SCSI_INQUIRY - BUFLEN: %d, BUF: %X:%X", srb->cmd6.SRB_BufLen, srb->cmd6.SRB_BufPointer.seg, srb->cmd6.SRB_BufPointer.offset);

			vxt_pointer ptr = VXT_POINTER(srb->cmd6.SRB_BufPointer.seg, srb->cmd6.SRB_BufPointer.offset);

			memwrite(s, ptr, (vxt_byte[]){DTYPE_CDROM}, 1);
			memwrite(s, ptr + 1, (vxt_byte[]){0x80}, 1); 		// Removable media flag.
			memwrite(s, ptr + 8, "VXT     ", 8);
			memwrite(s, ptr + 16, "VirtualXT CDROM ", 16);
			memwrite(s, ptr + 32, "1.0 ", 4);

			srb->cmd6.SRB_HaStat = HASTAT_OK;
			srb->cmd6.SRB_TargStat = STATUS_GOOD;
			srb->cmd6.SRB_Status = SS_COMP;
			break;
		}
		default:
			VXT_LOG("Unknown SCSI command: %X", *srb->cmd6.CDBByte);
			srb->cmd6.SRB_Status = SS_ERR;
	};
}

static int handle_aspi(struct scsi *a, vxt_pointer ptr, union SRB *srb) {
	vxt_system *s = VXT_GET_SYSTEM(a);
	vxt_byte cmd = srb->header.SRB_Cmd;

	// We only have one adapter.
	if (srb->header.SRB_HaId) {
		srb->header.SRB_Status = SS_INVALID_HA;
		return sizeof(srb->header);
	}

	switch (cmd) {
		case SC_HA_INQUIRY:
			srb->inquiry.SRB_Status = SS_COMP;
			srb->inquiry.HA_Count = 1;		 										// Number of adapters
			srb->inquiry.HA_SCSI_ID = 7;											// Adapter ID
			memcpy((char*)srb->inquiry.HA_ManagerId, "VirtualXT ASPI  ", 16);		// String describing the manager
			memcpy((char*)srb->inquiry.HA_Identifier, "VirtualXT SCSI  ", 16);		// String describing the host adapter
			return sizeof(srb->inquiry);
		case SC_GET_DEV_TYPE:
			memread(s, srb, ptr, sizeof(srb->device));

			// We only have one device atm. (0,0)
			if (srb->device.SRB_Target || srb->device.SRB_Lun) {
				srb->header.SRB_Status = SS_NO_DEVICE;
				break;
			}

			srb->device.SRB_DeviceType = DTYPE_CDROM;
			srb->device.SRB_Status = SS_COMP;
			return sizeof(srb->device);
		case SC_EXEC_SCSI_CMD:
		{
			int sz = sizeof(srb->cmd6);
			memread(s, srb, ptr, sz);
			
			switch (srb->cmd6.SRB_CDBLen) {
				case 6: break;
				case 10:
					sz = sizeof(srb->cmd10);
					memread(s, srb, ptr, sz);
					break;
				case 12:
					sz = sizeof(srb->cmd12);
					memread(s, srb, ptr, sz);
					break;
				default:
					srb->cmd6.SRB_Status = SS_INVALID_SRB;
					break;
			}

			handle_scsi(a, srb);
			return sz;
		}
		case SC_RESET_DEV:
			VXT_LOG("ASPI reset!");
			srb->header.SRB_Status = SS_ERR;
			break;
		case SC_ABORT_SRB:
			VXT_LOG("ASPI abort!");
			srb->header.SRB_Status = SS_ABORT_FAIL;
			break;
		default:
			VXT_LOG("Unknown ASPI command: %X", cmd);
			srb->header.SRB_Status = SS_INVALID_CMD;
	}
	
	return sizeof(srb->header);
}

static vxt_byte in(struct scsi *a, vxt_word port) {
	(void)a; (void)port;
	return 0; // Return 0 to indicate that we have a SCSI card.
}

static void out(struct scsi *a, vxt_word port, vxt_byte data) {
	(void)port; (void)data;
	vxt_system *s = VXT_GET_SYSTEM(a);
	struct vxt_registers *r = vxt_system_registers(s);

	// The ASPI interface uses the Pascal calling convension.
	vxt_word offset = vxtu_system_read_word(s, r->ss, r->sp + 4);
	vxt_word seg = vxtu_system_read_word(s, r->ss, r->sp + 6);
	vxt_pointer ptr = VXT_POINTER(seg, offset);

	union SRB srb = {0};
	memread(s, &srb, ptr, sizeof(srb.header));
	int sz = handle_aspi(a, ptr, &srb);
	memwrite(s, ptr, &srb, sz);
}

static vxt_error reset(struct scsi *a, struct scsi *state) {
	(void)a;
	if (state)
		return VXT_CANT_RESTORE;
	return VXT_NO_ERROR;
}

static const char *name(struct scsi *a) {
	(void)a; return "ASPI compatible SCSI Adapter";
}

static vxt_error install(struct scsi *a, vxt_system *s) {
	struct vxt_peripheral *p = VXT_GET_PERIPHERAL(a);
	vxt_system_install_io_at(s, p, 0xB6);
	return VXT_NO_ERROR;
}

VXTU_MODULE_CREATE(scsi, {
	PERIPHERAL->install = &install;
	PERIPHERAL->name = &name;
	PERIPHERAL->reset = &reset;
	PERIPHERAL->io.in = &in;
	PERIPHERAL->io.out = &out;
})
