#!/bin/bash

DIR=${GITHUB_WORKSPACE}/package
rm -rf ${DIR}

DIR_RPI3=${DIR}/RaspberryPi3
mkdir -p ${DIR_RPI3}

cp ${CIRCLEHOME}/boot/*.dtb ${DIR_RPI3}
cp ${CIRCLEHOME}/boot/*.dat ${DIR_RPI3}
cp ${CIRCLEHOME}/boot/*.bin ${DIR_RPI3}
cp ${CIRCLEHOME}/boot/*.elf ${DIR_RPI3}

cp front/rpi/kernel8-32.img ${DIR_RPI3}
cp ${CIRCLEHOME}/boot/config32.txt ${DIR_RPI3}/config.txt

cp boot/freedos_web_hd.img ${DIR_RPI3}/C.img
cp bios/GLABIOS.ROM ${DIR_RPI3}
cp bios/vxtx.bin ${DIR_RPI3}

cp tools/package/itch/README.rasberrypi.txt ${DIR}/README.txt
