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

#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>

#ifdef _WIN32
	#include <winsock2.h>
	#include <ws2tcpip.h>
	#define close closesocket
	#define sleep Sleep
#else
	#include <unistd.h>
	#include <sys/socket.h>
	#include <sys/select.h>
	#include <netinet/in.h>
	#include <netinet/tcp.h>
#endif

#define GDB_CPU_NUM_REGISTERS 16

typedef unsigned address;
typedef unsigned reg;

// DO NOT CHANGE THIS STRUCT!
struct gdb_state {
	int server, client;
	unsigned short port;
	void *peripheral;

	unsigned short current_cs;
	unsigned short current_ip;

	int signum;
	int noack;
	reg registers[GDB_CPU_NUM_REGISTERS];
};

#define DEBUG 0
#define GDBSTUB_IMPLEMENTATION
#include "gdbstub/gdbstub.h"

bool has_data(int fd) {
	if (fd == -1)
		return false;

	fd_set fds;
	FD_ZERO(&fds);
    FD_SET(fd, &fds);
	struct timeval timeout = {0};

    return select(fd + 1, &fds, NULL, NULL, &timeout) > 0;
}

bool accept_client(struct gdb_state *state) {
    if ((state->client != -1) || !has_data(state->server))
		return false;

    struct sockaddr_in addr;
    socklen_t ln = sizeof(addr);
    if ((state->client = accept(state->server, (struct sockaddr*)&addr, &ln)) == -1)
        return false;
        
    const int one = 1;
    setsockopt(state->client, IPPROTO_TCP, TCP_NODELAY, (void*)&one, sizeof(one));
    return true;
}

int open_server_socket(struct gdb_state *state) {
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_port = htons(state->port);
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_family = AF_INET;

    if ((state->server = socket(AF_INET, SOCK_STREAM, 0)) == -1) {
        return 1;
 	}
 	
    if (bind(state->server, (struct sockaddr*)&addr, sizeof(addr))) {
        return 2;
	}
	
    if (listen(state->server, 1)) {
        return 3;
    }
    return 0;
}

void close_socket(int fd) {
	close(fd);
}

int gdb_sys_getc(struct gdb_state *state) {
    char buf[1] = {GDB_EOF};
    if (recv(state->client, buf, 1, 0) != 1) {
        close(state->client);
        state->client = -1;
        return GDB_EOF;
    }
    return *buf;
}

int gdb_sys_putchar(struct gdb_state *state, int ch) {
    char buf[1] = {(char)ch};
    ssize_t ret = send(state->client, buf, 1, 0);
    if (ret != 1) {
        close(state->client);
        state->client = -1;
        return GDB_EOF;
    }
    return (int)ret;
}
