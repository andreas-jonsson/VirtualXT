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
            https://www.seagate.com/staticfiles/support/disc/manuals/Interface%20manuals/100293068c.pdf
*/

#include <vxt/vxtu.h>

#include <stdlib.h>
#include <stdio.h>

#include "aspi.h"
#include "scsidefs.h"

#define ASPI_PORT 0xB6
#define BLOCK_SIZE 2048

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

struct cdrom {
	FILE *fp;
	vxt_byte buffer[BLOCK_SIZE];
	char image_name[256];
};

static void memread(vxt_system *s, void *dest, vxt_pointer src, int size) {
	for (int i = 0; i < size; i++)
		((vxt_byte*)dest)[i] = vxt_system_read_byte(s, src + i);
}

static void memwrite(vxt_system *s, vxt_pointer dest, const void *src, int size) {
	for (int i = 0; i < size; i++)
		vxt_system_write_byte(s, dest + i, ((vxt_byte*)src)[i]);
}

static bool check_iso(struct cdrom *d) {
	if (!d->fp)
		return false;
	if (fseek(d->fp, 0x8001, SEEK_SET))
		return false;
	vxt_byte buffer[5] = {0};
	if (fread(buffer, 1, 5, d->fp) != 5)
		return false;
	return (memcmp(buffer, "CD001", 5) == 0);
}

static void handle_scsi(struct cdrom *d, union SRB *srb) {
	vxt_system *s = VXT_GET_SYSTEM(d);

	if (srb->cmd6.SRB_Target || srb->cmd6.SRB_Lun) {
		srb->cmd6.SRB_Status = SS_NO_DEVICE;
		return;
	}

	if (srb->cmd6.SRB_Flags)
		VXT_LOG("WARNING: Unhandled SRB flags: %X", srb->cmd6.SRB_Flags);

	const int sense_area_len = srb->cmd6.SRB_SenseLen;
	SENSE_DATA_FMT *sense_area = (SENSE_DATA_FMT*)(srb->cmd6.CDBByte + srb->cmd6.SRB_CDBLen);

	// Always set this for now.
	srb->cmd6.SRB_HaStat = HASTAT_OK;
	srb->cmd6.SRB_TargStat = STATUS_GOOD;

	switch (*srb->cmd6.CDBByte) {
		case SCSI_TST_U_RDY:
			srb->cmd6.SRB_Status = SS_COMP;
			break;
		case SCSI_REZERO:
			srb->cmd6.SRB_Status = SS_COMP;
			break;
		case SCSI_SEEK6: // We don't need to handle this because most commands specify LBA.
			srb->cmd6.SRB_Status = SS_COMP;
			break;
		case SCSI_REQ_SENSE:
			VXT_LOG("Request sense!");
			memset(sense_area, 0, sense_area_len);
			srb->cmd6.SRB_Status = SS_COMP;
			break;
		case SCSI_INQUIRY:
		{
			const vxt_pointer ptr = VXT_POINTER(srb->cmd6.SRB_BufPointer.seg, srb->cmd6.SRB_BufPointer.offset);

			memwrite(s, ptr, (vxt_byte[]){DTYPE_CDROM}, 1);
			memwrite(s, ptr + 1, (vxt_byte[]){0x80}, 1); 		// Removable media flag.
			memwrite(s, ptr + 8, "VXT     ", 8);
			memwrite(s, ptr + 16, "VirtualXT CDROM ", 16);
			memwrite(s, ptr + 32, "1.0 ", 4);

			srb->cmd6.SRB_Status = SS_COMP;
			break;
		}
		case SCSI_MODE_SEL6:
			// TODO: How to handle this?
			srb->cmd6.SRB_Status = SS_COMP;
			break;
		case SCSI_LOAD_UN:
			if (srb->cmd6.CDBByte[4] & 2) {
				VXT_LOG("Eject media!");
				if (d->fp) {
					fclose(d->fp);
					d->fp = NULL;
				}
			}
			srb->cmd6.SRB_Status = SS_COMP;
			break;
		case SCSI_READ6:
		{
			const vxt_byte *data = srb->cmd6.CDBByte;
			vxt_pointer ptr = VXT_POINTER(srb->cmd6.SRB_BufPointer.seg, srb->cmd6.SRB_BufPointer.offset);
			const unsigned lba = (((unsigned)data[1] & 0x1F) << 16) | ((unsigned)data[2] << 8) | (unsigned)data[3];
			const unsigned nblock = data[4] ? data[4] : 256;

			if ((nblock * BLOCK_SIZE) > srb->cmd6.SRB_BufLen) {		
				srb->cmd6.SRB_Status = SS_ERR;
				return;
			}

			if (!d->fp) {
				memset(sense_area, 0, sense_area_len);
				sense_area->ErrorCode = SERROR_CURRENT;
				sense_area->SenseKey = KEY_NOTREADY;

				srb->cmd6.SRB_TargStat = STATUS_CHKCOND;
				srb->cmd6.SRB_Status = SS_ERR;
				return;
			}

			// TODO: Add more error checking.
			fseek(d->fp, lba * BLOCK_SIZE, SEEK_SET);			
			for (unsigned i = 0; i < nblock; i++) {
				fread(d->buffer, BLOCK_SIZE, 1, d->fp);
				memwrite(s, ptr, d->buffer, BLOCK_SIZE);
				ptr += BLOCK_SIZE;
			}
			
			srb->cmd6.SRB_Status = SS_COMP;
			break;
		}
		default:
			VXT_LOG("Unknown SCSI command: %X (%d)", *srb->cmd6.CDBByte, srb->cmd6.SRB_CDBLen);
			srb->cmd6.SRB_Status = SS_ERR;
	};
}

