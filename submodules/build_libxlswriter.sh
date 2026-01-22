#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

cd libxlswriter

export CXXFLAGS="-g -O3 -flto=thin ${XL_TARGETS} ${OSX_VERSION_MIN} "
export CFLAGS="-g -O3 -flto=thin ${XL_TARGETS} ${OSX_VERSION_MIN} "
export LDFLAGS="-g -O3 -flto=thin ${XL_TARGETS} ${OSX_VERSION_MIN} "
cmake -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"
make -j ${NUMCPUS}
cp libxlsxwriter.a ${BASE_DEPS_DIR}/lib/
make clean
export CXXFLAGS="-g ${XL_TARGETS} ${OSX_VERSION_MIN} "
export CFLAGS="-g ${XL_TARGETS} ${OSX_VERSION_MIN} "
export LDFLAGS="-g ${XL_TARGETS} ${OSX_VERSION_MIN} "
cmake -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"
make -j ${NUMCPUS}
cp libxlsxwriter.a ${BASE_DEPS_DIR}/libdbg/
cp -a include/* ${BASE_DEPS_DIR}/include
make  clean
git checkout -- Makefile
git reset --hard
git status --ignored --short . | colrm 1 2 | xargs rm -rf
unset CXXFLAGS
unset CFLAGS
unset LDFLAGS


cd ..


