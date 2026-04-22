#!/bin/bash

# Install ANGLE (Almost Native Graphics Layer Engine) for xLights.
#
# Building ANGLE from source via depot_tools/gn/ninja was unreliable on CI,
# so we download pre-built binaries from jeremyfa/build-angle instead.
#
# Release layout:
#   angle-mac-universal.zip  -> include/, lib/libEGL.dylib, lib/libGLESv2.dylib
#                               (universal x86_64 + arm64)
#   angle-ios-universal.zip  -> include/, libEGL.xcframework, libGLESv2.xcframework
#                               (each xcframework contains ios-arm64 device and
#                                ios-arm64_x86_64-simulator slices)
#
# Installs to:
#   ${BASE_DEPS_DIR}/lib/{libEGL,libGLESv2}.dylib             (macOS release)
#   ${BASE_DEPS_DIR}/libdbg/{libEGL,libGLESv2}.dylib          (macOS debug — same binary)
#   ${BASE_DEPS_DIR}/lib-ios/{libEGL,libGLESv2}.xcframework
#   ${BASE_DEPS_DIR}/libdbg-ios/{libEGL,libGLESv2}.xcframework
#   ${BASE_DEPS_DIR}/include/{EGL,GLES2,GLES3,KHR}/

set -e

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

# Pin to a specific upstream build. Bump this tag to update ANGLE.
ANGLE_TAG="angle-97d33bc"
ANGLE_BASE_URL="https://github.com/jeremyfa/build-angle/releases/download/${ANGLE_TAG}"

CACHE_DIR="${SCRIPT_DIR}/angle-prebuilt/${ANGLE_TAG}"
MAC_ZIP="${CACHE_DIR}/angle-mac-universal.zip"
IOS_ZIP="${CACHE_DIR}/angle-ios-universal.zip"
MAC_EXTRACT="${CACHE_DIR}/mac"
IOS_EXTRACT="${CACHE_DIR}/ios"

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

echo "=== Fetching ANGLE ${ANGLE_TAG} ==="
download "${ANGLE_BASE_URL}/angle-mac-universal.zip" "${MAC_ZIP}"
download "${ANGLE_BASE_URL}/angle-ios-universal.zip" "${IOS_ZIP}"

echo "=== Extracting ==="
rm -rf "${MAC_EXTRACT}" "${IOS_EXTRACT}"
mkdir -p "${MAC_EXTRACT}" "${IOS_EXTRACT}"
unzip -q "${MAC_ZIP}" -d "${MAC_EXTRACT}"
unzip -q "${IOS_ZIP}" -d "${IOS_EXTRACT}"

# --- Patch missing simulator Info.plist ---
# The upstream zip ships the simulator slice of each xcframework *without* an
# Info.plist, which causes Xcode to fail framework embedding with:
#   "Framework ... did not contain an Info.plist"
# Clone the device slice's plist and rewrite the platform-specific keys.
patch_sim_plist() {
    local FW_NAME="$1"
    local DEV_FW="${IOS_EXTRACT}/${FW_NAME}.xcframework/ios-arm64/${FW_NAME}.framework"
    local SIM_FW="${IOS_EXTRACT}/${FW_NAME}.xcframework/ios-arm64_x86_64-simulator/${FW_NAME}.framework"
    local DEV_PLIST="${DEV_FW}/Info.plist"
    local SIM_PLIST="${SIM_FW}/Info.plist"

    if [ -f "${SIM_PLIST}" ]; then
        return 0
    fi
    if [ ! -f "${DEV_PLIST}" ]; then
        echo "WARNING: no device Info.plist template at ${DEV_PLIST}"
        return 1
    fi

    cp "${DEV_PLIST}" "${SIM_PLIST}"
    plutil -replace CFBundleSupportedPlatforms -json '["iPhoneSimulator"]' "${SIM_PLIST}"
    plutil -replace DTPlatformName -string iphonesimulator "${SIM_PLIST}"
    # DTSDKName looks like "iphoneos18.5" — swap the prefix to iphonesimulator.
    local DEV_SDK_NAME
    DEV_SDK_NAME=$(plutil -extract DTSDKName raw "${DEV_PLIST}" 2>/dev/null || echo "iphoneos")
    plutil -replace DTSDKName -string "iphonesimulator${DEV_SDK_NAME#iphoneos}" "${SIM_PLIST}"
    echo "  Synthesized ${SIM_PLIST}"
}
patch_sim_plist libEGL
patch_sim_plist libGLESv2

