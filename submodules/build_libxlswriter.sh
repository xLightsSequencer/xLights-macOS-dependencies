#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

cd libxlswriter

# USE_SYSTEM_MINIZIP stops libxlsxwriter compiling its own copy of minizip's
# write half, which otherwise defines the same zip* symbols this bundle's
# minizip does, leaving which implementation runs up to link order. Its
# discovery wants pkg-config, and this bundle ships no .pc files by design, so
# redirect it at what build_minizip.sh already produced. The git reset at the
# end of this script puts the CMakeLists back.
perl -0777 -pi -e 's/if\(MSVC\)\s*\n\s*find_package\(MINIZIP.*?\n\s*endif\(\)/set(MINIZIP_LIBRARIES \${XL_MINIZIP_LIBRARY})\n    list(APPEND LXW_PRIVATE_INCLUDE_DIRS \${XL_MINIZIP_INCLUDE_DIR})/s' CMakeLists.txt
if ! grep -q 'XL_MINIZIP_LIBRARY' CMakeLists.txt; then
    echo "build_libxlswriter: could not redirect USE_SYSTEM_MINIZIP discovery - upstream CMakeLists changed" >&2
    exit 1
fi

MZ_OPTS_COMMON="-DUSE_SYSTEM_MINIZIP=ON -DXL_MINIZIP_INCLUDE_DIR=${BASE_DEPS_DIR}/include"

export CXXFLAGS="-g -O3 -flto=thin ${XL_TARGETS} ${OSX_VERSION_MIN} "
export CFLAGS="-g -O3 -flto=thin ${XL_TARGETS} ${OSX_VERSION_MIN} "
export LDFLAGS="-g -O3 -flto=thin ${XL_TARGETS} ${OSX_VERSION_MIN} "
cmake -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" ${MZ_OPTS_COMMON} -DXL_MINIZIP_LIBRARY=${BASE_DEPS_DIR}/lib/libminizip.a
make -j ${NUMCPUS}
cp libxlsxwriter.a ${BASE_DEPS_DIR}/lib/
make clean
export CXXFLAGS="-g ${XL_TARGETS} ${OSX_VERSION_MIN} "
export CFLAGS="-g ${XL_TARGETS} ${OSX_VERSION_MIN} "
export LDFLAGS="-g ${XL_TARGETS} ${OSX_VERSION_MIN} "
cmake -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" ${MZ_OPTS_COMMON} -DXL_MINIZIP_LIBRARY=${BASE_DEPS_DIR}/libdbg/libminizip.a
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


