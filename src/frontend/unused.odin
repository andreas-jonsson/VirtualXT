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

package frontend

import "core:c"
import retro "vxt:frontend/libretro"

@(export)
retro_deinit :: proc "c" () {
}

@(export)
retro_api_version :: proc "c" () -> c.uint {
	return retro.API_VERSION
}

@(export)
retro_set_controller_port_device :: proc "c" (port: c.uint, device: c.uint) {
}

@(export)
retro_set_audio_sample_batch :: proc "c" (cb: retro.audio_sample_batch_t) {
}

@(export)
retro_get_region :: proc "c" () -> c.uint {
	return retro.REGION_NTSC
}

@(export)
retro_load_game_special :: proc "c" (type: c.uint, info: ^retro.game_info, num: c.size_t) -> c.bool {
	return false
}

@(export)
retro_serialize_size :: proc "c" () -> c.size_t {
	return 0
}

@(export)
retro_serialize :: proc "c" (data: rawptr, size: c.size_t) -> c.bool {
	return false
}

@(export)
retro_unserialize :: proc "c" (data: rawptr, size: c.size_t) -> c.bool {
	return false
}

@(export)
retro_get_memory_data :: proc "c" (id: c.uint) -> rawptr {
	return nil
}

@(export)
retro_get_memory_size :: proc "c" (id: c.uint) -> c.size_t {
	return 0
}

@(export)
retro_cheat_reset :: proc "c" () {
}

@(export)
retro_cheat_set :: proc "c" (index: c.uint, enabled: c.bool, code: cstring) {
}
