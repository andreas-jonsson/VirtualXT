VXTHOME = ../../lib/vxt
ifeq ($(CIRCLEHOME),)
CIRCLEHOME = ../../../circle
endif

LIBCHOME = $(VXTHOME)/../scanf

CFLAGS = -DVXT_NO_LIBC -DFRONTEND_VIDEO_RED=2 -DFRONTEND_VIDEO_GREEN=1 -DFRONTEND_VIDEO_BLUE=0 -DFRONTEND_VIDEO_ALPHA=3 -I$(VXTHOME)/include -I../common

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

EXTRACLEAN = $(VXTHOME)/*.o $(VXTHOME)/*.d

OBJS_LIBC = $(LIBCHOME)/scanf.o
EXTRACLEAN += $(LIBCHOME)/*.o $(LIBCHOME)/*.d

OBJS = main.o kernel.o ethernet.o cga.o mouse.o $(OBJS_VXT) $(OBJS_LIBC)

LIBS = $(CIRCLEHOME)/lib/usb/libusb.a \
	$(CIRCLEHOME)/lib/sound/libsound.a \
	$(CIRCLEHOME)/lib/input/libinput.a \
	$(CIRCLEHOME)/lib/fs/libfs.a \
	$(CIRCLEHOME)/lib/libcircle.a \
	$(CIRCLEHOME)/addon/fatfs/libfatfs.a \
	$(CIRCLEHOME)/addon/SDCard/libsdcard.a

include $(CIRCLEHOME)/Rules.mk

-include $(DEPS)
