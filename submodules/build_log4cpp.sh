#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

cd log4cpp
export CXXFLAGS="-g -O2 -flto=thin ${OSX_VERSION_MIN} ${XL_TARGETS} -std=c++11 -stdlib=libc++ -fvisibility-inlines-hidden "
export LDFLAGS="-flto=thin ${XL_TARGETS} "

glibtoolize --force --automake
aclocal -I m4 $ACLOCAL_FLAGS
autoheader
automake --add-missing
autoconf

cmake -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"
./configure --prefix=${BASE_DEPS_DIR} -host ${BUILD_HOST}
make clean
make -j ${NUMCPUS}
cp src/.libs/liblog4cpp.a ${BASE_DEPS_DIR}/lib
export CXXFLAGS="-g ${OSX_VERSION_MIN} ${XL_TARGETS} -std=c++11 -stdlib=libc++ -fvisibility-inlines-hidden "
export LDFLAGS="${XL_TARGETS} "
./configure --prefix=${BASE_DEPS_DIR} -host ${BUILD_HOST}
make clean
make -j ${NUMCPUS}
cp src/.libs/liblog4cpp.a ${BASE_DEPS_DIR}/libdbg
make clean
git reset --hard
git status --ignored --short . | colrm 1 2 | xargs rm -rf
unset CXXFLAGS
unset LDFLAGS

cd ..
