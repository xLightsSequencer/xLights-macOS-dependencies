#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

cd zstd
export CFLAGS="-g -flto=thin  ${OSX_VERSION_MIN} ${XL_TARGETS}"
export LDFLAGS="-flto=thin  ${OSX_VERSION_MIN} ${XL_TARGETS} "
make clean
make -j ${NUMCPUS} HAVE_LZMA=0 HAVE_LZ4=0 lib-mt
cp lib/libzstd.a ${BASE_DEPS_DIR}/lib
export CFLAGS="-g  ${OSX_VERSION_MIN} ${XL_TARGETS}"
export LDFLAGS=" ${OSX_VERSION_MIN} ${XL_TARGETS}"
make clean
make -j ${NUMCPUS} HAVE_LZMA=0 HAVE_LZ4=0 lib-mt
cp lib/libzstd.a ${BASE_DEPS_DIR}/libdbg
unset CFLAGS
unset LDFLAGS
# Ship the headers next to the library. Without them consumers compile against
# some other copy of zstd, and header/library skew across versions is exactly
# what this repo exists to prevent.
cp -f lib/zstd.h lib/zdict.h lib/zstd_errors.h ${BASE_DEPS_DIR}/include/

make clean

cd ..
