/*!
 * libretro.h is a simple API that allows for the creation of games and emulators.
 *
 * @file libretro.h
 * @version 1
 * @author libretro
 * @copyright Copyright (C) 2010-2023 The RetroArch team
 *
 * @paragraph LICENSE
 * The following license statement only applies to this libretro API header (libretro.h).
 *
 * Copyright (C) 2010-2023 The RetroArch team
 *
 * Permission is hereby granted, free of charge,
 * to any person obtaining a copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
 * and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
 * INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

package libretro

import "core:c"

API_VERSION :: 1
REGION_NTSC :: 0
REGION_PAL :: 1

ENVIRONMENT_EXPERIMENTAL :: 0x10000
NUM_CORE_OPTION_VALUES_MAX :: 128

ENVIRONMENT_GET_VARIABLE        :: 15
ENVIRONMENT_GET_VARIABLE_UPDATE :: 17
ENVIRONMENT_GET_LOG_INTERFACE 	:: 27
ENVIRONMENT_GET_PERF_INTERFACE 	:: 28
ENVIRONMENT_GET_SAVE_DIRECTORY  :: 31

ENVIRONMENT_GET_VFS_INTERFACE :: 45 | ENVIRONMENT_EXPERIMENTAL

ENVIRONMENT_SET_MESSAGE   				:: 6
ENVIRONMENT_SET_PIXEL_FORMAT 			:: 10
ENVIRONMENT_SET_VARIABLES 				:: 16
ENVIRONMENT_SET_SUPPORT_NO_GAME 		:: 18
ENVIRONMENT_SET_KEYBOARD_CALLBACK 		:: 12
ENVIRONMENT_SET_DISK_CONTROL_INTERFACE 	:: 13
ENVIRONMENT_SET_FRAME_TIME_CALLBACK 	:: 21
ENVIRONMENT_SET_AUDIO_CALLBACK 			:: 22
ENVIRONMENT_SET_CORE_OPTIONS_V2 		:: 67

VFS_FILE_ACCESS_READ 					:: 1 << 0
VFS_FILE_ACCESS_WRITE 					:: 1 << 1
VFS_FILE_ACCESS_READ_WRITE 				:: VFS_FILE_ACCESS_READ | VFS_FILE_ACCESS_WRITE
VFS_FILE_ACCESS_UPDATE_EXISTING 		:: 1 << 2
VFS_FILE_ACCESS_HINT_NONE 				:: 0
VFS_FILE_ACCESS_HINT_FREQUENT_ACCESS 	:: 1 << 0
VFS_SEEK_POSITION_START 				:: 0
VFS_SEEK_POSITION_CURRENT 				:: 1
VFS_SEEK_POSITION_END 					:: 2

environment_t :: #type proc "c" (cmd: c.uint, data: rawptr) -> c.bool
log_printf_t :: #type proc "c" (level: log_level, fmt: cstring, #c_vararg args: ..any)
audio_sample_t :: #type proc "c" (left, right: c.int16_t)
audio_sample_batch_t :: #type proc "c" (data: [^]c.int16_t, frames: c.size_t) -> c.size_t
input_poll_t :: #type proc "c" ()
input_state_t :: #type proc "c" (port, device, index, id: c.uint) -> c.int16_t
keyboard_event_t :: #type proc "c" (down: c.bool, keycode: key, character: c.uint32_t, key_modifiers: c.uint16_t)
video_refresh_t :: #type proc "c" (data: rawptr, width, height: c.uint, pitch: c.size_t)
audio_callback_t :: #type proc "c" ()
audio_set_state_callback_t :: #type proc "c" (enabled: c.bool)
frame_time_callback_t :: #type proc "c" (usec: usec_t)

perf_get_time_usec_t :: #type proc "c" () -> time_t
get_cpu_features_t :: #type proc "c" () -> c.uint64_t
perf_get_counter_t :: #type proc "c" () -> perf_tick_t
perf_register_t :: #type proc "c" (counter: ^perf_counter)
perf_start_t :: #type proc "c" (counter: ^perf_counter)
perf_stop_t :: #type proc "c" (counter: ^perf_counter)
perf_log_t :: #type proc "c" ()

set_eject_state_t :: #type proc "c" (ejected: c.bool) -> c.bool
get_eject_state_t :: #type proc "c" () -> c.bool
get_image_index_t :: #type proc "c" () -> c.uint
set_image_index_t :: #type proc "c" (index: c.uint) -> c.bool
get_num_images_t :: #type proc "c" () -> c.uint
replace_image_index_t :: #type proc "c" (index: c.uint, #by_ptr info: game_info) -> c.bool
add_image_index_t :: #type proc "c" () -> c.bool

vfs_get_path_t :: #type proc "c" (stream: ^vfs_file_handle) -> cstring
vfs_open_t :: #type proc "c" (path: cstring, mode, hints: c.uint) -> ^vfs_file_handle
vfs_close_t :: #type proc "c" (stream: ^vfs_file_handle) -> c.int
vfs_size_t :: #type proc "c" (stream: ^vfs_file_handle) -> c.int64_t
vfs_tell_t :: #type proc "c" (stream: ^vfs_file_handle) -> c.int64_t
vfs_seek_t :: #type proc "c" (stream: ^vfs_file_handle, offset: c.int64_t, seek_position: c.int) -> c.int64_t
vfs_read_t :: #type proc "c" (stream: ^vfs_file_handle, s: rawptr, ln: c.uint64_t) -> c.int64_t
vfs_write_t :: #type proc "c" (stream: ^vfs_file_handle, s: rawptr, ln: c.uint64_t) -> c.int64_t
vfs_flush_t :: #type proc "c" (stream: ^vfs_file_handle) -> c.int
vfs_remove_t :: #type proc "c" (path: cstring) -> c.int
vfs_rename_t :: #type proc "c" (old_path, new_path: cstring) -> c.int

vfs_file_handle :: struct {}

pixel_format :: enum c.int {
	PIXEL_FORMAT_0RGB1555,
	PIXEL_FORMAT_XRGB8888,
	PIXEL_FORMAT_RGB565,
}

log_level :: enum c.int {
	LOG_DEBUG,
	LOG_INFO,
	LOG_WARN,
	LOG_ERROR,
}

log_callback :: struct {
	log: log_printf_t,
}

keyboard_callback :: struct {
	callback: keyboard_event_t,
}

audio_callback :: struct {
	callback: audio_callback_t,
	set_state: audio_set_state_callback_t,
}

perf_callback :: struct {
	get_time_usec: perf_get_time_usec_t,
	get_cpu_features: get_cpu_features_t,
	get_perf_counter: perf_get_counter_t,
	perf_register: perf_register_t,
	perf_start: perf_start_t,
	perf_stop: perf_stop_t,
	perf_log: perf_log_t,
}

frame_time_callback :: struct {
	callback: frame_time_callback_t,
	reference: usec_t,
}

message :: struct {
	msg: cstring,
	frames: c.uint,
}

// VFS API v1
vfs_interface :: struct {
	get_path: vfs_get_path_t,
	open: vfs_open_t,
	close: vfs_close_t,
	size: vfs_size_t,
	tell: vfs_tell_t,
	seek: vfs_seek_t,
	read: vfs_read_t,
	write: vfs_write_t,
	flush: vfs_flush_t,
	remove: vfs_remove_t,
	rename: vfs_rename_t,
}

vfs_interface_info :: struct {
	required_interface_version: c.uint32_t,
	iface: ^vfs_interface,
}

system_info :: struct {
	library_name,
	library_version,
	valid_extensions: cstring,
	need_fullpath,
	block_extract: c.bool,
}

game_info :: struct {
	path: cstring,
	data: rawptr,
	size: c.size_t,
	meta: cstring,
}

game_geometry :: struct {
	base_width,	base_height,
	max_width, max_height: c.uint,
	aspect_ratio: f32,
}

system_timing :: struct {
	fps, sample_rate: f64,
}

system_av_info :: struct {
	geometry: game_geometry,
	timing: system_timing,
}

perf_counter :: struct {
	ident: cstring,
	start, total, call_cnt: perf_tick_t,
	registered: c.bool,
}

variable :: struct {
	key, value: cstring,
}

core_option_value :: struct {
	value, label: cstring,
}

core_option_v2_category :: struct {
	key, desc, info: cstring,
}

core_option_v2_definition :: struct {
	key: cstring,
	desc, desc_categorized: cstring,
	info, info_categorized: cstring,
	category_key: cstring,
	values: [NUM_CORE_OPTION_VALUES_MAX]core_option_value,
	default_value: cstring,
}

core_options_v2 :: struct {
	categories: ^core_option_v2_category,
	definitions: ^core_option_v2_definition,
}

disk_control_callback :: struct {
	set_eject_state: set_eject_state_t,
	get_eject_state: get_eject_state_t,
	get_image_index: get_image_index_t,
	set_image_index: set_image_index_t,
	get_num_images: get_num_images_t,
	replace_image_index: replace_image_index_t,
	add_image_index: add_image_index_t,
}

usec_t :: c.int64_t
time_t :: c.int64_t
perf_tick_t :: c.uint64_t

key :: enum c.int {
	K_UNKNOWN        = 0,
	K_BACKSPACE      = 8,
	K_TAB            = 9,
	K_CLEAR          = 12,
	K_RETURN         = 13,
	K_PAUSE          = 19,
	K_ESCAPE         = 27,
	K_SPACE          = 32,
	K_EXCLAIM        = 33,
	K_QUOTEDBL       = 34,
	K_HASH           = 35,
	K_DOLLAR         = 36,
	K_AMPERSAND      = 38,
	K_QUOTE          = 39,
	K_LEFTPAREN      = 40,
	K_RIGHTPAREN     = 41,
	K_ASTERISK       = 42,
	K_PLUS           = 43,
	K_COMMA          = 44,
	K_MINUS          = 45,
	K_PERIOD         = 46,
	K_SLASH          = 47,
	K_0              = 48,
	K_1              = 49,
	K_2              = 50,
	K_3              = 51,
	K_4              = 52,
	K_5              = 53,
	K_6              = 54,
	K_7              = 55,
	K_8              = 56,
	K_9              = 57,
	K_COLON          = 58,
	K_SEMICOLON      = 59,
	K_LESS           = 60,
	K_EQUALS         = 61,
	K_GREATER        = 62,
	K_QUESTION       = 63,
	K_AT             = 64,
	K_LEFTBRACKET    = 91,
	K_BACKSLASH      = 92,
	K_RIGHTBRACKET   = 93,
	K_CARET          = 94,
	K_UNDERSCORE     = 95,
	K_BACKQUOTE      = 96,
	K_a              = 97,
	K_b              = 98,
	K_c              = 99,
	K_d              = 100,
	K_e              = 101,
	K_f              = 102,
	K_g              = 103,
	K_h              = 104,
	K_i              = 105,
	K_j              = 106,
	K_k              = 107,
	K_l              = 108,
	K_m              = 109,
	K_n              = 110,
	K_o              = 111,
	K_p              = 112,
	K_q              = 113,
	K_r              = 114,
	K_s              = 115,
	K_t              = 116,
	K_u              = 117,
	K_v              = 118,
	K_w              = 119,
	K_x              = 120,
	K_y              = 121,
	K_z              = 122,
	K_LEFTBRACE      = 123,
	K_BAR            = 124,
	K_RIGHTBRACE     = 125,
	K_TILDE          = 126,
	K_DELETE         = 127,

	K_KP0            = 256,
	K_KP1            = 257,
	K_KP2            = 258,
	K_KP3            = 259,
	K_KP4            = 260,
	K_KP5            = 261,
	K_KP6            = 262,
	K_KP7            = 263,
	K_KP8            = 264,
	K_KP9            = 265,
	K_KP_PERIOD      = 266,
	K_KP_DIVIDE      = 267,
	K_KP_MULTIPLY    = 268,
	K_KP_MINUS       = 269,
	K_KP_PLUS        = 270,
	K_KP_ENTER       = 271,
	K_KP_EQUALS      = 272,

	K_UP             = 273,
	K_DOWN           = 274,
	K_RIGHT          = 275,
	K_LEFT           = 276,
	K_INSERT         = 277,
	K_HOME           = 278,
	K_END            = 279,
	K_PAGEUP         = 280,
	K_PAGEDOWN       = 281,

	K_F1             = 282,
	K_F2             = 283,
	K_F3             = 284,
	K_F4             = 285,
	K_F5             = 286,
	K_F6             = 287,
	K_F7             = 288,
	K_F8             = 289,
	K_F9             = 290,
	K_F10            = 291,
	K_F11            = 292,
	K_F12            = 293,
	K_F13            = 294,
	K_F14            = 295,
	K_F15            = 296,

	K_NUMLOCK        = 300,
	K_CAPSLOCK       = 301,
	K_SCROLLOCK      = 302,
	K_RSHIFT         = 303,
	K_LSHIFT         = 304,
	K_RCTRL          = 305,
	K_LCTRL          = 306,
	K_RALT           = 307,
	K_LALT           = 308,
	K_RMETA          = 309,
	K_LMETA          = 310,
	K_LSUPER         = 311,
	K_RSUPER         = 312,
	K_MODE           = 313,
	K_COMPOSE        = 314,

	K_HELP           = 315,
	K_PRINT          = 316,
	K_SYSREQ         = 317,
	K_BREAK          = 318,
	K_MENU           = 319,
	K_POWER          = 320,
	K_EURO           = 321,
	K_UNDO           = 322,
	K_OEM_102        = 323,

	K_BROWSER_BACK      = 324,
	K_BROWSER_FORWARD   = 325,
	K_BROWSER_REFRESH   = 326,
	K_BROWSER_STOP      = 327,
	K_BROWSER_SEARCH    = 328,
	K_BROWSER_FAVORITES = 329,
	K_BROWSER_HOME      = 330,
	K_VOLUME_MUTE       = 331,
	K_VOLUME_DOWN       = 332,
	K_VOLUME_UP         = 333,
	K_MEDIA_NEXT        = 334,
	K_MEDIA_PREV        = 335,
	K_MEDIA_STOP        = 336,
	K_MEDIA_PLAY_PAUSE  = 337,
	K_LAUNCH_MAIL       = 338,
	K_LAUNCH_MEDIA      = 339,
	K_LAUNCH_APP1       = 340,
	K_LAUNCH_APP2       = 341,
}
