#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

cd lua

make clean
export CFLAGS="-g -O3 -flto=thin -Wall -fno-stack-protector -fno-common ${XL_TARGETS} ${OSX_VERSION_MIN} "
make -j ${NUMCPUS} all CFLAGS="$CFLAGS" MYLDFLAGS="$CFLAGS"
cp liblua.a ${BASE_DEPS_DIR}/lib
cp lua.h luaconf.h lualib.h lauxlib.h ${BASE_DEPS_DIR}/include
make clean
export CFLAGS="-g ${XL_TARGETS} ${OSX_VERSION_MIN} "
make -j ${NUMCPUS} all CFLAGS="$CFLAGS" MYLDFLAGS="$CFLAGS"
cp liblua.a ${BASE_DEPS_DIR}/libdbg
make clean
unset CFLAGS


cd ..
