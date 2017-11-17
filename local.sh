#!/usr/bin/env bash

export JOB_NAME=recodesign
export BUILD_VERSION_PATH=http://127.0.0.1/oneapple.ipa
export BUNDLE_IDENTIFIER=com.ysl.oneaplle
 chmod +x *.sh
./iOS-recodesign.sh
