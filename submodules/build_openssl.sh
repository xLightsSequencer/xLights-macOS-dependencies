#!/bin/bash
#
# build_openssl.sh - macOS universal (x86_64 + arm64) static OpenSSL.
#
# Exists so curl can offer TLS 1.3. Apple's SecureTransport never gained it -
# curl's sectransp backend silently downgrades a TLS 1.3 request:
#
#     case CURL_SSLVERSION_MAX_TLSv1_3:
#     case CURL_SSLVERSION_MAX_TLSv1_2:
#       ver_max = kTLSProtocol12;
#
# so no curl version can reach 1.3 while that backend is in use. Apple removed
# SecureTransport from curl entirely in 8.15.0, which also capped how far the
# curl pin could move.
#
# OpenSSL rather than mbedTLS or wolfSSL specifically because curl wires Apple
# SecTrust into openssl.c and gtls.c ONLY. With OpenSSL we get TLS 1.3 and keep
# certificate trust in the OS keychain (--with-apple-sectrust); with mbedTLS we
# would have to ship and maintain a CA bundle. GnuTLS is wired up too but is
# LGPL with heavier dependencies. OpenSSL 3.x is Apache-2.0, which is clean for
# App Store distribution.
#
# OpenSSL cannot build multiple architectures in one pass, so each arch is
# configured and built separately and then lipo'd, the same shape as ffmpeg.
set -e
. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )
STAGE="${SCRIPT_DIR}/.openssl_stage"

rm -rf "${STAGE}"
mkdir -p "${STAGE}"

cd openssl

# Common configure flags. no-shared keeps it static like everything else here;
# the no-* options drop pieces nothing in this bundle uses and cut build time
# substantially.
COMMON_OPTS=(
  no-shared no-tests no-docs no-legacy
  no-ssl3 no-comp no-dtls no-weak-ssl-ciphers
)

build_arch() {   # $1 = openssl target, $2 = -arch flag, $3 = output subdir
    local target="$1" arch="$2" out="$3"
    echo "==> openssl ${out}"
    make clean >/dev/null 2>&1 || true
    git clean -dffxq . 2>/dev/null || true

    ./Configure "${target}" "${COMMON_OPTS[@]}" \
        "-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}" \
        --prefix="${STAGE}/${out}" --openssldir="${STAGE}/${out}/ssl"
    make -j "${NUMCPUS}" build_libs
    mkdir -p "${STAGE}/${out}"
    cp libcrypto.a libssl.a "${STAGE}/${out}/"
    # Keep this arch's generated headers; they are configuration-dependent.
    mkdir -p "${STAGE}/${out}/include"
    cp -R include/openssl "${STAGE}/${out}/include/"
}

build_arch darwin64-x86_64-cc "-arch x86_64" x86_64
build_arch darwin64-arm64-cc  "-arch arm64"  arm64

echo "==> openssl: creating universal libraries"
lipo -create -output "${BASE_DEPS_DIR}/lib/libcrypto.a" \
     "${STAGE}/x86_64/libcrypto.a" "${STAGE}/arm64/libcrypto.a"
lipo -create -output "${BASE_DEPS_DIR}/lib/libssl.a" \
     "${STAGE}/x86_64/libssl.a" "${STAGE}/arm64/libssl.a"

# OpenSSL generates opensslconf.h per configuration. If the two architectures
# disagree, a single copy would be wrong for one of them - so check rather than
# assume, and fail loudly if it ever stops being true.
if ! diff -q "${STAGE}/x86_64/include/openssl/opensslconf.h" \
             "${STAGE}/arm64/include/openssl/opensslconf.h" >/dev/null; then
    echo "build_openssl: opensslconf.h differs between architectures;" \
         "a single universal copy would be wrong for one of them" >&2
    diff "${STAGE}/x86_64/include/openssl/opensslconf.h" \
         "${STAGE}/arm64/include/openssl/opensslconf.h" >&2 || true
    exit 1
fi
cp -R "${STAGE}/arm64/include/openssl" "${BASE_DEPS_DIR}/include/"

# The debug tree links the same static libraries; OpenSSL is not something we
# step through, and a separate build would double an already long step.
cp -f "${BASE_DEPS_DIR}/lib/libcrypto.a" "${BASE_DEPS_DIR}/libdbg/libcrypto.a"
cp -f "${BASE_DEPS_DIR}/lib/libssl.a"    "${BASE_DEPS_DIR}/libdbg/libssl.a"

rm -rf "${STAGE}"
make clean >/dev/null 2>&1 || true
git clean -dffxq . 2>/dev/null || true

echo "==> openssl done ($(lipo -archs ${BASE_DEPS_DIR}/lib/libssl.a))"
cd ..
