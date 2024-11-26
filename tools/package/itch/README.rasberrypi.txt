Copy all files to the root directory of a FAT32 formated SDCard.
VirtualXT can run on RasberryPi 3/4/5, although the RPI3 is on the slow side
and the RPI5 is not that well tested. So you are best of with a RPI4. :)

The default boot order is SD:A.img, SD:C.img, USB:RAW. Note that USB drives
are not plug and play. They need to be inserted and removed while the system
is powered off as they are considered harddrives in the virtual system.
The size of a USB drive when mounted is caped at ~504MB but the actual device
can be of any size. To prevent disk corruption it is recommended to use FDISK
in DOS to ensure the correct size and format when using a USB drive.

The keyboard is mapped as a US Model-F keyboard common on PC/XT and AT
machines in the 80's. This means a lot of "modern" keys do not work since
PC style USB (and PS2) keyboards are based on the later IBM Model-M.

Ethernet support should work but is not well tested. Run the ETHERNET.BAT
file on the included disk image to load drivers and launch DHCP server.

If you get stuck with a black screen during boot, try enable logging and
detatch all USB devices including mouse and keyboard.

On RPI3 you might get better results when gaming if you run with CPUSTEP=DROP.
This can however break the internal timekeeping for some applications.

VirtualXT specific options in cmdline.txt:
  BOOT=<set boot device, BIOS disk id>
  FD=<floppy image on SDCard>
  HD=<harddrive image on SDCard>
  LOGFILE=<log to file on SDCard>
  CPUFREQ=<virtual CPU frequency in Hz>
  CPUSTEP=<FIXED/DROP/FLOAT, default is FIXED>
  CGA=<Emulate CGA adapter 0/1 >
