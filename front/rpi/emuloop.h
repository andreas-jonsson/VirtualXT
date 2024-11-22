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

#include "kernel.h"

#ifndef _EMULOOP_H_
#define _EMULOOP_H_

#include <circle/multicore.h>
#include <circle/memory.h>
#include <circle/types.h>

class CEmuLoop : public CMultiCoreSupport
{
public:
	CEmuLoop(CMemorySystem *mem, vxt_system *s);
	~CEmuLoop(void);

	void Run(unsigned nCore);

	static CSpinLock s_SpinLock;

private:
	vxt_system *m_pSystem;
};

#endif
