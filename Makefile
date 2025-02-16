LIB_NAME=virtualxt_libretro
LIB_EXT=so
BUILD_MODE=shared

LIB_NAME_PARAM=-out:$(LIB_NAME)
ifeq ($(OS),Windows_NT)
	LIB_EXT=dll
	BUILD_MODE=dll
	LIB_NAME_PARAM=-out:$(LIB_NAME).$(LIB_EXT)
else
	ifeq ($(UNAME_S),Darwin)
		LIB_EXT=dylib
	endif
endif

TARGET_PARAM=
ifneq ($(ODIN_TARGET),)
	TARGET_PARAM=-target:$(ODIN_TARGET)
endif

CPU_TRACE_PARAM=
ifneq ($(VXT_CPU_TRACE),)
	CPU_TRACE_PARAM=-define:VXT_CPU_TRACE=$(VXT_CPU_TRACE)
endif

COLLECTIONS= \
	-collection:vxt=src \
	-collection:modules=src/modules \
	-collection:bios=bios \
	-collection:boot=boot

TEST_DATA= \
	src/tests/opcodes.odin \
	src/tests/testdata/8088.json \
	src/tests/testdata/*.json \
	src/tests/testdata/*.json.gz

ODIN_VET?=-vet-semicolon -vet-shadowing -vet-style -vet-tabs -vet-unused
ODIN_BUILD=odin build src/frontend $(ODIN_VET) $(CPU_TRACE_PARAM) $(COLLECTIONS)

all: release

gdbstub:
	$(MAKE) -C src/modules/gdb

debug: gdbstub
	$(ODIN_BUILD) $(LIB_NAME_PARAM) -build-mode:$(BUILD_MODE) -define:VXT_GDBSTUB=true -debug $(ODIN_FLAGS)

release:
	$(ODIN_BUILD) $(LIB_NAME_PARAM) -build-mode:$(BUILD_MODE) -o:speed $(ODIN_FLAGS)

rasberrypi:
	$(ODIN_BUILD) -out:tools/circle/kernel/core.o -build-mode:object -target:freestanding_arm64 -define:VXT_EXTERNAL_HEAP=true -o:speed $(ODIN_FLAGS)
	$(MAKE) -C tools/circle/kernel

object:
	$(ODIN_BUILD) -out:$(LIB_NAME).o -build-mode:object $(TARGET_PARAM) -o:speed $(ODIN_FLAGS)

wasm:
	$(ODIN_BUILD) -out:$(LIB_NAME).wasm -build-mode:shared -target:freestanding_wasm32 -o:speed $(ODIN_FLAGS)

run: release
	retroarch -v -L $(LIB_NAME).$(LIB_EXT)

testdata:
	(cd src/tests/testdata && ./download.py)

.PHONY: tests
tests:
	odin test src/tests -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_SHORT_LOGS=true -define:ODIN_TEST_LOG_LEVEL=error -o:speed $(ODIN_VET) $(COLLECTIONS)

clean:
	rm -f *.o *.so *.dll *.dylib *.wasm
	rm -f tests $(TEST_DATA)
	$(MAKE) -C src/modules/gdb clean
	-$(MAKE) -C tools/circle/kernel clean
