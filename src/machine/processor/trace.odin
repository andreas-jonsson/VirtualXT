#+private
#+build !freestanding

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

package processor

import "core:os"
import "core:io"
import "core:log"

@(private="file")
trace: io.Stream

write_cpu_trace :: proc() {
	if #config(VXT_CPU_TRACE, "") == "" {
		return
	}

	if trace.data == nil {
		name := #config(VXT_CPU_TRACE, "cpu.trace")
		fp, err := os.open(name, os.O_CREATE | os.O_WRONLY, 0o644)
		assert(err == nil)
		trace = os.stream_from_handle(fp)
		log.infof("CPU Trace: %s", name)
	}

	_, err := io.write_ptr(trace, &registers.cs, 2)
	assert(err == nil)
	
	_, err = io.write_ptr(trace, &registers.ip, 2)
	assert(err == nil)
}

close_cpu_trace :: proc() {
	io.close(trace)
}
