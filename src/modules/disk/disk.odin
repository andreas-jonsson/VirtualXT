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

package disk

import "core:log"
import "core:strings"

import retro "vxt:frontend/libretro"
import "vxt:machine/peripheral"

BOOTSECTOR_ADDRESS :: 0x7C00
SECTOR_SIZE :: 512

Drive :: struct {
	fp:                        ^retro.vfs_file_handle,
	size:                      uint,
	is_hd:                     bool,
	cylinders, sectors, heads: u16,
	status:                    byte,
	error:                     bool,
}

Disk :: struct {
	vfs:                        ^retro.vfs_interface,
	boot_drive, num_hd, num_fd: byte,
	drives:                     [0x100]Drive,
}

install :: proc(disk: ^Disk) -> bool {
	// IO 0xB0, 0xB1 to interrupt 0x19, 0x13
	peripheral.register_io_address_range(disk, 0xB0, 0xB1)
	return true
}

destroy :: proc(disk: ^Disk) {
	for &drive in disk.drives {
		if drive.fp != nil {
			disk.vfs.close(drive.fp)
		}
	}
}

execute_operation :: proc(disk: ^Disk, drive: ^Drive, read: bool, addr: u32, cylinders, sectors, heads: u16, count: byte) -> (num: byte) {
	if sectors == 0 {
		return
	}

	lba := (i64(cylinders) * i64(drive.heads) + i64(heads)) * i64(drive.sectors) + i64(sectors) - 1
	if disk.vfs.seek(drive.fp, lba * SECTOR_SIZE, retro.VFS_SEEK_POSITION_START) != 0 {
		return
	}
	defer disk.vfs.flush(drive.fp)

	buffer: [SECTOR_SIZE]byte
	for num < count {
		offset := addr + (u32(num) * SECTOR_SIZE)

		if read {
			if disk.vfs.read(drive.fp, &buffer[0], SECTOR_SIZE) != SECTOR_SIZE {
				return
			}
			for data in buffer {
				peripheral.peripheral_interface.write(offset, data)
				offset += 1
			}
		} else {
			for &data in buffer {
				data = peripheral.peripheral_interface.read(offset)
				offset += 1
			}
			if disk.vfs.write(drive.fp, &buffer[0], SECTOR_SIZE) != SECTOR_SIZE {
				return
			}
		}
		num += 1
	}
	return
}

execute_and_set :: proc(disk: ^Disk, read: bool) {
	using reg := peripheral.peripheral_interface.registers()
	drive := &disk.drives[dl]

	if drive.fp == nil {
		ah = 1
		flags += {.CARRY}
	} else {
		al = execute_operation(disk, drive, read, peripheral.address(es, bx), u16(ch) + u16(cl / 64) * 256, u16(cl & 0x3F), u16(dh), al)
		ah = 0
		flags -= {.CARRY}
	}
}

bootstrap :: proc(disk: ^Disk) {
	using reg := peripheral.peripheral_interface.registers()
	drive := &disk.drives[disk.boot_drive]

	if drive.fp == nil {
		log.error("No boot drive!")
		flags += {.CARRY}
		return
	}

	dl = disk.boot_drive
	al = execute_operation(disk, drive, true, BOOTSECTOR_ADDRESS, 0, 1, 0, 1)
	flags -= {.CARRY}
}

open_disk_image :: proc(disk: ^Disk, path: string) -> ^retro.vfs_file_handle {
	using retro

	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)

	fp := disk.vfs.open(cpath, VFS_FILE_ACCESS_READ_WRITE | VFS_FILE_ACCESS_UPDATE_EXISTING, VFS_FILE_ACCESS_HINT_FREQUENT_ACCESS)
	if fp == nil {
		if fp = disk.vfs.open(cpath, VFS_FILE_ACCESS_READ, VFS_FILE_ACCESS_HINT_FREQUENT_ACCESS); fp == nil {
			log.panicf("Could not open disk image file: %s", path)
		}
		log.warnf("Open file as read-only: %s", path)
	}
	return fp
}

