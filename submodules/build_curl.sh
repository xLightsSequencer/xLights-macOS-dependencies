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

# TLS: OpenSSL, with certificate verification delegated to Apple SecTrust.
#
# This replaced SecureTransport, which can never do TLS 1.3 - curl's sectransp
# backend silently downgrades the request:
#
#     case CURL_SSLVERSION_MAX_TLSv1_3:
#     case CURL_SSLVERSION_MAX_TLSv1_2:
#       ver_max = kTLSProtocol12;
#
# and Apple never added it. curl removed the backend outright in 8.15.0, which
# is what previously capped the pin at 8.14.x.
#
# --with-apple-sectrust is the part that makes this a clean swap rather than a
# downgrade: certificates are still verified against the OS keychain, so there
# is no CA bundle to ship or keep current. curl wires SecTrust into openssl.c
# and gtls.c ONLY - mbedTLS or wolfSSL would have forced a bundled CA store.
# It requires curl >= 8.18.
#
# Note there is no --without-secure-transport here: the option no longer
# exists in 8.21, because the backend it referred to is gone. Passing it only
# produced "configure: WARNING: unrecognized options".
CURL_TLS_OPTS=(
  --with-openssl="${BASE_DEPS_DIR}"
  --with-apple-sectrust
)

# --- Release build (universal) ---
export CFLAGS="-g -O3 -flto=thin ${XL_TARGETS} ${OSX_VERSION_MIN}"
export LDFLAGS="-g -O3 -flto=thin ${XL_TARGETS} ${OSX_VERSION_MIN}"
./configure "${CURL_TLS_OPTS[@]}" \
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
./configure "${CURL_TLS_OPTS[@]}" \
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