static int handle_aspi(struct cdrom *d, vxt_pointer ptr, union SRB *srb) {
	vxt_system *s = VXT_GET_SYSTEM(d);
	const vxt_byte cmd = srb->header.SRB_Cmd;

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

			handle_scsi(d, srb);
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

static vxt_byte in(struct cdrom *d, vxt_word port) {
	(void)d; (void)port;
	return 0; // Return 0 to indicate that we have a SCSI card.
}

static void out(struct cdrom *d, vxt_word port, vxt_byte data) {
	(void)port; (void)data;
	vxt_system *s = VXT_GET_SYSTEM(d);
	const struct vxt_registers *r = vxt_system_registers(s);

	// The ASPI interface uses the Pascal calling convension.
	const vxt_word offset = vxtu_system_read_word(s, r->ss, r->sp + 4);
	const vxt_word seg = vxtu_system_read_word(s, r->ss, r->sp + 6);
	const vxt_pointer ptr = VXT_POINTER(seg, offset);

	union SRB srb = {0};
	memread(s, &srb, ptr, sizeof(srb.header));
	int sz = handle_aspi(d, ptr, &srb);
	memwrite(s, ptr, &srb, sz);
}

static vxt_error reset(struct cdrom *d, struct cdrom *state) {
	(void)d;
	return state ? VXT_CANT_RESTORE : VXT_NO_ERROR;
}

static const char *name(struct cdrom *d) {
	(void)d; return "SCSI CD-ROM";
}

static vxt_error destroy(struct cdrom *d) {
	if (d->fp)
		fclose(d->fp);
    vxt_system_allocator(VXT_GET_SYSTEM(d))(VXT_GET_PERIPHERAL(d), 0);
    return VXT_NO_ERROR;
}

static vxt_error install(struct cdrom *d, vxt_system *s) {
	if (*d->image_name) {
		if (!(d->fp = fopen(d->image_name, "rb"))) {
			VXT_LOG("Could not open: %s", d->image_name);
		} else if (!check_iso(d)) {
			VXT_LOG("File is not a valid ISO image: %s", d->image_name);
			fclose(d->fp);
			d->fp = NULL;
		}
	} else {
		VXT_LOG("No media in drive!");
	}
	
	vxt_system_install_io_at(s, VXT_GET_PERIPHERAL(d), ASPI_PORT);
	return VXT_NO_ERROR;
}

VXTU_MODULE_CREATE(cdrom, {
	// TODO: Currently there is no frontend interface support!

	strncpy(DEVICE->image_name, ARGS, sizeof(DEVICE->image_name) - 1);
	
	PERIPHERAL->install = &install;
	PERIPHERAL->name = &name;
	PERIPHERAL->reset = &reset;
	PERIPHERAL->destroy = &destroy;
	PERIPHERAL->io.in = &in;
	PERIPHERAL->io.out = &out;
})
