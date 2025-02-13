ifeq ($(CIRCLEHOME),)
	CIRCLEHOME=../../../../circle
endif

CFLAGS = -I../../libretro
OBJS = main.o kernel.o emuloop.o core.o

LIBS = $(CIRCLEHOME)/lib/libcircle.a \
	$(CIRCLEHOME)/lib/usb/libusb.a \
	$(CIRCLEHOME)/lib/sound/libsound.a \
	$(CIRCLEHOME)/lib/input/libinput.a \
	$(CIRCLEHOME)/lib/fs/libfs.a \
	$(CIRCLEHOME)/addon/fatfs/libfatfs.a \
	$(CIRCLEHOME)/addon/SDCard/libsdcard.a

include $(CIRCLEHOME)/Rules.mk

-include $(DEPS)
