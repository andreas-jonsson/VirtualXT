#!/bin/bash

DIR=${GITHUB_WORKSPACE}/package

cp ${GITHUB_WORKSPACE}/kernel8.img ${DIR}
cp ${GITHUB_WORKSPACE}/kernel8-rpi4.img ${DIR}
cp ${GITHUB_WORKSPACE}/kernel_2712.img ${DIR}

cp boot/freedos_rpi_hd.img ${DIR}/C.img
cp bios/GLABIOS.ROM ${DIR}
cp bios/vxtx.bin ${DIR}
cp bios/vgabios.bin ${DIR}

cp tools/package/itch/README.rasberrypi.txt ${DIR}/README.txt
