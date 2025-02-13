# VirtualXT

[![Build](https://github.com/virtualxt/virtualxt/actions/workflows/libretro.yml/badge.svg)](https://github.com/virtualxt/virtualxt/actions/workflows/sdl2.yml)
[![Chat](https://img.shields.io/matrix/virtualxt:matrix.org)](https://matrix.to/#/#virtualxt:matrix.org)
[![Support](https://github.com/BoostIO/issuehunt-materials/raw/master/v1/issuehunt-shield-v1.svg)](https://issuehunt.io/r/virtualxt/virtualxt)

VirtualXT is a [libretro](https://www.libretro.com) Turbo PC/XT emulator that runs on modern hardware, operating systems and bare-metal ARM SBCs.
It is designed to be simple and lightweight yet still capable enough to run a large library of old application and games.

Browser version is avalible [here](https://realmode.games).

## Features

* Intel 286 processor
* PC/XT chipset
* Hardware CPU validator
* CGA or VGA compatible graphics
* EMS and UMA memory
* AdLib music synthesizer
* Serial UARTs
* Ethernet adapter
* Runs on bare-metal ARM
* Direct file share with host
* ISA passthrough​ using Arstech USB2ISA adapter
* GLaBIOS or Turbo XT BIOS 3.1 with extensions
* Integerated GDB server
* Flexible module system
* and more...

## Screenshots

![freedos screenshot](screenshots/freedos.PNG)

![win30setup screenshot](screenshots/win30setup.PNG)

![monkey screenshot](screenshots/monkey.PNG)

## Build

The emulator is written in [Odin](https://odin-lang.org) and can be compiled using the included GNU Makefile.

```
git clone https://github.com/virtualxt/virtualxt.git
cd virtualxt
make release
# Or if you have RetroArch installed.
make run
```

You can download pre-built binaries from [itch.io](https://phix.itch.io/virtualxt/purchase).

## ISA Passthrough​

VirtualXT supports ISA passthrough using Arstech [USB2ISA](https://arstech.com/install/ecom-catshow/usb2.0.html) adapter or the [CH367](https://www.aliexpress.com/item/1005003569540792.html) development board.
It should be noted that DMA currently not supported and the CH367 board is **VERY** limited in it's capabilities.

![isa passthrough screenshot​](screenshots/isa.jpg)

## Hardware Validation

A hardware validator was developed to ensure proper CPU behaviour.
Some additional information about that can be found [here](https://hackaday.io/project/184209-virtualxt-hardware-validator).
This [talk](https://youtu.be/qatzd0niz9A?si=_NVqQu_zc1KDB8W6) by Daniel Balsom describes the process in details.

![validator screenshot](screenshots/validator.jpg)

## Shout-out

Friends, contributors and sources of inspiration!

* **gloriouscow**
* **homebrew8088**
* **fmahnke**
* **adriancable**
* **mikechambers84**
* **trylle**
* **640-KB**
