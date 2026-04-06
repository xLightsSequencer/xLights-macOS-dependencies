#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

cd libxlswriter

# --- iOS Release build (arm64) ---
export CXXFLAGS="-g -O3 -flto=thin ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
export CFLAGS="-g -O3 -flto=thin ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
export LDFLAGS="-g -O3 -flto=thin ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
cmake -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_MIN_VERSION}
make -j ${NUMCPUS}
cp libxlsxwriter.a ${BASE_DEPS_DIR}/lib-ios/

# --- iOS Debug build (arm64) ---
make clean
export CXXFLAGS="-g ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
export CFLAGS="-g ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
export LDFLAGS="-g ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
cmake -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_MIN_VERSION}
make -j ${NUMCPUS}
cp libxlsxwriter.a ${BASE_DEPS_DIR}/libdbg-ios/

make clean
git checkout -- Makefile
git reset --hard
git status --ignored --short . | colrm 1 2 | xargs rm -rf
unset CXXFLAGS
unset CFLAGS
unset LDFLAGS

cd ..
