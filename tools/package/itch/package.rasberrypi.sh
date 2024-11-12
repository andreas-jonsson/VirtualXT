#!/bin/bash

DIR=${GITHUB_WORKSPACE}/package

cp ${GITHUB_WORKSPACE}/kernel8-32.img ${DIR}
cp ${GITHUB_WORKSPACE}/kernel7l.img ${DIR}

cp boot/freedos_rpi_hd.img ${DIR}/C.img
cp bios/GLABIOS.ROM ${DIR}
cp bios/vxtx.bin ${DIR}

cp tools/package/itch/README.rasberrypi.txt ${DIR}/README.txt
