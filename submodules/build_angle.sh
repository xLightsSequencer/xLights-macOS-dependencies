#!/bin/bash

# Build ANGLE (Almost Native Graphics Layer Engine) with Metal backend
# Produces static libANGLE_egl.a and libANGLE_glesv2.a for macOS (universal) and iOS (arm64)
#
# ANGLE requires Google's depot_tools (gn, ninja, gclient).
# First-time setup is slow (~2GB download for deps).

set -e

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

# --- Install/update depot_tools ---
if [ ! -d "depot_tools" ]; then
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
else
    cd depot_tools
    git pull --rebase || true
    cd ..
fi
export PATH="${SCRIPT_DIR}/depot_tools:$PATH"

# --- Fetch ANGLE source + dependencies ---
if [ ! -d "angle" ]; then
    mkdir -p angle
    cd angle
    fetch --no-history angle
    cd ..
else
    cd angle
    git pull --rebase || true
    gclient sync --no-history
    cd ..
fi

cd angle

# Common GN args for Metal-only static build
COMMON_GN_ARGS='
is_debug = false
is_component_build = false
angle_build_all = false
angle_build_tests = false
angle_enable_metal = true
angle_enable_vulkan = false
angle_enable_gl = false
angle_enable_gl_desktop_backend = false
angle_enable_d3d9 = false
angle_enable_d3d11 = false
angle_enable_null = false
angle_enable_swiftshader = false
angle_enable_wgpu = false
angle_enable_abseil = false
angle_has_histograms = false
use_custom_libcxx = false
'

# Helper: collect all .a files from a build dir and merge into two consumer libraries
# Usage: merge_angle_libs <build_obj_dir> <output_dir>
merge_angle_libs() {
    local BUILD_OBJ_DIR="$1"
    local OUTPUT_DIR="$2"
    mkdir -p "${OUTPUT_DIR}"

    # Find ALL static libs produced by the build
    local ALL_LIBS
    ALL_LIBS=$(find "${BUILD_OBJ_DIR}" -name "*.a" 2>/dev/null)
    if [ -z "$ALL_LIBS" ]; then
        echo "WARNING: No .a files found in ${BUILD_OBJ_DIR}"
        return 1
    fi

    # Separate EGL from the rest
    local EGL_LIB
    EGL_LIB=$(echo "$ALL_LIBS" | grep "libEGL_static\.a" | head -1)
    local GLESV2_LIBS
    GLESV2_LIBS=$(echo "$ALL_LIBS" | grep -v "libEGL_static\.a")

    # Merge all non-EGL libs into a single libANGLE_glesv2.a
    if [ -n "$GLESV2_LIBS" ]; then
        # shellcheck disable=SC2086
        libtool -static -o "${OUTPUT_DIR}/libANGLE_glesv2.a" $GLESV2_LIBS
        echo "  Created ${OUTPUT_DIR}/libANGLE_glesv2.a"
    fi

    # Copy EGL as libANGLE_egl.a
    if [ -n "$EGL_LIB" ]; then
        cp "$EGL_LIB" "${OUTPUT_DIR}/libANGLE_egl.a"
        echo "  Created ${OUTPUT_DIR}/libANGLE_egl.a"
    fi
}

# --- macOS arm64 Release ---
echo "=== Building ANGLE for macOS arm64 ==="
gn gen out/macos-arm64 --args="
${COMMON_GN_ARGS}
target_os = \"mac\"
target_cpu = \"arm64\"
mac_deployment_target = \"${MACOSX_DEPLOYMENT_TARGET}\"
"
autoninja -C out/macos-arm64 angle_static

# --- macOS x86_64 Release ---
echo "=== Building ANGLE for macOS x86_64 ==="
gn gen out/macos-x64 --args="
${COMMON_GN_ARGS}
target_os = \"mac\"
target_cpu = \"x64\"
mac_deployment_target = \"${MACOSX_DEPLOYMENT_TARGET}\"
"
autoninja -C out/macos-x64 angle_static

# --- Create universal macOS static libraries ---
echo "=== Creating universal macOS libraries ==="
mkdir -p out/macos-universal

# Find all .a names from the arm64 build and lipo them with x64 counterparts
while IFS= read -r ARM64_LIB; do
    LIB_NAME=$(basename "$ARM64_LIB")
    # Find the matching x64 lib by name
    X64_LIB=$(find out/macos-x64/obj -name "$LIB_NAME" 2>/dev/null | head -1)
    if [ -n "$X64_LIB" ]; then
        lipo -create "$ARM64_LIB" "$X64_LIB" -output "out/macos-universal/${LIB_NAME}"
        echo "  Created universal ${LIB_NAME}"
    else
        cp "$ARM64_LIB" "out/macos-universal/${LIB_NAME}"
        echo "  Copied arm64-only ${LIB_NAME}"
    fi
done < <(find out/macos-arm64/obj -name "*.a" 2>/dev/null)

# Merge universal libs into consumer-facing libraries
EGL_LIB=$(find out/macos-universal -name "libEGL_static.a" 2>/dev/null | head -1)
GLESV2_LIBS=$(find out/macos-universal -name "*.a" ! -name "libEGL_static.a" ! -name "libANGLE_egl.a" ! -name "libANGLE_glesv2.a" 2>/dev/null)
if [ -n "$GLESV2_LIBS" ]; then
    # shellcheck disable=SC2086
    libtool -static -o out/macos-universal/libANGLE_glesv2.a $GLESV2_LIBS
