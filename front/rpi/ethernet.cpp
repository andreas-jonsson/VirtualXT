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

#include <circle/synchronize.h>
#include <circle/netdevice.h>

#define _Static_assert static_assert
#define bool bool

#include <vxt/vxtu.h>

#include <assert.h>

#define POLL_DELAY 1000 		// Poll every millisecond.
#define CONFIG_DELAY 2000000 	// Poll every other second.

enum pkt_driver_error {
	BAD_HANDLE = 1,		// Invalid handle number.
	NO_CLASS,			// No interfaces of specified class found.
	NO_TYPE,			// No interfaces of specified type found.
	NO_NUMBER,			// No interfaces of specified number found.
	BAD_TYPE,			// Bad packet type specified.
	NO_MULTICAST,		// This interface does not support multicast.
	CANT_TERMINATE,		// This packet driver cannot terminate.
	BAD_MODE,			// An invalid receiver mode was specified.
	NO_SPACE,			// Operation failed because of insufficient space.
	TYPE_INUSE,			// The type had previously been accessed, and not released.
	BAD_COMMAND,		// The command was out of range, or not implemented.
	CANT_SEND,			// The packet couldn't be sent (usually hardware error).
	CANT_SET,			// Hardware address couldn't be changed (more than 1 handle open).
	BAD_ADDRESS,		// Hardware address has bad length or format.
	CANT_RESET			// Couldn't reset interface (more than 1 handle open).
};

enum pkt_driver_command {
	DRIVE_INFO = 1,
	ACCESS_TYPE,
	RELEASE_TYPE,
	SEND_PACKET,
	TERMINATE,
	GET_ADDRESS,
	RESET_INTERFACE
};

struct ethernet {
	bool can_recv;

	CNetDevice *adapter;
	bool link_up;
	vxt_byte mac_addr[6];
	vxt_timer_id config_timer;

	// Temp buffer for package
	vxt_byte buffer[FRAME_BUFFER_SIZE];

	DMA_BUFFER(u8, rx_buffer, FRAME_BUFFER_SIZE);
	unsigned rx_len;
	
	vxt_word cb_seg;
	vxt_word cb_offset;
};

