STATIC_LINKING := 0
AR             := ar
ODIN_VERSION   := dev-2025-02

ifneq ($(V),1)
   Q := @
endif

ifeq ($(platform),)
   platform = unix
   ifeq ($(shell uname -s),)
      platform = win
   else ifneq ($(findstring MINGW,$(shell uname -s)),)
      platform = win
   else ifneq ($(findstring Darwin,$(shell uname -s)),)
      platform = osx
   else ifneq ($(findstring win,$(shell uname -s)),)
      platform = win
   endif
endif

# system platform
system_platform = unix
ifeq ($(shell uname -a),)
	EXE_EXT = .exe
	system_platform = win
else ifneq ($(findstring Darwin,$(shell uname -a)),)
	system_platform = osx
	arch = intel
   ifeq ($(shell uname -p),arm)
      arch = arm
   endif
else ifneq ($(findstring MINGW,$(shell uname -a)),)
	system_platform = win
endif

CORE_DIR += ../../../
TARGET_NAME := virtualxt
ODIN_TARGET =

ifeq ($(STATIC_LINKING), 1)
   EXT := a
endif

ifneq (,$(findstring unix,$(platform)))
   EXT ?= so
   TARGET := $(TARGET_NAME)_libretro.$(EXT)
   fpic := -fPIC
   SHARED := -shared -Wl,--no-undefined
else ifeq ($(platform), linux-portable)
   TARGET := $(TARGET_NAME)_libretro.$(EXT)
   fpic := -fPIC -nostdlib
   SHARED := -shared
else ifneq (,$(findstring android,$(platform)))
   TARGET := $(TARGET_NAME)_libretro_android.so
   fpic := -fPIC
   SHARED := -shared -Wl,--no-undefined
   TARGET_TRIPLE := unknown

   ifeq ($(platform), android-arm)
      TARGET_TRIPLE = armv7a-linux-androideabi
      ODIN_TARGET = freestanding_arm32
   else ifeq ($(platform), android-arm64)
      TARGET_TRIPLE = aarch64-linux-android
      ODIN_TARGET = freestanding_arm64
   else ifeq ($(platform), android-x86)
      TARGET_TRIPLE = i686-linux-android
   else ifeq ($(platform), android-x86_64)
      TARGET_TRIPLE = x86_64-linux-android
   endif

   CC = $(ANDROID_NDK_LLVM)/bin/$(TARGET_TRIPLE)21-clang
   AR = $(ANDROID_NDK_LLVM)/bin/llvm-ar

else ifneq (,$(findstring osx,$(platform)))
   TARGET := $(TARGET_NAME)_libretro.dylib
   fpic := -fPIC
   SHARED := -dynamiclib

   ifeq ($(CROSS_COMPILE),1)
		TARGET_RULE   = -target $(LIBRETRO_APPLE_PLATFORM) -isysroot $(LIBRETRO_APPLE_ISYSROOT)
		CFLAGS       += $(TARGET_RULE)
		LDFLAGS      += $(TARGET_RULE)
   endif
else ifneq (,$(findstring ios,$(platform)))
   EXT ?= dylib
   TARGET := $(TARGET_NAME)_libretro_ios.$(EXT)
   fpic := -fPIC
   SHARED := -dynamiclib
   DEFINES := -DIOS
   MIN_VERSION := -miphoneos-version-min=5.0

   ifeq ($(platform),$(filter $(platform),ios9 ios-arm64))
      MIN_VERSION = -miphoneos-version-min=8.0
   endif
   ifeq ($(IOSSDK),)
      IOSSDK := $(shell xcodebuild -version -sdk iphoneos Path)
   endif

   ifeq ($(platform),ios-arm64)
      SHARED += -arch arm64 $(MIN_VERSION) -isysroot $(IOSSDK)
      CC = cc -arch arm64 $(MIN_VERSION) -isysroot $(IOSSDK)
      ODIN_TARGET = freestanding_arm64
   else
      SHARED += -arch armv7 $(MIN_VERSION) -isysroot $(IOSSDK)
      CC = cc -arch armv7 $(MIN_VERSION) -isysroot $(IOSSDK)
      ODIN_TARGET = freestanding_arm32
   endif
else ifneq (,$(findstring tvos,$(platform)))
	EXT ?= dylib
   TARGET := $(TARGET_NAME)_libretro_tvos.$(EXT)
   fpic := -fPIC
   SHARED := -dynamiclib
   DEFINES := -DIOS -DTVOS
   MIN_VERSION := -mappletvos-version-min=9.0

   ifeq ($(TVOSSDK),)
      TVOSSDK := $(shell xcodebuild -version -sdk appletvos Path)
   endif

   SHARED += -arch arm64 $(MIN_VERSION) -isysroot $(TVOSSDK)
   CC = cc -arch arm64 $(MIN_VERSION) -isysroot $(TVOSSDK)
   ODIN_TARGET = freestanding_arm64
else ifeq ($(platform), emscripten)
   TARGET := $(TARGET_NAME)_libretro_emscripten.bc
   fpic := -fPIC
   SHARED := -shared -Wl,--no-undefined
   STATIC_LINKING=1
   AR = emar
else
   TARGET := $(TARGET_NAME)_libretro.dll
   SHARED := -shared -static-libgcc -s -Wl,--no-undefined
   ODIN_TARGET = windows_amd64
endif

ifeq ($(DEBUG), 1)
   CFLAGS += -O0 -g
else
   CFLAGS += -O3 -DNDEBUG
endif

OBJECTS = $(TARGET_NAME)_libretro.o

all: $(TARGET)

setup:
	curl -L -o odin.zip https://github.com/odin-lang/Odin/releases/download/$(ODIN_VERSION)/odin-linux-amd64-$(ODIN_VERSION).zip && unzip odin.zip

$(OBJECTS): setup
	$(shell echo $(platform))
	$(shell echo $(system_platform))
	ls -al $(PATH):$(PWD)/odin-linux-amd64-$(ODIN_VERSION)
	export PATH=$(PATH):$(PWD)/odin-linux-amd64-$(ODIN_VERSION) && ODIN_TARGET=linux_amd64 $(MAKE) -C $(CORE_DIR) object
	ls -al

$(TARGET): $(OBJECTS)
ifeq ($(STATIC_LINKING), 1)
	$(AR) rcs $@ $(OBJECTS)
else
	@$(if $(Q), $(shell echo echo LD $@),)
	$(Q)$(CC) $(fpic) $(SHARED) -o $@ $(CORE_DIR)$(OBJECTS) $(LDFLAGS)
endif

clean:
	rm -f $(OBJECTS) $(TARGET)
	-$(MAKE) -C $(CORE_DIR) clean

.PHONY: clean

print-%:
	@echo '$*=$($*)'
