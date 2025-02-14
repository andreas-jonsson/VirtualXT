STATIC_LINKING := 0
AR             := ar
ODIN_VERSION   := dev-2025-02
TARGET_NAME    := virtualxt
CORE_DIR       := ../../../

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
system_odin = linux-amd64
ifeq ($(shell uname -a),)
	EXE_EXT = .exe
	system_odin = windows-amd64
else ifneq ($(findstring Darwin,$(shell uname -a)),)
	system_odin = macos-amd64
	ifeq ($(shell uname -p),arm)
    	system_odin = macos-arm64
	endif
else ifneq ($(findstring MINGW,$(shell uname -a)),)
	system_odin = windows-amd64
endif

ifeq ($(STATIC_LINKING), 1)
   EXT := a
endif

ifneq (,$(findstring unix,$(platform)))
   EXT ?= so
   TARGET := $(TARGET_NAME)_libretro.$(EXT)
   fpic := -fPIC
   SHARED := -shared -Wl,--no-undefined

   # NOTE: Is this always linux amd64?
   ODIN_TARGET = linux_amd64
else ifeq ($(platform), linux-portable)
   EXT ?= so
   TARGET := $(TARGET_NAME)_libretro.$(EXT)
   fpic := -fPIC -nostdlib
   SHARED := -shared

   # TODO: Check if this is 32 or 64bit
   ODIN_TARGET = freestanding_amd64_sysv
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
      # Note: There are no freestanding i386 target atm. But this should work.
      ODIN_TARGET = linux_i386
   else ifeq ($(platform), android-x86_64)
      TARGET_TRIPLE = x86_64-linux-android
      ODIN_TARGET = freestanding_amd64_sysv
   endif

   CC = $(ANDROID_NDK_LLVM)/bin/$(TARGET_TRIPLE)21-clang
   AR = $(ANDROID_NDK_LLVM)/bin/llvm-ar

else ifneq (,$(findstring osx,$(platform)))
   TARGET := $(TARGET_NAME)_libretro.dylib
   fpic := -fPIC
   SHARED := -dynamiclib
   TARGET_PLATFORM = $(shell uname -p)

   ifeq ($(CROSS_COMPILE),1)
		TARGET_RULE   = -target $(LIBRETRO_APPLE_PLATFORM) -isysroot $(LIBRETRO_APPLE_ISYSROOT)
		LDFLAGS      += $(TARGET_RULE)
		TARGET_PLATFORM = $(LIBRETRO_APPLE_PLATFORM)
   endif

   ifeq (,$(findstring arm,$(TARGET_PLATFORM)))
		ODIN_TARGET = darwin_arm64
   else
		ODIN_TARGET = darwin_amd64
   endif
else ifneq (,$(findstring ios,$(platform)))
   EXT ?= dylib
   TARGET := $(TARGET_NAME)_libretro_ios.$(EXT)
   fpic := -fPIC
   SHARED := -dynamiclib
   MIN_VERSION := -miphoneos-version-min=5.0

   ifeq ($(platform),$(filter $(platform),ios9 ios-arm64))
      MIN_VERSION = -miphoneos-version-min=8.0
   endif
   ifeq ($(IOSSDK),)
      IOSSDK := $(shell xcodebuild -version -sdk iphoneos Path)
   endif

   ODIN_SUBTARGET = ios
   ifeq ($(platform),ios-arm64)
      SHARED += -arch arm64 $(MIN_VERSION) -isysroot $(IOSSDK)
      CC = cc -arch arm64 $(MIN_VERSION) -isysroot $(IOSSDK)
      ODIN_TARGET = darwin_arm64
   else
      SHARED += -arch armv7 $(MIN_VERSION) -isysroot $(IOSSDK)
      CC = cc -arch armv7 $(MIN_VERSION) -isysroot $(IOSSDK)
      ODIN_TARGET = darwin_arm32
   endif
else ifneq (,$(findstring tvos,$(platform)))
   EXT ?= dylib
   TARGET := $(TARGET_NAME)_libretro_tvos.$(EXT)
   fpic := -fPIC
   SHARED := -dynamiclib
   MIN_VERSION := -mappletvos-version-min=9.0

   ifeq ($(TVOSSDK),)
      TVOSSDK := $(shell xcodebuild -version -sdk appletvos Path)
   endif

   SHARED += -arch arm64 $(MIN_VERSION) -isysroot $(TVOSSDK)
   CC = cc -arch arm64 $(MIN_VERSION) -isysroot $(TVOSSDK)
   ODIN_TARGET = freestanding_arm64
else ifeq ($(platform), emscripten)
   # Emscripten is not supported atm.
else
   TARGET := $(TARGET_NAME)_libretro.dll
   SHARED := -shared -static-libgcc -s -Wl,--no-undefined

   ifeq ($(platform), win64)
    	ODIN_TARGET = windows_amd64
   else
		ODIN_TARGET = windows_i386
   endif
endif

MKPATH = $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
OBJECTS = $(TARGET_NAME)_libretro.o

all: $(TARGET)

setup:
	curl -L -o odin.zip https://github.com/odin-lang/Odin/releases/download/$(ODIN_VERSION)/odin-$(system_odin)-$(ODIN_VERSION).zip && unzip odin.zip

$(OBJECTS): setup
	@echo platform: $(platform)
	@echo target: $(ODIN_TARGET)
	PATH=$(PATH):$(MKPATH)/odin-$(system_odin)-$(ODIN_VERSION) ODIN_TARGET=$(ODIN_TARGET) ODIN_SUBTARGET=$(ODIN_SUBTARGET) ODIN_VET= $(MAKE) -C $(CORE_DIR) object

$(TARGET): $(OBJECTS)
ifeq ($(STATIC_LINKING), 1)
	$(AR) rcs $@ $(OBJECTS)
else
	@$(if $(Q), $(shell echo echo LD $@),)
	$(Q)$(CC) $(fpic) $(SHARED) -o $@ $(CORE_DIR)$(OBJECTS) $(LDFLAGS)
endif

clean:
	rm -f $(OBJECTS) $(TARGET) odin.zip
	rm -rf odin-$(system_odin)-$(ODIN_VERSION)
	-$(MAKE) -C $(CORE_DIR) clean

.PHONY: clean

print-%:
	@echo '$*=$($*)'
