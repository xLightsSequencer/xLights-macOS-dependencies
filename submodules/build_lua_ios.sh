#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

cd lua

# --- iOS Release build (arm64) ---
make clean
export CFLAGS="-g -O3 -flto=thin -Wall -fno-stack-protector -fno-common -DLUA_USE_IOS ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
make -j ${NUMCPUS} all CFLAGS="$CFLAGS" MYLDFLAGS="$CFLAGS"
cp liblua.a ${BASE_DEPS_DIR}/lib-ios/

# --- iOS Debug build (arm64) ---
make clean
export CFLAGS="-g -DLUA_USE_IOS ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
make -j ${NUMCPUS} all CFLAGS="$CFLAGS" MYLDFLAGS="$CFLAGS"
cp liblua.a ${BASE_DEPS_DIR}/libdbg-ios/

# --- iOS Simulator Release build (arm64-simulator) ---
make clean
export CFLAGS="-g -O3 -flto=thin -Wall -fno-stack-protector -fno-common -DLUA_USE_IOS ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}"
make -j ${NUMCPUS} all CFLAGS="$CFLAGS" MYLDFLAGS="$CFLAGS"
cp liblua.a ${BASE_DEPS_DIR}/lib-ios-sim/

# --- iOS Simulator Debug build (arm64-simulator) ---
make clean
export CFLAGS="-g -DLUA_USE_IOS ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}"
make -j ${NUMCPUS} all CFLAGS="$CFLAGS" MYLDFLAGS="$CFLAGS"
cp liblua.a ${BASE_DEPS_DIR}/libdbg-ios-sim/

make clean
unset CFLAGS

cd ..
