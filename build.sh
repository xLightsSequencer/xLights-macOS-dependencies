#!/bin/bash


. ./env.sh


BASE_DEPS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

echo "Base Dir:  ${BASE_DEPS_DIR}"

sysctl -a | grep hw.perflevel


mkdir -p ${BASE_DEPS_DIR}/lib
mkdir -p ${BASE_DEPS_DIR}/libdbg
mkdir -p ${BASE_DEPS_DIR}/lib-ios
mkdir -p ${BASE_DEPS_DIR}/libdbg-ios
mkdir -p ${BASE_DEPS_DIR}/bin
mkdir -p ${BASE_DEPS_DIR}/share
mkdir -p ${BASE_DEPS_DIR}/include

git submodule update --init --force


cd submodules

./build_wxwidgets.sh 2>&1 | tee ./build_wxwidgets.log

./build_zstd.sh 2>&1 | tee ./build_zstd.log

./build_liquidfun.sh 2>&1 | tee ./build_liquidfun.log

./build_sdl.sh 2>&1 | tee ./build_sdl.log

./build_lua.sh 2>&1 | tee ./build_lua.log

./build_libxlswriter.sh 2>&1 | tee ./build_libxlswriter.log

./build_hidapi.sh 2>&1 | tee ./build_hidapi.log

./build_ffmpeg.sh 2>&1 | tee ./build_ffmpeg.log

./build_curl.sh 2>&1 | tee ./build_curl.log

./install_ispc.sh 2>&1 | tee ./install_ispc.log

# --- iOS builds (arm64 only, libraries needed for iPad app) ---
./build_zstd_ios.sh 2>&1 | tee ./build_zstd_ios.log
./build_liquidfun_ios.sh 2>&1 | tee ./build_liquidfun_ios.log
./build_lua_ios.sh 2>&1 | tee ./build_lua_ios.log
./build_libxlswriter_ios.sh 2>&1 | tee ./build_libxlswriter_ios.log
./build_curl_ios.sh 2>&1 | tee ./build_curl_ios.log


./build_angle.sh 2>&1 | tee ./build_angle.log


cd ..


rm -rf output
mkdir -p output

cd ..

tar  --exclude-vcs --exclude submodules --exclude .github --exclude build.sh --exclude env.sh --exclude output -c xLights-macOS-dependencies | zstd -18 -T0 -f -o xLights-macOS-dependencies/output/xLights-macOS-dependencies.tar.zst
