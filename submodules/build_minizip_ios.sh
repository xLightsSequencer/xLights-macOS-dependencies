#!/bin/bash
#
# build_minizip_ios.sh - iOS device and simulator builds of zlib's
# contrib/minizip. See build_minizip.sh for why minizip is built here at all.

set -e

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

SRC="${SCRIPT_DIR}/zlib/contrib/minizip"
if [ ! -f "${SRC}/unzip.c" ]; then
    echo "build_minizip_ios: zlib submodule not checked out (${SRC})" >&2
    exit 1
fi

SOURCES="ioapi.c unzip.c zip.c mztools.c"

build_variant() {          # build_variant <outdir> <extra-cflags...>
    local outdir="$1"; shift
    local work
    work=$( mktemp -d )
    for c in ${SOURCES}; do
        clang -c "$@" -I"${SRC}" "${SRC}/${c}" -o "${work}/${c%.c}.o"
    done
    # libtool, not ar: these objects are universal, and ar/ranlib warn that the
    # resulting archive is fat and they cannot operate on it. The archive links
    # either way, but the warning is noise in every build log.
    libtool -static -o "${work}/libminizip.a" "${work}"/*.o
    mkdir -p "${BASE_DEPS_DIR}/${outdir}"
    cp "${work}/libminizip.a" "${BASE_DEPS_DIR}/${outdir}/"
    rm -rf "${work}"
    echo "    -> ${outdir}/libminizip.a"
}

build_variant lib-ios        -g -O3 -flto=thin ${IOS_ARM64_TARGETS}     ${IOS_VERSION_MIN}
build_variant libdbg-ios     -g                ${IOS_ARM64_TARGETS}     ${IOS_VERSION_MIN}
build_variant lib-ios-sim    -g -O3 -flto=thin ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}
build_variant libdbg-ios-sim -g                ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}

echo "==> minizip (iOS) done"
