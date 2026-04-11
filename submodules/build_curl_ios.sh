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

# curl's autoconf check for pipe2 misfires on the iPhoneSimulator SDK: the link
# test finds a stub in libSystem but <unistd.h> in that SDK does not declare
# the prototype, so socketpair.c fails to compile. Force pipe2 off for all
# passes to sidestep the host/sdk mismatch. (iPhoneOS SDK already resolves to
# "no" on its own, so this is a no-op for device builds.)
export ac_cv_func_pipe2=no

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

# --- iOS Simulator Release build (arm64-simulator) ---
make clean
export CFLAGS="-g -O3 -flto=thin ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}"
export LDFLAGS="-g -O3 -flto=thin ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}"
./configure --with-secure-transport --without-openssl \
    --disable-shared --enable-static \
    --disable-ldap --disable-ldaps --disable-dict --disable-telnet --disable-tftp \
    --disable-pop3 --disable-imap --disable-smb --disable-smtp \
    --disable-gopher --disable-rtsp --disable-manual \
    --without-brotli --without-zstd --without-nghttp2 --without-libidn2 --without-libpsl \
    --host=arm-apple-darwin \
    --prefix="${BASE_DEPS_DIR}"
make -j ${NUMCPUS}
cp lib/.libs/libcurl.a ${BASE_DEPS_DIR}/lib-ios-sim/

# --- iOS Simulator Debug build (arm64-simulator) ---
make clean
export CFLAGS="-g ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}"
export LDFLAGS="-g ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}"
./configure --with-secure-transport --without-openssl \
    --disable-shared --enable-static \
    --disable-ldap --disable-ldaps --disable-dict --disable-telnet --disable-tftp \
    --disable-pop3 --disable-imap --disable-smb --disable-smtp \
    --disable-gopher --disable-rtsp --disable-manual \
    --without-brotli --without-zstd --without-nghttp2 --without-libidn2 --without-libpsl \
    --host=arm-apple-darwin \
    --prefix="${BASE_DEPS_DIR}"
make -j ${NUMCPUS}
cp lib/.libs/libcurl.a ${BASE_DEPS_DIR}/libdbg-ios-sim/

# Cleanup
unset CFLAGS
unset LDFLAGS
make clean
git reset --hard
git status --ignored --short . | colrm 1 2 | xargs rm -rf

cd ..
