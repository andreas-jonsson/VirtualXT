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

#include "emuloop.h"

#define SYSTEM_STEPS 1
#define GET_TICKS ( CTimer::GetClockTicks64() * (vxt_system_frequency(m_pSystem) / 1000000) )

#ifndef ARM_ALLOW_MULTI_CORE
	#error You need to enable multicore support!
#endif

CSpinLock CEmuLoop::s_SpinLock(TASK_LEVEL);

CEmuLoop::CEmuLoop(CMemorySystem *mem, vxt_system *s)
:	CMultiCoreSupport(mem),
	m_pSystem(s)
{
}

CEmuLoop::~CEmuLoop(void) {
}

void CEmuLoop::Run(unsigned nCore) {
	if (nCore != 1)
		return;

	VXT_LOG("Emulation loop started!");

	assert(CLOCKHZ == 1000000);
	u64 virtual_ticks = GET_TICKS;

	while (true) {
		u64	cpu_ticks = GET_TICKS;
		
		if (virtual_ticks < cpu_ticks) {
			s_SpinLock.Acquire();
			struct vxt_step step = vxt_system_step(m_pSystem, SYSTEM_STEPS);
			s_SpinLock.Release();

			if (step.err != VXT_NO_ERROR)
				VXT_LOG(vxt_error_str(step.err));
			virtual_ticks += step.cycles;
		}
	}

	VXT_LOG("Emulation loop ended!");	
}
