Copy all files to the root directory of a FAT32 formated SDCard.
(Only RasberryPi 3 and 4 is supported at this time.)

The default boot order is SD:A.img, SD:C.img, USB:RAW. Note that USB drives
are not plug and play. They need to be inserted and removed while the system
is powered off as they are considered harddrives in the virtual system.
The size of a USB drive when mounted is caped at ~504MB but the actual device
can be of any size. To prevent disk corruption it is recommended to use FDISK
in DOS to ensure the correct size and format when using a USB drive.

Ethernet support should work but is not well tested. Run the ETHERNET.BAT
file on the included disk image to load drivers and launch DHCP server.

Known issus:
  * Audio is not working atm. :(
  * Keyboard has issues at times.
  * Old USB mouses have been known to lockup the system when connected. 

VirtualXT specific options in cmdline.txt are:
  BOOT=<set boot device, BIOS disk id>
  FD=<floppy image on SDCard>
  HD=<harddrive image on SDCard>
  LOGFILE=<log to file on SDCard>
  CPUFREQ=<virtual CPU frequency in Hz>
