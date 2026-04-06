#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

cd curl

# Clean any previous build
[ -f Makefile ] && make clean
git reset --hard
git status --ignored --short . | colrm 1 2 | xargs rm -rf

autoreconf -fi

# --- Release build (universal) ---
export CFLAGS="-g -O3 -flto=thin ${XL_TARGETS} ${OSX_VERSION_MIN}"
export LDFLAGS="-g -O3 -flto=thin ${XL_TARGETS} ${OSX_VERSION_MIN}"
./configure --with-secure-transport --without-openssl \
    --disable-shared --enable-static \
    --disable-ldap --disable-ldaps --disable-dict --disable-telnet --disable-tftp \
    --disable-pop3 --disable-imap --disable-smb --disable-smtp \
    --disable-gopher --disable-rtsp --disable-manual \
    --without-brotli --without-zstd --without-nghttp2 --without-libidn2 --without-libpsl \
    --prefix="${BASE_DEPS_DIR}" \
    --host=arm-apple-darwin
make -j ${NUMCPUS}
cp lib/.libs/libcurl.a ${BASE_DEPS_DIR}/lib/
cp -a include/curl ${BASE_DEPS_DIR}/include/

# --- Debug build (universal) ---
make clean
export CFLAGS="-g ${XL_TARGETS} ${OSX_VERSION_MIN}"
export LDFLAGS="-g ${XL_TARGETS} ${OSX_VERSION_MIN}"
./configure --with-secure-transport --without-openssl \
    --disable-shared --enable-static \
    --disable-ldap --disable-ldaps --disable-dict --disable-telnet --disable-tftp \
    --disable-pop3 --disable-imap --disable-smb --disable-smtp \
    --disable-gopher --disable-rtsp --disable-manual \
    --without-brotli --without-zstd --without-nghttp2 --without-libidn2 --without-libpsl \
    --prefix="${BASE_DEPS_DIR}" \
    --host=arm-apple-darwin
make -j ${NUMCPUS}
cp lib/.libs/libcurl.a ${BASE_DEPS_DIR}/libdbg/

# Cleanup
unset CFLAGS
unset LDFLAGS
make clean
git reset --hard
git status --ignored --short . | colrm 1 2 | xargs rm -rf

cd ..