mount_disk :: proc(disk: ^Disk, disk_num: byte, path: string) {
	file_ptr := open_disk_image(disk, path)
	file_size := uint(disk.vfs.size(file_ptr))

	using drive: Drive
	fp = file_ptr
	size = file_size
	is_hd = false

	switch size {
	case 512, 163840:
		cylinders = 40
		sectors = 8
		heads = 1
	case 368640:
		cylinders = 40
		sectors = 9
		heads = 2
	case 737280:
		cylinders = 80
		sectors = 9
		heads = 2
	case 1228800:
		cylinders = 80
		sectors = 15
		heads = 2
	case 1474560:
		cylinders = 80
		sectors = 18
		heads = 2
	case:
		sectors = 63
		heads = 16
		cylinders = u16(size / (uint(sectors) * uint(heads) * SECTOR_SIZE))
		is_hd = true
	}

	// Auto select
	num := disk_num
	if num == 0xFF {
		num = is_hd ? (disk.num_hd + 0x80) : disk.num_fd
	}

	if is_hd {
		disk.num_hd += 1
	} else {
		disk.num_fd += 1
	}

	assert(disk.num_fd <= 2)
	assert(disk.drives[num].fp == nil)

	assert((size % SECTOR_SIZE) == 0)
	assert((is_hd && num >= 0x80) || (!is_hd && num < 0x80))

	log.infof("%s image mounted: %s", is_hd ? "HD" : "FD", path)
	log.infof("  Index: 0x%2.X", num)
	log.infof("  CSH: %d, %d, %d", cylinders, sectors, heads)

	disk.drives[num] = drive
}

config :: proc(disk: ^Disk, name, key: string, value: any) -> bool {
	if name != "disk" {
		return true
	}

	switch key {
	case "vfs":
		disk.vfs = value.(^retro.vfs_interface)
	case "mounted":
		status := value.(^byte)
		status^ = (disk.drives[status^].fp != nil) ? 1 : 0
	case "umount":
		num := value.(byte)
		if num >= 0x80 {
			log.warn("Can't unmount harddrive!")
			return false
		}
		if drive := &disk.drives[num]; drive.fp != nil {
			disk.vfs.close(drive.fp)
			drive^ = Drive{}
		} else {
			log.warn("No drive mounted!")
		}
	case "boot":
		disk.boot_drive = value.(byte)
	case "auto":
		mount_disk(disk, 0xFF, value.(string))
	case "A":
		mount_disk(disk, 0, value.(string))
	case "C":
		mount_disk(disk, 0x80, value.(string))
	case:
		return false
	}
	return true
}

io_in :: proc(disk: ^Disk, port: u16) -> byte {
	switch port {
	case 0xB0:
		return (disk.boot_drive >= 0x80) ? 0 : 0xFF
	case 0xB1:
		idx := peripheral.peripheral_interface.registers().dl
		return (disk.drives[idx].fp != nil) ? 0 : 0xFF
	case:
		panic("unmapped port")
	}
}

io_out :: proc(disk: ^Disk, port: u16, _: byte) {
	if port == 0xB0 {
		bootstrap(disk)
		return
	}

	using reg := peripheral.peripheral_interface.registers()
	drive := &disk.drives[dl]

	switch ah {
	case 0:
		// Reset
		ah = 0
		flags -= {.CARRY}
	case 1:
		// Return status
		ah = drive.status
		flags = drive.error ? (flags + {.CARRY}) : (flags - {.CARRY})
		return
	case 2:
		// Read sector
		execute_and_set(disk, true)
	case 3:
		// Write sector
		execute_and_set(disk, false)
	case 4, 5:
		// Format track
		ah = 0
		flags -= {.CARRY}
	case 8:
		// Drive parameters
		if drive.fp == nil {
			ah = 0xAA
			flags += {.CARRY}
		} else {
			ax = 0
			flags -= {.CARRY}
			ch = byte((drive.cylinders - 1) & 0xFF)
			cl = byte((((drive.cylinders - 1) >> 2) & 0xC0) | (drive.sectors & 0x3F))
			dh = byte(drive.heads - 1)

			if dl < 0x80 {
				bl = 4
				dl = 2
			} else {
				dl = disk.num_hd
			}
		}
	case:
		flags += {.CARRY}
	}

	drive.status = ah
	drive.error = .CARRY in flags

	if drive.is_hd {
		peripheral.peripheral_interface.write(peripheral.address(0x40, 0x74), ah)
	}
}
