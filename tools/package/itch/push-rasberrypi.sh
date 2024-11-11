#!/bin/bash

butler login
butler push package phix/virtualxt:rasberrypi-${GITHUB_REF_NAME} --userversion ${VXT_VERSION}-${GITHUB_RUN_ID}
