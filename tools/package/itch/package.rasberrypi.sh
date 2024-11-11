#!/bin/bash

DIR=${GITHUB_WORKSPACE}/package
rm -rf ${DIR}
mkdir ${DIR}

cp ${CIRCLEHOME}/boot/*.dtb ${DIR}
cp ${CIRCLEHOME}/boot/*.dat ${DIR}
cp ${CIRCLEHOME}/boot/*.bin ${DIR}
cp ${CIRCLEHOME}/boot/*.elf ${DIR}

cp ../../../front/rpi/kernel8-32.img ${DIR}
cp ${CIRCLEHOME}/boot/config32.txt ${DIR}/config.txt
