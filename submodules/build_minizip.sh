#!/bin/bash
#
# build_minizip.sh - macOS (universal) build of zlib's contrib/minizip.
#
# minizip lives inside the zlib submodule, so there is nothing extra to check
# out. macOS takes zlib itself from the system, but there is no system minizip,
# which is why this is built here while build_zlib is Windows-only.
#
# xLights uses this for sequence packages and FPP uploads. It previously
# compiled the copy vendored inside libxlsxwriter - the 2010 release of the same
# code, carrying no local patches. Debian's libminizip-dev comes from this same
# contrib/ source, so the bundle and Linux stay on matching code.

set -e

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

SRC="${SCRIPT_DIR}/zlib/contrib/minizip"
if [ ! -f "${SRC}/unzip.c" ]; then
    echo "build_minizip: zlib submodule not checked out (${SRC})" >&2
    exit 1
fi

# iowin32.c is the Win32 backend; minizip.c and miniunz.c are the command-line
# tools and define main(). None belong in the library on macOS.
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

# Release carries no debug flag; debug uses -g. Both are universal, matching
# every other macOS artifact here.
build_variant lib    -g -O3 -flto=thin ${XL_TARGETS} ${OSX_VERSION_MIN}
build_variant libdbg -g                ${XL_TARGETS} ${OSX_VERSION_MIN}

# Consumers include <minizip/unzip.h>, which is where Debian's libminizip-dev
# puts them, so one spelling works on every platform.
mkdir -p "${BASE_DEPS_DIR}/include/minizip"
# ioapi.h pulls in ints.h; mz64conf.h and bzlib.h are behind #ifdefs this
# build does not define.
for h in zip.h unzip.h ioapi.h ints.h crypt.h mztools.h; do
    cp "${SRC}/${h}" "${BASE_DEPS_DIR}/include/minizip/"
done

echo "==> minizip done"
