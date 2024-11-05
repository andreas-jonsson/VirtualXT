VXTHOME = ../../lib/vxt
ifeq ($(CIRCLEHOME),)
CIRCLEHOME = ../../../circle
endif

FLAGS_VXT = -DVXT_NO_LIBC -I$(VXTHOME)/include -I../common

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

OBJS = main.o kernel.o cga.o $(OBJS_VXT)

LIBS = $(CIRCLEHOME)/lib/usb/libusb.a \
	$(CIRCLEHOME)/lib/input/libinput.a \
	$(CIRCLEHOME)/lib/fs/libfs.a \
	$(CIRCLEHOME)/lib/libcircle.a \
	$(CIRCLEHOME)/addon/fatfs/libfatfs.a \
	$(CIRCLEHOME)/addon/SDCard/libsdcard.a

include $(CIRCLEHOME)/Rules.mk

-include $(DEPS)
