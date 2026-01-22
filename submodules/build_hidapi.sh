#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

cd hidapi

export CFLAGS="-g -O3 -flto=thin -Wall -fno-stack-protector -fno-common ${XL_TARGETS} ${OSX_VERSION_MIN} "
./bootstrap
./configure --prefix=${BASE_DEPS_DIR}
make clean
make -j ${NUMCPUS}
cp ./mac/.libs/libhidapi.a ${BASE_DEPS_DIR}/lib
make clean
export CFLAGS="-g -Wall -fno-stack-protector -fno-common ${XL_TARGETS} ${OSX_VERSION_MIN} "
./configure --prefix=${BASE_DEPS_DIR}
make -j ${NUMCPUS}
rm -f /opt/local/libdbg/libhidapi*
cp ./mac/.libs/libhidapi.a ${BASE_DEPS_DIR}/libdbg
make clean
unset CFLAGS





cd ..
