@echo off
odin build src\frontend -out:virtualxt_libretro.dll -build-mode:dll -o:speed -collection:vxt=src -collection:modules=src\modules -collection:bios=bios -collection:boot=boot
