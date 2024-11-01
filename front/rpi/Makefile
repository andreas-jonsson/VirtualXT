VXTHOME = ../../lib/vxt
ifeq ($(CIRCLEHOME),)
CIRCLEHOME = ../../../circle
endif

FLAGS_VXT = -DVXT_NO_LIBC -DFRONTEND_VIDEO_RED=2 -DFRONTEND_VIDEO_GREEN=1 -DFRONTEND_VIDEO_BLUE=0 -DFRONTEND_VIDEO_ALPHA=3 -I$(VXTHOME)/include -I../common

CFLAGS := $(FLAGS_VXT)
CPPFLAGS := -fpermissive $(FLAGS_VXT)

OBJS_VXT = $(VXTHOME)/cpu.o \
	$(VXTHOME)/disk.o \
	$(VXTHOME)/dma.o \
	$(VXTHOME)/dummy.o \
	$(VXTHOME)/memory.o \
	$(VXTHOME)/pic.o \
	$(VXTHOME)/pit.o \
	$(VXTHOME)/ppi.o \
	$(VXTHOME)/system.o \
	$(VXTHOME)/uart.o

OBJS = main.o kernel.o $(OBJS_VXT)

LIBS = $(CIRCLEHOME)/lib/usb/libusb.a \
	$(CIRCLEHOME)/lib/input/libinput.a \
	$(CIRCLEHOME)/lib/fs/libfs.a \
	$(CIRCLEHOME)/lib/libcircle.a

include $(CIRCLEHOME)/Rules.mk

-include $(DEPS)