extern "C" {

static const char *command_to_string(int cmd) {
	#define CASE(cmd) case cmd: return #cmd;
	switch (cmd) {
		CASE(DRIVE_INFO)
		CASE(ACCESS_TYPE)
		CASE(RELEASE_TYPE)
		CASE(SEND_PACKET)
		CASE(TERMINATE)
		CASE(GET_ADDRESS)
		CASE(RESET_INTERFACE)
		case 0xFE: return "GET_CALLBACK";
		case 0xFF: return "COPY_PACKAGE";
	}
	#undef CASE
	return "UNSUPPORTED COMMAND";
}

static vxt_byte in(struct ethernet *n, vxt_word port) {
	(void)n; (void)port;
	// Return 0 to indicate that we have a network card.
	return n->link_up ? 0 : 0xFF;
}

static void out(struct ethernet *n, vxt_word port, vxt_byte data) {
	(void)port; (void)data;
	vxt_system *s = VXT_GET_SYSTEM(n);
	struct vxt_registers *r = vxt_system_registers(s);

	if (!n->link_up) {
		r->flags |= VXT_CARRY;
		return;	
	}

	// Assume no error
	r->flags &= ~VXT_CARRY;
	
	#define ENSURE_HANDLE assert(r->bx == 0)
	#define LOG_COMMAND VXT_LOG(command_to_string(r->ah));

	switch (r->ah) {
		case DRIVE_INFO: LOG_COMMAND
			r->bx = 1; // version
			r->ch = 1; // class
			r->dx = 1; // type
			r->cl = 0; // number
			r->al = 1; // functionality
			// Name in DS:SI is filled in by the driver.
			break;
		case ACCESS_TYPE: LOG_COMMAND
			assert(r->cx == 0);

			// We only support capturing all types.
			// typelen != any_type
			if (r->cx != 0) {
				r->flags |= VXT_CARRY;
				r->dh = BAD_TYPE;
				return;
			}

			n->can_recv = true;
			n->cb_seg = r->es;
			n->cb_offset = r->di;

			VXT_LOG("Callback address: %X:%X", r->es, r->di);

			r->ax = 0; // Handle
			break;
		case RELEASE_TYPE: LOG_COMMAND
			ENSURE_HANDLE;
			break;
		case TERMINATE: LOG_COMMAND
			ENSURE_HANDLE;
			r->flags |= VXT_CARRY;
			r->dh = CANT_TERMINATE;
			return;
		case SEND_PACKET:
			if (r->cx > FRAME_BUFFER_SIZE) {
				VXT_LOG("Can't send! Invalid package size!");
				r->flags |= VXT_CARRY;
				r->dh = CANT_SEND;
				return;
			}

			for (int i = 0; i < (int)r->cx; i++)
				n->buffer[i] = vxt_system_read_byte(s, VXT_POINTER(r->ds, r->si + i));

			if (!n->adapter->SendFrame(n->buffer, r->cx))
				VXT_LOG("Could not send packet!");
				
			VXT_LOG("Sent package with size: %d bytes", r->cx);
			break;
		case GET_ADDRESS: LOG_COMMAND
			ENSURE_HANDLE;
			if (r->cx < 6) {
				VXT_LOG("Can't fit address!");
				r->flags |= VXT_CARRY;
				r->dh = NO_SPACE;
				return;
			}

			r->cx = 6;
			for (int i = 0; i < (int)r->cx; i++)
				vxt_system_write_byte(s, VXT_POINTER(r->es, r->di + i), n->mac_addr[i]);
			break;
		case RESET_INTERFACE: LOG_COMMAND
			ENSURE_HANDLE;
			VXT_LOG("Reset interface!");
			n->can_recv = false; // Not sure about this...
			n->rx_len = 0;
			break;
		case 0xFE: // get_callback
			r->es = n->cb_seg;
			r->di = n->cb_offset;
			r->bx = 0; // Handle
			r->cx = (vxt_word)n->rx_len;
			break;
		case 0xFF: // copy_package
			// Do we have a valid buffer?
			if (r->es || r->di) {
				for (int i = 0; i < n->rx_len; i++)
					vxt_system_write_byte(s, VXT_POINTER(r->es, r->di + i), n->rx_buffer[i]);

				// Callback expects buffer in DS:SI
				r->ds = r->es;
				r->si = r->di;
				r->cx = (vxt_word)n->rx_len;
				
				VXT_LOG("Received package with size: %d bytes", n->rx_len);
			} else {
				VXT_LOG("Package discarded by driver!");
			}

			n->rx_len = 0;
			n->can_recv = true;
			break;
		default: LOG_COMMAND
			r->flags |= VXT_CARRY;
			r->dh = BAD_COMMAND;
			return;
	}
}

static vxt_error reset(struct ethernet *n, struct ebridge *state) {
	if (state)
		return VXT_CANT_RESTORE;
		
	n->rx_len = n->cb_seg = n->cb_offset = 0;
	n->can_recv = false;
	return VXT_NO_ERROR;
}

static const char *name(struct ethernet *n) {
	(void)n; return "Network Adapter";
}

static vxt_error timer(struct ethernet *n, vxt_timer_id id, int cycles) {
	(void)cycles;

	if (id == n->config_timer) {
		if (!(n->link_up = n->adapter->IsLinkUp()))
			n->adapter->UpdatePHY();
		return VXT_NO_ERROR;
	}

	if (!n->link_up || !n->can_recv)
		return VXT_NO_ERROR;

	if (!n->adapter->ReceiveFrame(n->rx_buffer, &n->rx_len))
		return VXT_NO_ERROR;

	n->can_recv = false;
	vxt_system_interrupt(VXT_GET_SYSTEM(n), 6);
	return VXT_NO_ERROR;
}

static vxt_error install(struct ethernet *n, vxt_system *s) {
	if (!(n->adapter = CNetDevice::GetNetDevice(0))) {
		VXT_LOG("Could not initialize network adapter!");
		return VXT_USER_ERROR(0);
	}

	const CMACAddress *addr = n->adapter->GetMACAddress();
	if (!addr) {
		VXT_LOG("Could not read MAC address!");
		return VXT_USER_ERROR(1);
	}
	addr->CopyTo(n->mac_addr);

	struct vxt_peripheral *p = VXT_GET_PERIPHERAL(n);
	vxt_system_install_io_at(s, p, 0xB2);
	vxt_system_install_timer(s, p, POLL_DELAY);
	n->config_timer = vxt_system_install_timer(s, p, CONFIG_DELAY);
	return VXT_NO_ERROR;
}

struct vxt_peripheral *ethernet_create(vxt_allocator *alloc) VXT_PERIPHERAL_CREATE(alloc, ethernet, {
	PERIPHERAL->install = &install;
	PERIPHERAL->name = &name;
	PERIPHERAL->reset = &reset;
	PERIPHERAL->timer = &timer;
	PERIPHERAL->io.in = &in;
	PERIPHERAL->io.out = &out;
})

}
