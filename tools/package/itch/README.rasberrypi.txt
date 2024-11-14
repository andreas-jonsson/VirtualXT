Copy all files to the root directory of a FAT32 formated SDCard.
(Only RasberryPi 3 and 4 is supported at this time.)

Default boot order is SD:A.img, SD:C.img, USB:RAW

VirtualXT specific options in cmdline.txt are:
	BOOT=<set boot device, BIOS disk id>
	FD=<floppy image on SDCard>
	HD=<harddrive image on SDCard>
	LOGFILE=<log to file on SDCard>
	CPUFREQ=<virtual CPU frequency in Hz>