# --- Patch missing CFBundleShortVersionString ---
# The upstream ANGLE Info.plists ship with CFBundleVersion but no
# CFBundleShortVersionString, which App Store Connect rejects with
# ITMS-90057 when the iPad app that embeds these frameworks is
# submitted. Add the key to every framework slice's Info.plist.
patch_short_version() {
    local FW_NAME="$1"
    for plist in "${IOS_EXTRACT}/${FW_NAME}.xcframework/"*"/${FW_NAME}.framework/Info.plist"; do
        if [ -f "${plist}" ]; then
            plutil -remove CFBundleShortVersionString "${plist}" 2>/dev/null || true
            plutil -insert CFBundleShortVersionString -string "1.0" "${plist}"
            echo "  Added CFBundleShortVersionString to ${plist}"
        fi
    done
}
patch_short_version libEGL
patch_short_version libGLESv2

# --- macOS dylibs (universal x86_64 + arm64) ---
echo "=== Installing macOS dylibs ==="
mkdir -p "${BASE_DEPS_DIR}/lib" "${BASE_DEPS_DIR}/libdbg"
cp "${MAC_EXTRACT}/lib/libEGL.dylib"    "${BASE_DEPS_DIR}/lib/"
cp "${MAC_EXTRACT}/lib/libGLESv2.dylib" "${BASE_DEPS_DIR}/lib/"
# No separate debug build — use the same binaries for libdbg/.
cp "${MAC_EXTRACT}/lib/libEGL.dylib"    "${BASE_DEPS_DIR}/libdbg/"
cp "${MAC_EXTRACT}/lib/libGLESv2.dylib" "${BASE_DEPS_DIR}/libdbg/"

# --- iOS xcframeworks (device + simulator) ---
echo "=== Installing iOS xcframeworks ==="
mkdir -p "${BASE_DEPS_DIR}/lib-ios" "${BASE_DEPS_DIR}/libdbg-ios"
for fw in libEGL.xcframework libGLESv2.xcframework; do
    rm -rf "${BASE_DEPS_DIR}/lib-ios/${fw}"    "${BASE_DEPS_DIR}/libdbg-ios/${fw}"
    cp -R  "${IOS_EXTRACT}/${fw}" "${BASE_DEPS_DIR}/lib-ios/"
    cp -R  "${IOS_EXTRACT}/${fw}" "${BASE_DEPS_DIR}/libdbg-ios/"
done

# --- Headers ---
echo "=== Installing ANGLE headers ==="
mkdir -p "${BASE_DEPS_DIR}/include/EGL" \
         "${BASE_DEPS_DIR}/include/GLES2" \
         "${BASE_DEPS_DIR}/include/GLES3" \
         "${BASE_DEPS_DIR}/include/KHR"
cp "${MAC_EXTRACT}/include/EGL/"*.h    "${BASE_DEPS_DIR}/include/EGL/"
cp "${MAC_EXTRACT}/include/GLES2/"*.h  "${BASE_DEPS_DIR}/include/GLES2/"
cp "${MAC_EXTRACT}/include/GLES3/"*.h  "${BASE_DEPS_DIR}/include/GLES3/"
cp "${MAC_EXTRACT}/include/KHR/"*.h    "${BASE_DEPS_DIR}/include/KHR/"

echo "=== ANGLE ${ANGLE_TAG} install complete ==="
echo "  macOS release: ${BASE_DEPS_DIR}/lib/{libEGL,libGLESv2}.dylib"
echo "  macOS debug:   ${BASE_DEPS_DIR}/libdbg/{libEGL,libGLESv2}.dylib"
echo "  iOS release:   ${BASE_DEPS_DIR}/lib-ios/{libEGL,libGLESv2}.xcframework"
echo "  iOS debug:     ${BASE_DEPS_DIR}/libdbg-ios/{libEGL,libGLESv2}.xcframework"
echo "  Headers:       ${BASE_DEPS_DIR}/include/{EGL,GLES2,GLES3,KHR}/"
