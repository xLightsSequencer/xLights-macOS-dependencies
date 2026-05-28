#!/bin/bash

# Install KLightMapper.xcframework for the xLights iPad app.
#
# KLightMapper is the closed-source camera-based light-mapping engine.
# Its source lives in a private repo; only the prebuilt XCFramework is
# published — to GitHub releases on KulpLights/KLightMapper — by that
# repo's CI. We just download the pinned release and stage it next to
# the other iOS frameworks (same model as build_angle.sh).
#
# Release asset layout:
#   KLightMapper.xcframework.zip -> KLightMapper.xcframework
#       (ios-arm64 device + ios-arm64_x86_64-simulator slices, each
#        with its .swiftmodule + Info.plist already in place)
#
# Installs to:
#   ${BASE_DEPS_DIR}/lib-ios/KLightMapper.xcframework         (real copy)
#   ${BASE_DEPS_DIR}/libdbg-ios/KLightMapper.xcframework      (symlink)
#   ${BASE_DEPS_DIR}/lib-ios-sim/KLightMapper.xcframework     (symlink)
#   ${BASE_DEPS_DIR}/libdbg-ios-sim/KLightMapper.xcframework  (symlink)
#   ${BASE_DEPS_DIR}/lib/KLightMapper.xcframework             (symlink — macOS rel)
#   ${BASE_DEPS_DIR}/libdbg/KLightMapper.xcframework          (symlink — macOS dbg)
#
# The xcframework bundles macOS + iOS device + iOS simulator slices in
# one artifact, so a single 62MB copy is shared via relative symlinks
# across all six search paths the xLights Xcode projects look at.

set -e

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

# Pin to a published release. Bump this tag to update KLightMapper —
# it must correspond to a release in KulpLights/KLightMapper. For a
# dev build against the rolling pre-release, override on the command
# line:  KLM_TAG=latest-build ./build_klightmapper.sh
KLM_TAG="${KLM_TAG:-v1.2.0}"
KLM_BASE_URL="https://github.com/KulpLights/KLightMapper/releases/download/${KLM_TAG}"

CACHE_DIR="${SCRIPT_DIR}/klightmapper-prebuilt/${KLM_TAG}"
ZIP="${CACHE_DIR}/KLightMapper.xcframework.zip"
EXTRACT="${CACHE_DIR}/extract"

mkdir -p "${CACHE_DIR}"

download() {
    local url="$1"
    local dest="$2"
    if [ -f "${dest}" ]; then
        echo "  Using cached $(basename "${dest}")"
    else
        echo "  Downloading $(basename "${dest}")"
        curl -L --fail --retry 3 -o "${dest}.part" "${url}"
        mv "${dest}.part" "${dest}"
    fi
}

echo "=== Fetching KLightMapper ${KLM_TAG} ==="
download "${KLM_BASE_URL}/KLightMapper.xcframework.zip" "${ZIP}"

echo "=== Extracting ==="
rm -rf "${EXTRACT}"
mkdir -p "${EXTRACT}"
unzip -q "${ZIP}" -d "${EXTRACT}"

FW_SRC="${EXTRACT}/KLightMapper.xcframework"
if [ ! -d "${FW_SRC}" ]; then
    echo "ERROR: ${FW_SRC} not found after extracting ${ZIP}" >&2
    exit 1
fi

echo "=== Installing xcframework ==="
# One real copy in lib-ios/, relative symlinks in the other five search
# paths. rm -rf on a symlink removes the link only, not the target.
PRIMARY="${BASE_DEPS_DIR}/lib-ios"
mkdir -p "${PRIMARY}"
rm -rf "${PRIMARY}/KLightMapper.xcframework"
cp -R "${FW_SRC}" "${PRIMARY}/"

for dest in \
    "${BASE_DEPS_DIR}/libdbg-ios" \
    "${BASE_DEPS_DIR}/lib-ios-sim" \
    "${BASE_DEPS_DIR}/libdbg-ios-sim" \
    "${BASE_DEPS_DIR}/lib" \
    "${BASE_DEPS_DIR}/libdbg"; do
    mkdir -p "${dest}"
    rm -rf "${dest}/KLightMapper.xcframework"
    ln -s "../lib-ios/KLightMapper.xcframework" "${dest}/KLightMapper.xcframework"
done

echo "=== KLightMapper ${KLM_TAG} install complete ==="
echo "  Primary:        ${PRIMARY}/KLightMapper.xcframework"
echo "  Symlinked from: libdbg-ios, lib-ios-sim, libdbg-ios-sim, lib, libdbg"
