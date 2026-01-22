#!/bin/bash

. ./env.sh


BASE_DEPS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

echo "Base Dir:  ${BASE_DEPS_DIR}"

sysctl -a | grep hw.perflevel


mkdir -p ${BASE_DEPS_DIR}/lib
mkdir -p ${BASE_DEPS_DIR}/libdbg
mkdir -p ${BASE_DEPS_DIR}/bin
mkdir -p ${BASE_DEPS_DIR}/share
mkdir -p ${BASE_DEPS_DIR}/include


cd submodules

./build_wxwidgets.sh 2>&1 | tee ./build_wxwidgets.log

./build_zstd.sh 2>&1 | tee ./build_zstd.log

./build_log4cpp.sh 2>&1 | tee ./build_log4cpp.log

./build_liquidfun.sh 2>&1 | tee ./build_liquidfun.log

./build_sdl.sh 2>&1 | tee ./build_sdl.log

./build_lua.sh 2>&1 | tee ./build_lua.log

./build_libxlswriter.sh 2>&1 | tee ./build_libxlswriter.log

./build_libusb.sh 2>&1 | tee ./build_libusb.log

./build_ffmpeg.sh 2>&1 | tee ./build_ffmpeg.log

./install_ispc.sh 2>&1 | tee ./install_ispc.log


cd ..


rm -rf output
mkdir -p output

cd ..

tar  --exclude-vcs --exclude submodules --exclude build.sh --exclude env.sh --exclude output -c xLights-macOS-dependencies | zstd -18 -T0 -f -o xLights-macOS-dependencies/output/xLights-macOS-dependencies.tar.zst
