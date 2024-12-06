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

#ifndef _KEYMAP_H_
#define _KEYMAP_H_

#define NUM_MODIFIERS 9
enum vxtu_scancode modifierToXT[NUM_MODIFIERS] = {
	VXTU_SCAN_LCONTROL,		// ModifierKeyLeftCtrl
	VXTU_SCAN_LSHIFT,		// ModifierKeyLeftShift
	VXTU_SCAN_ALT,			// ModifierKeyAlt
	VXTU_SCAN_INVALID,		// ModifierKeyLeftWin
	VXTU_SCAN_LCONTROL,		// ModifierKeyRightCtrl
	VXTU_SCAN_RSHIFT,		// ModifierKeyRightShift
	VXTU_SCAN_ALT,			// ModifierKeyAltGr
	VXTU_SCAN_INVALID,		// ModifierKeyRightWin
	VXTU_SCAN_INVALID		// ModifierKeyUnknown
};

enum vxtu_scancode usbToXT[256] = {
	VXTU_SCAN_INVALID,		// USB 0	(null)
	VXTU_SCAN_INVALID,		// USB 1	(null)
	VXTU_SCAN_INVALID,		// USB 2	(null)
	VXTU_SCAN_INVALID,		// USB 3	(null)
	VXTU_SCAN_A,			// USB 4	KeyA
	VXTU_SCAN_B,			// USB 5	KeyB
	VXTU_SCAN_C,			// USB 6	KeyC
	VXTU_SCAN_D,			// USB 7	KeyD
	VXTU_SCAN_E,			// USB 8	KeyE
	VXTU_SCAN_F,			// USB 9	KeyF
	VXTU_SCAN_G,			// USB a	KeyG
	VXTU_SCAN_H,			// USB b	KeyH
	VXTU_SCAN_I,			// USB c	KeyI
	VXTU_SCAN_J,			// USB d	KeyJ
	VXTU_SCAN_K,			// USB e	KeyK
	VXTU_SCAN_L,			// USB f	KeyL
	VXTU_SCAN_M,			// USB 10	KeyM
	VXTU_SCAN_N,			// USB 11	KeyN
	VXTU_SCAN_O,			// USB 12	KeyO
	VXTU_SCAN_P,			// USB 13	KeyP
	VXTU_SCAN_Q,			// USB 14	KeyQ
	VXTU_SCAN_R,			// USB 15	KeyR
	VXTU_SCAN_S,			// USB 16	KeyS
	VXTU_SCAN_T,			// USB 17	KeyT
	VXTU_SCAN_U,			// USB 18	KeyU
	VXTU_SCAN_V,			// USB 19	KeyV
	VXTU_SCAN_W,			// USB 1a	KeyW
	VXTU_SCAN_X,			// USB 1b	KeyX
	VXTU_SCAN_Y,			// USB 1c	KeyY
	VXTU_SCAN_Z,			// USB 1d	KeyZ
	VXTU_SCAN_1,			// USB 1e	Digit1
	VXTU_SCAN_2,			// USB 1f	Digit2
	VXTU_SCAN_3,			// USB 20	Digit3
	VXTU_SCAN_4,			// USB 21	Digit4
	VXTU_SCAN_5,			// USB 22	Digit5
	VXTU_SCAN_6,			// USB 23	Digit6
	VXTU_SCAN_7,			// USB 24	Digit7
	VXTU_SCAN_8,			// USB 25	Digit8
	VXTU_SCAN_9,			// USB 26	Digit9
	VXTU_SCAN_0,			// USB 27	Digit0
	VXTU_SCAN_ENTER,		// USB 28	Enter
	VXTU_SCAN_ESCAPE,		// USB 29	Escape
	VXTU_SCAN_BACKSPACE,	// USB 2a	Backspace
	VXTU_SCAN_TAB,			// USB 2b	Tab
	VXTU_SCAN_SPACE,		// USB 2c	Space
	VXTU_SCAN_MINUS,		// USB 2d	Minus
	VXTU_SCAN_EQUAL,		// USB 2e	Equal
	VXTU_SCAN_LBRACKET,		// USB 2f	BracketLeft
	VXTU_SCAN_RBRACKET,		// USB 30	BracketRight
	VXTU_SCAN_BACKSLASH,	// USB 31	Backslash
	VXTU_SCAN_INVALID,		// USB 32	(none)
	VXTU_SCAN_SEMICOLON,	// USB 33	Semicolon
	VXTU_SCAN_QUOTE,		// USB 34	Quote
	VXTU_SCAN_BACKQUOTE,	// USB 35	Backquote
	VXTU_SCAN_COMMA,		// USB 36	Comma
	VXTU_SCAN_PERIOD,		// USB 37	Period
	VXTU_SCAN_SLASH,		// USB 38	Slash
	VXTU_SCAN_CAPSLOCK,		// USB 39	CapsLock
	VXTU_SCAN_F1,			// USB 3a	F1
	VXTU_SCAN_F2,			// USB 3b	F2
	VXTU_SCAN_F3,			// USB 3c	F3
	VXTU_SCAN_F4,			// USB 3d	F4
	VXTU_SCAN_F5,			// USB 3e	F5
	VXTU_SCAN_F6,			// USB 3f	F6
	VXTU_SCAN_F7,			// USB 40	F7
	VXTU_SCAN_F8,			// USB 41	F8
	VXTU_SCAN_F9,			// USB 42	F9
	VXTU_SCAN_F10,			// USB 43	F10
	VXTU_SCAN_INVALID,		// USB 44	F11
	VXTU_SCAN_INVALID,		// USB 45	F12
	VXTU_SCAN_PRINT,		// USB 46	PrintScreen
	VXTU_SCAN_SCRLOCK,		// USB 47	ScrollLock
	VXTU_SCAN_INVALID,		// USB 48	Pause
	VXTU_SCAN_INVALID,		// USB 49	Insert
	VXTU_SCAN_INVALID,		// USB 4a	Home
	VXTU_SCAN_INVALID,		// USB 4b	PageUp
	VXTU_SCAN_INVALID,		// USB 4c	Delete
	VXTU_SCAN_INVALID,		// USB 4d	End
	VXTU_SCAN_INVALID,		// USB 4e	PageDown
	VXTU_SCAN_KP_RIGHT,		// USB 4f	ArrowRight
	VXTU_SCAN_KP_LEFT,		// USB 50	ArrowLeft
	VXTU_SCAN_KP_DOWN,		// USB 51	ArrowDown
	VXTU_SCAN_KP_UP,		// USB 52	ArrowUp
	VXTU_SCAN_NUMLOCK,		// USB 53	NumLock
	VXTU_SCAN_INVALID,		// USB 54	NumpadDivide
	VXTU_SCAN_PRINT,		// USB 55	NumpadMultiply
	VXTU_SCAN_KP_MINUS,		// USB 56	NumpadSubtract
	VXTU_SCAN_KP_PLUS,		// USB 57	NumpadAdd
	VXTU_SCAN_INVALID,		// USB 58	NumpadEnter
	VXTU_SCAN_KP_END,		// USB 59	Numpad1
	VXTU_SCAN_KP_DOWN,		// USB 5a	Numpad2
	VXTU_SCAN_KP_PAGEDOWN,	// USB 5b	Numpad3
	VXTU_SCAN_KP_LEFT,		// USB 5c	Numpad4
	VXTU_SCAN_KP_5,			// USB 5d	Numpad5
	VXTU_SCAN_KP_RIGHT,		// USB 5e	Numpad6
	VXTU_SCAN_KP_HOME,		// USB 5f	Numpad7
	VXTU_SCAN_KP_UP,		// USB 60	Numpad8
	VXTU_SCAN_KP_PAGEUP,	// USB 61	Numpad9
	VXTU_SCAN_KP_INSERT,	// USB 62	Numpad0
	VXTU_SCAN_KP_DELETE,	// USB 63	NumpadDecimal
	VXTU_SCAN_INVALID,		// USB 64	IntlBackslash
	VXTU_SCAN_INVALID,		// USB 65	ContextMenu
	VXTU_SCAN_INVALID,		// USB 66	Power
	VXTU_SCAN_INVALID,		// USB 67	NumpadEqual
	VXTU_SCAN_INVALID,		// USB 68	F13
	VXTU_SCAN_INVALID,		// USB 69	F14
	VXTU_SCAN_INVALID,		// USB 6a	F15
	VXTU_SCAN_INVALID,		// USB 6b	F16
	VXTU_SCAN_INVALID,		// USB 6c	F17
	VXTU_SCAN_INVALID,		// USB 6d	F18
	VXTU_SCAN_INVALID,		// USB 6e	F19
	VXTU_SCAN_INVALID,		// USB 6f	F20
	VXTU_SCAN_INVALID,		// USB 70	F21
	VXTU_SCAN_INVALID,		// USB 71	F22
	VXTU_SCAN_INVALID,		// USB 72	F23
	VXTU_SCAN_INVALID,		// USB 73	F24
	VXTU_SCAN_INVALID,		// USB 74	Open
	VXTU_SCAN_INVALID,		// USB 75	Help
	VXTU_SCAN_INVALID,		// USB 76	(null)
	VXTU_SCAN_INVALID,		// USB 77	Select
	VXTU_SCAN_INVALID,		// USB 78	(none)
	VXTU_SCAN_INVALID,		// USB 79	Again
	VXTU_SCAN_INVALID,		// USB 7a	Undo
	VXTU_SCAN_INVALID,		// USB 7b	Cut
	VXTU_SCAN_INVALID,		// USB 7c	Copy
	VXTU_SCAN_INVALID,		// USB 7d	Paste
	VXTU_SCAN_INVALID,		// USB 7e	Find
	VXTU_SCAN_INVALID,		// USB 7f	VolumeMute
	VXTU_SCAN_INVALID,		// USB 80	VolumeUp
	VXTU_SCAN_INVALID,		// USB 81	VolumeDown
	VXTU_SCAN_INVALID,		// USB 82	(none)
	VXTU_SCAN_INVALID,		// USB 83	(none)
	VXTU_SCAN_INVALID,		// USB 84	(none)
	VXTU_SCAN_INVALID,		// USB 85	NumpadComma
	VXTU_SCAN_INVALID,		// USB 86	(none)
	VXTU_SCAN_INVALID,		// USB 87	IntlRo
	VXTU_SCAN_INVALID,		// USB 88	KanaMode
	VXTU_SCAN_INVALID,		// USB 89	IntlYen
	VXTU_SCAN_INVALID,		// USB 8a	Convert
	VXTU_SCAN_INVALID,		// USB 8b	NonConvert
	VXTU_SCAN_INVALID,		// USB 8c	(none)
	VXTU_SCAN_INVALID,		// USB 8d	(none)
	VXTU_SCAN_INVALID,		// USB 8e	(none)
	VXTU_SCAN_INVALID,		// USB 8f	(none)
	VXTU_SCAN_INVALID,		// USB 90	Lang1
	VXTU_SCAN_INVALID,		// USB 91	Lang2
	VXTU_SCAN_INVALID,		// USB 92	Lang3
	VXTU_SCAN_INVALID,		// USB 93	Lang4
	VXTU_SCAN_INVALID,		// USB 94	Lang5
	VXTU_SCAN_INVALID,		// USB 95	(none)
	VXTU_SCAN_INVALID,		// USB 96	(none)
	VXTU_SCAN_INVALID,		// USB 97	(none)
	VXTU_SCAN_INVALID,		// USB 98	(none)
	VXTU_SCAN_INVALID,		// USB 99	(none)
	VXTU_SCAN_INVALID,		// USB 9a	(none)
	VXTU_SCAN_INVALID,		// USB 9b	Abort
	VXTU_SCAN_INVALID,		// USB 9c	(none)
	VXTU_SCAN_INVALID,		// USB 9d	(none)
	VXTU_SCAN_INVALID,		// USB 9e	(none)
	VXTU_SCAN_INVALID,		// USB 9f	(none)
	VXTU_SCAN_INVALID,		// USB a0	(none)
	VXTU_SCAN_INVALID,		// USB a1	(none)
	VXTU_SCAN_INVALID,		// USB a2	(none)
	VXTU_SCAN_INVALID,		// USB a3	Props
	VXTU_SCAN_INVALID,		// USB a4	(none)
	VXTU_SCAN_INVALID,		// USB a5	(none)
	VXTU_SCAN_INVALID,		// USB a6	(none)
	VXTU_SCAN_INVALID,		// USB a7	(none)
	VXTU_SCAN_INVALID,		// USB a8	(none)
	VXTU_SCAN_INVALID,		// USB a9	(none)
	VXTU_SCAN_INVALID,		// USB aa	(none)
	VXTU_SCAN_INVALID,		// USB ab	(none)
	VXTU_SCAN_INVALID,		// USB ac	(none)
	VXTU_SCAN_INVALID,		// USB ad	(none)
	VXTU_SCAN_INVALID,		// USB ae	(none)
	VXTU_SCAN_INVALID,		// USB af	(none)
	VXTU_SCAN_INVALID,		// USB b0	(none)
	VXTU_SCAN_INVALID,		// USB b1	(none)
	VXTU_SCAN_INVALID,		// USB b2	(none)
	VXTU_SCAN_INVALID,		// USB b3	(none)
	VXTU_SCAN_INVALID,		// USB b4	(none)
	VXTU_SCAN_INVALID,		// USB b5	(none)
	VXTU_SCAN_INVALID,		// USB b6	NumpadParenLeft
	VXTU_SCAN_INVALID,		// USB b7	NumpadParenRight
	VXTU_SCAN_INVALID,		// USB b8	(none)
	VXTU_SCAN_INVALID,		// USB b9	(none)
	VXTU_SCAN_INVALID,		// USB ba	(none)
	VXTU_SCAN_INVALID,		// USB bb	NumpadBackspace
	VXTU_SCAN_INVALID,		// USB bc	(none)
	VXTU_SCAN_INVALID,		// USB bd	(none)
	VXTU_SCAN_INVALID,		// USB be	(none)
	VXTU_SCAN_INVALID,		// USB bf	(none)
	VXTU_SCAN_INVALID,		// USB c0	(none)
	VXTU_SCAN_INVALID,		// USB c1	(none)
	VXTU_SCAN_INVALID,		// USB c2	(none)
	VXTU_SCAN_INVALID,		// USB c3	(none)
	VXTU_SCAN_INVALID,		// USB c4	(none)
	VXTU_SCAN_INVALID,		// USB c5	(none)
	VXTU_SCAN_INVALID,		// USB c6	(none)
	VXTU_SCAN_INVALID,		// USB c7	(none)
	VXTU_SCAN_INVALID,		// USB c8	(none)
	VXTU_SCAN_INVALID,		// USB c9	(none)
	VXTU_SCAN_INVALID,		// USB ca	(none)
	VXTU_SCAN_INVALID,		// USB cb	(none)
	VXTU_SCAN_INVALID,		// USB cc	(none)
	VXTU_SCAN_INVALID,		// USB cd	(none)
	VXTU_SCAN_INVALID,		// USB ce	(none)
	VXTU_SCAN_INVALID,		// USB cf	(none)
	VXTU_SCAN_INVALID,		// USB d0	NumpadMemoryStore
	VXTU_SCAN_INVALID,		// USB d1	NumpadMemoryRecall
	VXTU_SCAN_INVALID,		// USB d2	NumpadMemoryClear
	VXTU_SCAN_INVALID,		// USB d3	NumpadMemoryAdd
	VXTU_SCAN_INVALID,		// USB d4	NumpadMemorySubtract
	VXTU_SCAN_INVALID,		// USB d5	(none)
	VXTU_SCAN_INVALID,		// USB d6	(none)
	VXTU_SCAN_INVALID,		// USB d7	(null)
	VXTU_SCAN_INVALID,		// USB d8	NumpadClear
	VXTU_SCAN_INVALID,		// USB d9	NumpadClearEntry
	VXTU_SCAN_INVALID,		// USB da	(none)
	VXTU_SCAN_INVALID,		// USB db	(none)
	VXTU_SCAN_INVALID,		// USB dc	(none)
	VXTU_SCAN_INVALID,		// USB dd	(none)
	VXTU_SCAN_INVALID,		// USB de	(none)
	VXTU_SCAN_INVALID,		// USB df	(none)
	VXTU_SCAN_LCONTROL,		// USB e0	ControlLeft
	VXTU_SCAN_LSHIFT,		// USB e1	ShiftLeft
	VXTU_SCAN_ALT,			// USB e2	AltLeft
	VXTU_SCAN_INVALID,		// USB e3	OSLeft
	VXTU_SCAN_LCONTROL,		// USB e4	ControlRight
	VXTU_SCAN_RSHIFT,		// USB e5	ShiftRight
	VXTU_SCAN_ALT,			// USB e6	AltRight
	VXTU_SCAN_INVALID,		// USB e7	OSRight
	VXTU_SCAN_INVALID,		// USB e8	(none)
	VXTU_SCAN_INVALID,		// USB e9	(none)
	VXTU_SCAN_INVALID,		// USB ea	(none)
	VXTU_SCAN_INVALID,		// USB eb	(none)
	VXTU_SCAN_INVALID,		// USB ec	(none)
	VXTU_SCAN_INVALID,		// USB ed	(none)
	VXTU_SCAN_INVALID,		// USB ee	(none)
	VXTU_SCAN_INVALID,		// USB ef	(none)
	VXTU_SCAN_INVALID,		// USB f0	(none)
	VXTU_SCAN_INVALID,		// USB f1	(none)
	VXTU_SCAN_INVALID,		// USB f2	(none)
	VXTU_SCAN_INVALID,		// USB f3	(none)
	VXTU_SCAN_INVALID,		// USB f4	(none)
	VXTU_SCAN_INVALID,		// USB f5	(none)
	VXTU_SCAN_INVALID,		// USB f6	(none)
	VXTU_SCAN_INVALID,		// USB f7	(none)
	VXTU_SCAN_INVALID,		// USB f8	(none)
	VXTU_SCAN_INVALID,		// USB f9	(none)
	VXTU_SCAN_INVALID,		// USB fa	(none)
	VXTU_SCAN_INVALID,		// USB fb	(none)
	VXTU_SCAN_INVALID,		// USB fc	(none)
	VXTU_SCAN_INVALID,		// USB fd	(none)
	VXTU_SCAN_INVALID,		// USB fe	(none)
	VXTU_SCAN_INVALID,		// USB ff	(none)
};

#endif
