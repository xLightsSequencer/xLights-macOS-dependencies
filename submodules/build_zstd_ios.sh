#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

cd zstd

# --- iOS Release build (arm64) ---
export CFLAGS="-g -O3 -flto=thin ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
export LDFLAGS="-flto=thin ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
make clean
make -j ${NUMCPUS} HAVE_LZMA=0 HAVE_LZ4=0 lib-mt
cp lib/libzstd.a ${BASE_DEPS_DIR}/lib-ios/

# --- iOS Debug build (arm64) ---
export CFLAGS="-g ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
export LDFLAGS="${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
make clean
make -j ${NUMCPUS} HAVE_LZMA=0 HAVE_LZ4=0 lib-mt
cp lib/libzstd.a ${BASE_DEPS_DIR}/libdbg-ios/

# --- iOS Simulator Release build (arm64-simulator) ---
export CFLAGS="-g -O3 -flto=thin ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}"
export LDFLAGS="-flto=thin ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}"
make clean
make -j ${NUMCPUS} HAVE_LZMA=0 HAVE_LZ4=0 lib-mt
cp lib/libzstd.a ${BASE_DEPS_DIR}/lib-ios-sim/

# --- iOS Simulator Debug build (arm64-simulator) ---
export CFLAGS="-g ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}"
export LDFLAGS="${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}"
make clean
make -j ${NUMCPUS} HAVE_LZMA=0 HAVE_LZ4=0 lib-mt
cp lib/libzstd.a ${BASE_DEPS_DIR}/libdbg-ios-sim/

unset CFLAGS
unset LDFLAGS
make clean

cd ..
