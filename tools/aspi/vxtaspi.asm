; Copyright (c) 2019-2024 Andreas T Jonsson <mail@andreasjonsson.se>
;
; This software is provided 'as-is', without any express or implied
; warranty. In no event will the authors be held liable for any damages
; arising from the use of this software.
;
; Permission is granted to anyone to use this software for any purpose,
; including commercial applications, and to alter it and redistribute it
; freely, subject to the following restrictions:
;
; 1. The origin of this software must not be misrepresented; you must not
;    claim that you wrote the original software. If you use this software in
;    a product, an acknowledgment (see the following) in the product
;    documentation is required.
;
;    This product make use of the VirtualXT software emulator.
;    Visit https://virtualxt.org for more information.
;
; 2. Altered source versions must be plainly marked as such, and must not be
;    misrepresented as being the original software.
;
; 3. This notice may not be removed or altered from any source distribution.

; --------------------------------------------
; Reference: https://github.com/cr1901/devdriv
; --------------------------------------------

%define VERSION '0.0.1'
%define ASPI_PORT 0xB6
;%define DEBUG out 0xB3, al

cpu 186

struc header
  next: resd 1
  attr: resw 1
  strat: resw 1
  intr: resw 1
  name: resb 8
endstruc

struc drivereq
  .len: resb 1
  .unit: resb 1
  .cmd: resb 1
  .status: resw 1
  .dosq: resd 1
  .devq: resd 1
endstruc

struc wrreq
  .hdr: resb drivereq_size
  .desc: resb 1
  .xferaddr: resd 1
  .count: resw 1
  .start: resw 1
endstruc

struc initreq
  .hdr: resb drivereq_size
  .numunits: resb 1
  .brkaddr: resd 1
  .bpbaddr: resd 1
endstruc

struc ndreq
  .hdr: resb drivereq_size
  .byteread: resb 1
endstruc

; Status return bits- high
%define STATUS_ERROR      (1 << 15)
%define STATUS_BUSY       (1 << 9)
%define STATUS_DONE       (1 << 8)

; Error codes (Status return bits- low)
%define WRITE_PROTECT     0
%define UNKNOWN_UNIT      1
%define DRIVE_NOT_READY   2
%define UNKNOWN_COMMAND   3
%define CRC_ERROR         4
%define BAD_DRIVE_REQ     5
%define SEEK_ERROR        6
%define UNKNOWN_MEDIA     7
%define SECTOR_NOT_FOUND  8
%define OUT_OF_PAPER      9
%define WRITE_FAULT     0xA
%define READ_FAULT      0xB
%define GENERAL_FAILURE 0xC

hdr:
istruc header
  at next, dd -1
  at attr, dw 0xC000
  at strat, dw strategy
  at intr, dw interrupt
  at name, db 'SCSIMGR$'
iend

; Driver data
packet_ptr dd 0

strategy:
  mov cs:[packet_ptr], bx
  mov cs:[packet_ptr+2], es
  retf

interrupt:
  pusha

  les di, cs:[packet_ptr]
  mov si, es:[di + drivereq.cmd]
  cmp si, 11
  ja .bad_cmd

  shl si, 1
  jmp [.fntab + si]

.bad_cmd:
  mov al, UNKNOWN_COMMAND
.err:
  xor ah, ah
  or ah, (STATUS_ERROR | STATUS_DONE) >> 8
  mov es:[di + drivereq.status], ax
  jmp .end
.exit:
  mov word es:[di + drivereq.status], STATUS_DONE
.end:
  popa
  retf

.fntab:
  dw init   ;  0      INIT
  dw .exit  ;  1      MEDIA CHECK (Block only, NOP for character)
  dw .exit  ;  2      BUILD BPB      "    "     "    "   "
  dw icread ;  3      IOCTL INPUT (Only called if device has IOCTL)
  dw .exit  ;  4      INPUT (read)
  dw .exit  ;  5      NON-DESTRUCTIVE INPUT NO WAIT (Char devs only)
  dw .exit  ;  6      INPUT STATUS                    "     "    "
  dw .exit  ;  7      INPUT FLUSH                     "     "    "
  dw .exit  ;  8      OUTPUT (write)
  dw .exit  ;  9      OUTPUT (Write) with verify
  dw .exit  ; 10      OUTPUT STATUS                   "     "    "
  dw .exit  ; 11      OUTPUT FLUSH                    "     "    "
  dw .exit  ; 12      IOCTL OUTPUT (Only called if device has IOCTL)

icread:
  push es
  pop ds
  
  cmp word [di + wrreq.count], 4
  jne interrupt.err
  
  mov si, di
  les di, [si + wrreq.xferaddr]
  
  mov word es:[di], aspi_entry
  mov es:[di + 2], cs
  
  mov word [si + wrreq.count], 4

  mov di, si ; Make sure ES:DI points at the right place to set status.
  jmp interrupt.exit

; ASPI Entry
aspi_entry:
  out ASPI_PORT, al
  retf

; Init data does not need to be kept, so it goes last.
res_end:
init:
  push cs
  pop ds
  in al, ASPI_PORT
  test al, 0
  je .ok
  mov dx, install_err_msg
  mov ah, 0x9
  int 0x21
  jmp interrupt.err
.ok:
  mov dx, install_msg
  mov ah, 0x9
  int 0x21
  mov word es:[di + initreq.brkaddr], res_end
  mov word es:[di + initreq.brkaddr + 2], cs
  jmp interrupt.exit

install_msg db 'VirtualXT ASPI Manager v ', VERSION, ' installed.', 0xD, 0xA, '$'
install_err_msg db 'ERROR! No compatible SCSI adapter found!', 0xD, 0xA, '$'