fi
if [ -n "$EGL_LIB" ]; then
    cp "$EGL_LIB" out/macos-universal/libANGLE_egl.a
fi

# Install macOS release to deps directory
cp out/macos-universal/libANGLE_glesv2.a "${BASE_DEPS_DIR}/lib/"
cp out/macos-universal/libANGLE_egl.a "${BASE_DEPS_DIR}/lib/"

# --- macOS Debug build (arm64 only for speed) ---
echo "=== Building ANGLE for macOS arm64 Debug ==="
gn gen out/macos-arm64-dbg --args="
${COMMON_GN_ARGS}
is_debug = true
target_os = \"mac\"
target_cpu = \"arm64\"
mac_deployment_target = \"${MACOSX_DEPLOYMENT_TARGET}\"
"
autoninja -C out/macos-arm64-dbg angle_static
merge_angle_libs out/macos-arm64-dbg/obj out/macos-debug

cp out/macos-debug/libANGLE_glesv2.a "${BASE_DEPS_DIR}/libdbg/"
cp out/macos-debug/libANGLE_egl.a "${BASE_DEPS_DIR}/libdbg/"

# --- iOS arm64 Release ---
echo "=== Building ANGLE for iOS arm64 ==="
gn gen out/ios-arm64 --args="
${COMMON_GN_ARGS}
target_os = \"ios\"
target_cpu = \"arm64\"
target_environment = \"device\"
ios_deployment_target = \"${IOS_MIN_VERSION}\"
"
autoninja -C out/ios-arm64 angle_static
merge_angle_libs out/ios-arm64/obj out/ios-release

cp out/ios-release/libANGLE_glesv2.a "${BASE_DEPS_DIR}/lib-ios/"
cp out/ios-release/libANGLE_egl.a "${BASE_DEPS_DIR}/lib-ios/"

# --- iOS arm64 Debug ---
echo "=== Building ANGLE for iOS arm64 Debug ==="
gn gen out/ios-arm64-dbg --args="
${COMMON_GN_ARGS}
is_debug = true
target_os = \"ios\"
target_cpu = \"arm64\"
target_environment = \"device\"
ios_deployment_target = \"${IOS_MIN_VERSION}\"
"
autoninja -C out/ios-arm64-dbg angle_static
merge_angle_libs out/ios-arm64-dbg/obj out/ios-debug

cp out/ios-debug/libANGLE_glesv2.a "${BASE_DEPS_DIR}/libdbg-ios/"
cp out/ios-debug/libANGLE_egl.a "${BASE_DEPS_DIR}/libdbg-ios/"

# --- Install headers ---
echo "=== Installing ANGLE headers ==="
mkdir -p "${BASE_DEPS_DIR}/include/EGL"
mkdir -p "${BASE_DEPS_DIR}/include/GLES2"
mkdir -p "${BASE_DEPS_DIR}/include/GLES3"
mkdir -p "${BASE_DEPS_DIR}/include/KHR"
mkdir -p "${BASE_DEPS_DIR}/include/ANGLE"

cp include/EGL/egl.h "${BASE_DEPS_DIR}/include/EGL/"
cp include/EGL/eglext.h "${BASE_DEPS_DIR}/include/EGL/"
cp include/EGL/eglext_angle.h "${BASE_DEPS_DIR}/include/EGL/"
cp include/EGL/eglplatform.h "${BASE_DEPS_DIR}/include/EGL/"
cp include/GLES2/gl2.h "${BASE_DEPS_DIR}/include/GLES2/"
cp include/GLES2/gl2ext.h "${BASE_DEPS_DIR}/include/GLES2/"
cp include/GLES2/gl2ext_angle.h "${BASE_DEPS_DIR}/include/GLES2/"
cp include/GLES2/gl2platform.h "${BASE_DEPS_DIR}/include/GLES2/"
cp include/GLES3/gl3.h "${BASE_DEPS_DIR}/include/GLES3/"
cp include/GLES3/gl31.h "${BASE_DEPS_DIR}/include/GLES3/"
cp include/GLES3/gl32.h "${BASE_DEPS_DIR}/include/GLES3/"
cp include/GLES3/gl3platform.h "${BASE_DEPS_DIR}/include/GLES3/"
cp include/KHR/khrplatform.h "${BASE_DEPS_DIR}/include/KHR/"
cp include/angle_gl.h "${BASE_DEPS_DIR}/include/ANGLE/"
cp include/export.h "${BASE_DEPS_DIR}/include/ANGLE/"

cd ..

echo "=== ANGLE build complete ==="
echo "Libraries installed to:"
echo "  macOS release: ${BASE_DEPS_DIR}/lib/libANGLE_egl.a, libANGLE_glesv2.a"
echo "  macOS debug:   ${BASE_DEPS_DIR}/libdbg/libANGLE_egl.a, libANGLE_glesv2.a"
echo "  iOS release:   ${BASE_DEPS_DIR}/lib-ios/libANGLE_egl.a, libANGLE_glesv2.a"
echo "  iOS debug:     ${BASE_DEPS_DIR}/libdbg-ios/libANGLE_egl.a, libANGLE_glesv2.a"
echo "Headers installed to: ${BASE_DEPS_DIR}/include/{EGL,GLES2,GLES3,KHR,ANGLE}"
