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

#include "kernel.h"
#include <circle/startup.h>
#include <circle/memory.h>

#define ODIN_HEAP_SIZE (1024 * 1024 * 10)
extern "C" void odin_startup_runtime(void*,int);

int main(void) {
	void *ptr = CMemorySystem::HeapAllocate(ODIN_HEAP_SIZE, HEAP_DEFAULT_NEW);
	odin_startup_runtime(ptr, ODIN_HEAP_SIZE);

	CKernel Kernel;
	if (!Kernel.Initialize()) {
		halt();
		return EXIT_HALT;
	}
	
	TShutdownMode ShutdownMode = Kernel.Run();
	switch (ShutdownMode) {
		case ShutdownReboot:
			reboot();
			return EXIT_REBOOT;
		case ShutdownHalt:
		default:
			halt();
			return EXIT_HALT;
	}
}
