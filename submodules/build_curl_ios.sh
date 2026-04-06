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

# --- iOS Release build (arm64) ---
export CFLAGS="-g -O3 -flto=thin ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
export LDFLAGS="-g -O3 -flto=thin ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
./configure --with-secure-transport --without-openssl \
    --disable-shared --enable-static \
    --disable-ldap --disable-ldaps --disable-dict --disable-telnet --disable-tftp \
    --disable-pop3 --disable-imap --disable-smb --disable-smtp \
    --disable-gopher --disable-rtsp --disable-manual \
    --without-brotli --without-zstd --without-nghttp2 --without-libidn2 --without-libpsl \
    --host=arm-apple-darwin \
    --prefix="${BASE_DEPS_DIR}"
make -j ${NUMCPUS}
cp lib/.libs/libcurl.a ${BASE_DEPS_DIR}/lib-ios/

# --- iOS Debug build (arm64) ---
make clean
export CFLAGS="-g ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
export LDFLAGS="-g ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
./configure --with-secure-transport --without-openssl \
    --disable-shared --enable-static \
    --disable-ldap --disable-ldaps --disable-dict --disable-telnet --disable-tftp \
    --disable-pop3 --disable-imap --disable-smb --disable-smtp \
    --disable-gopher --disable-rtsp --disable-manual \
    --without-brotli --without-zstd --without-nghttp2 --without-libidn2 --without-libpsl \
    --host=arm-apple-darwin \
    --prefix="${BASE_DEPS_DIR}"
make -j ${NUMCPUS}
cp lib/.libs/libcurl.a ${BASE_DEPS_DIR}/libdbg-ios/

# Cleanup
unset CFLAGS
unset LDFLAGS
make clean
git reset --hard
git status --ignored --short . | colrm 1 2 | xargs rm -rf

cd ..
