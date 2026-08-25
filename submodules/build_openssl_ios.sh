#!/bin/bash
#
# build_openssl_ios.sh - iOS (device arm64 + simulator arm64) static OpenSSL.
#
# Companion to build_openssl.sh; see that script for why OpenSSL is here at all
# (TLS 1.3, which Apple's SecureTransport can never provide, plus Apple SecTrust
# so certificate trust still comes from the OS keychain).
#
# OpenSSL builds one architecture per pass and the device and simulator triples
# are distinct even at the same arch, so they cannot be lipo'd together - they
# install into parallel lib-ios / lib-ios-sim trees, matching how the other iOS
# dependencies here are laid out.
set -e
. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )
STAGE="${SCRIPT_DIR}/.openssl_ios_stage"

rm -rf "${STAGE}"
mkdir -p "${STAGE}"

cd openssl

COMMON_OPTS=(
  no-shared no-tests no-docs no-legacy
  no-ssl3 no-comp no-dtls no-weak-ssl-ciphers
)

build_variant() {   # $1=tag  $2=openssl target  $3=version-min flag  $4=libtree  $5=dbgtree
    local tag="$1" target="$2" vermin="$3" libtree="$4" dbgtree="$5"
    echo "==> openssl ios (${tag})"
    make clean >/dev/null 2>&1 || true
    git clean -dffxq . 2>/dev/null || true

    # The xcrun-based targets pick the SDK themselves but set no deployment
    # target, so pass it explicitly to match the rest of the bundle.
    ./Configure "${target}" "${COMMON_OPTS[@]}" "${vermin}" \
        --prefix="${STAGE}/${tag}" --openssldir="${STAGE}/${tag}/ssl"
    make -j "${NUMCPUS}" build_libs

    mkdir -p "${BASE_DEPS_DIR}/${libtree}" "${BASE_DEPS_DIR}/${dbgtree}"
    cp libcrypto.a libssl.a "${BASE_DEPS_DIR}/${libtree}/"
    # As on macOS, the debug tree links the same static libraries: OpenSSL is
    # not something we step through, and a separate build would double an
    # already long step.
    cp libcrypto.a libssl.a "${BASE_DEPS_DIR}/${dbgtree}/"

    mkdir -p "${STAGE}/${tag}/include"
    cp -R include/openssl "${STAGE}/${tag}/include/"
}

build_variant device    ios64-xcrun              "${IOS_VERSION_MIN}"     lib-ios     libdbg-ios
build_variant simulator iossimulator-arm64-xcrun "${IOS_SIM_VERSION_MIN}" lib-ios-sim libdbg-ios-sim

# This repo ships ONE include/ tree shared by the macOS and iOS builds, which is
# only correct if the generated, configuration-dependent header agrees across
# them. Check rather than assume - installing a header that describes a
# different configuration than the library is exactly the mismatch this bundle
# exists to prevent.
MAC_CONF="${BASE_DEPS_DIR}/include/openssl/opensslconf.h"
if [ -f "${MAC_CONF}" ]; then
    for tag in device simulator; do
        if ! diff -q "${MAC_CONF}" "${STAGE}/${tag}/include/openssl/opensslconf.h" >/dev/null; then
            echo "build_openssl_ios: opensslconf.h for ${tag} differs from the macOS copy;" \
                 "a single shared include/ tree would describe the wrong configuration" >&2
            diff "${MAC_CONF}" "${STAGE}/${tag}/include/openssl/opensslconf.h" >&2 || true
            exit 1
        fi
    done
    echo "    opensslconf.h matches the macOS build; shared include/ is correct"
else
    echo "build_openssl_ios: macOS OpenSSL headers not present - build_openssl.sh must run first" >&2
    exit 1
fi

rm -rf "${STAGE}"
make clean >/dev/null 2>&1 || true
git clean -dffxq . 2>/dev/null || true

echo "==> openssl ios done"
cd ..
