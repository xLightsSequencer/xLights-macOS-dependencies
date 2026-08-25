#!/bin/bash
#
# build_curl_ios.sh - iOS (device + simulator, release + debug) static curl.
#
# TLS is OpenSSL with certificate verification delegated to Apple SecTrust.
# See build_openssl.sh for why: SecureTransport can never negotiate TLS 1.3
# (curl's sectransp backend downgrades the request to 1.2), and curl removed
# that backend entirely in 8.15.0. --with-apple-sectrust keeps trust in the OS
# keychain so there is no CA bundle to ship; curl wires SecTrust into openssl.c
# and gtls.c only, which is why OpenSSL rather than mbedTLS.
set -e
. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )
SSL_STAGE="${SCRIPT_DIR}/.curl_ssl_stage"

rm -rf "${SSL_STAGE}"

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

# curl expects an OpenSSL prefix laid out as <prefix>/lib and <prefix>/include.
# The bundle stores iOS libraries in parallel lib-ios / lib-ios-sim trees with a
# single shared include/, so assemble a small prefix per variant rather than
# reshaping the bundle.
stage_openssl() {   # $1 = tag, $2 = source lib tree
    local tag="$1" libtree="$2"
    local dir="${SSL_STAGE}/${tag}"
    mkdir -p "${dir}/lib" "${dir}/include"
    cp "${BASE_DEPS_DIR}/${libtree}/libssl.a" "${BASE_DEPS_DIR}/${libtree}/libcrypto.a" "${dir}/lib/"
    cp -R "${BASE_DEPS_DIR}/include/openssl" "${dir}/include/"
    echo "${dir}"
}

build_variant() {   # $1=label  $2=cflags  $3=openssl-prefix  $4=destination lib tree
    local label="$1" flags="$2" sslprefix="$3" dest="$4"
    echo "==> curl ios (${label})"
    make clean >/dev/null 2>&1 || true
    export CFLAGS="${flags}"
    export LDFLAGS="${flags}"
    ./configure \
        --with-openssl="${sslprefix}" --with-apple-sectrust \
        --disable-shared --enable-static \
        --disable-ldap --disable-ldaps --disable-dict --disable-telnet --disable-tftp \
        --disable-pop3 --disable-imap --disable-smb --disable-smtp \
        --disable-gopher --disable-rtsp --disable-manual \
        --without-brotli --without-zstd --without-nghttp2 --without-libidn2 --without-libpsl \
        --host=arm-apple-darwin \
        --prefix="${BASE_DEPS_DIR}"
    make -j "${NUMCPUS}"
    mkdir -p "${BASE_DEPS_DIR}/${dest}"
    cp lib/.libs/libcurl.a "${BASE_DEPS_DIR}/${dest}/"
}

DEVICE_SSL=$(stage_openssl device    lib-ios)
SIM_SSL=$(stage_openssl    simulator lib-ios-sim)

build_variant "device release"    "-g -O3 -flto=thin ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"         "${DEVICE_SSL}" lib-ios
build_variant "device debug"      "-g ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"                        "${DEVICE_SSL}" libdbg-ios
build_variant "simulator release" "-g -O3 -flto=thin ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}" "${SIM_SSL}"    lib-ios-sim
build_variant "simulator debug"   "-g ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}"                "${SIM_SSL}"    libdbg-ios-sim

# Cleanup
unset CFLAGS
unset LDFLAGS
rm -rf "${SSL_STAGE}"
make clean
git reset --hard
git status --ignored --short . | colrm 1 2 | xargs rm -rf

echo "==> curl ios done"
cd ..
