#!/bin/bash

# Fail loudly. Every step below is piped through `tee`, which means the
# pipeline's exit status is tee's (always 0) - so without pipefail a step that
# dies, or a build script that is missing entirely, leaves this script exiting
# 0 and CI reporting success. run_step checks the real status via PIPESTATUS
# and collects failures so one broken library does not hide the rest.
set -o pipefail

XL_FAILED=()

run_step() {            # run_step <label> <command...>
    local label="$1"; shift
    echo "==> ${label}"
    "$@" 2>&1 | tee "./build_${label}.log"
    local rc=${PIPESTATUS[0]}
    if [ "${rc}" -ne 0 ]; then
        echo "!!! ${label} FAILED (rc=${rc})"
        XL_FAILED+=("${label}")
    fi
}


. ./env.sh


BASE_DEPS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

echo "Base Dir:  ${BASE_DEPS_DIR}"

sysctl -a | grep hw.perflevel


# Prune the output tree first. It is otherwise never cleaned, so headers that
# move or get renamed between versions linger and can shadow the current ones -
# a stale FFmpeg 6 header sitting beside an 8.x library, for instance, which is
# the exact mismatch this bundle exists to prevent. build.sh always rebuilds
# everything, so nothing is lost.
rm -rf ${BASE_DEPS_DIR}/lib ${BASE_DEPS_DIR}/libdbg ${BASE_DEPS_DIR}/include \
       ${BASE_DEPS_DIR}/bin ${BASE_DEPS_DIR}/share

mkdir -p ${BASE_DEPS_DIR}/lib
mkdir -p ${BASE_DEPS_DIR}/libdbg
mkdir -p ${BASE_DEPS_DIR}/lib-ios
mkdir -p ${BASE_DEPS_DIR}/libdbg-ios
mkdir -p ${BASE_DEPS_DIR}/lib-ios-sim
mkdir -p ${BASE_DEPS_DIR}/libdbg-ios-sim
mkdir -p ${BASE_DEPS_DIR}/bin
mkdir -p ${BASE_DEPS_DIR}/share
mkdir -p ${BASE_DEPS_DIR}/include

git submodule update --init --force


cd submodules

run_step wxwidgets ./build_wxwidgets.sh

run_step zstd ./build_zstd.sh

run_step liquidfun ./build_liquidfun.sh

run_step sdl ./build_sdl.sh

run_step lua ./build_lua.sh

run_step minizip ./build_minizip.sh

run_step libxlswriter ./build_libxlswriter.sh

run_step hidapi ./build_hidapi.sh

run_step ffmpeg ./build_ffmpeg.sh

run_step openssl ./build_openssl.sh

run_step curl ./build_curl.sh

run_step ispc ./install_ispc.sh

run_step shader_translate ./build_shader_translate.sh

# --- iOS builds (arm64 only, libraries needed for iPad app) ---
run_step zstd_ios ./build_zstd_ios.sh
run_step liquidfun_ios ./build_liquidfun_ios.sh
run_step lua_ios ./build_lua_ios.sh
run_step minizip_ios ./build_minizip_ios.sh
run_step libxlswriter_ios ./build_libxlswriter_ios.sh
run_step openssl_ios ./build_openssl_ios.sh
run_step curl_ios ./build_curl_ios.sh
run_step shader_translate_ios ./build_shader_translate_ios.sh

cd ..

# --- make relocatable -------------------------------------------------------
# wx debug dylibs are installed with an absolute install name taken from
# configure's --prefix, i.e. this machine's path. Rewrite them to @rpath here so
# the published bundle works wherever it is unpacked, instead of every consumer
# patching it with install_name_tool at its own build time.
run_step relocatable "${BASE_DEPS_DIR}/make_relocatable.sh" "${BASE_DEPS_DIR}"

# --- verify -----------------------------------------------------------------
# Exit codes alone are not enough: a build script can return 0 having produced
# nothing. Check the expected libraries are actually present before packaging,
# so a silently partial bundle cannot be published.
#
# This is a representative set, not an exhaustive one - every non-wx library,
# plus two wx libraries as a sanity check on that build. The wx entries carry
# the version in their name, so a wxWidgets major/minor bump will trip this
# deliberately: that is a change worth noticing rather than absorbing.
#
# libpostproc is deliberately absent - it was removed from FFmpeg in 8.x.
XL_EXPECTED_LIBS="libavcodec.a libavdevice.a libavfilter.a libavformat.a \
libavutil.a libswresample.a libswscale.a libcurl.a libhidapi.a libliquidfun.a \
liblua.a libSDL2.a libxlsxwriter.a libminizip.a libzstd.a libssl.a libcrypto.a \
libglslang.a libSPIRV.a \
libSPIRV-Tools.a libSPIRV-Tools-opt.a libMachineIndependent.a \
libGenericCodeGen.a libOSDependent.a libglslang-default-resource-limits.a \
libspirv-cross-core.a libspirv-cross-glsl.a libspirv-cross-msl.a \
libwx_baseu-3.3.a libwx_osx_cocoau_core-3.3.a"

XL_MISSING=()
for _lib in ${XL_EXPECTED_LIBS}; do
    [ -f "${BASE_DEPS_DIR}/lib/${_lib}" ] || XL_MISSING+=("lib/${_lib}")
done
if [ ${#XL_MISSING[@]} -gt 0 ]; then
    echo "build.sh: bundle is missing expected libraries: ${XL_MISSING[*]}"
    XL_FAILED+=("verify")
fi

# Existence is still not usability: check the bundle survives being moved and
# can actually be linked and run against.
run_step usable "${BASE_DEPS_DIR}/verify_bundle.sh" "${BASE_DEPS_DIR}"

if [ ${#XL_FAILED[@]} -gt 0 ]; then
    echo ""
    echo "build.sh: FAILED steps: ${XL_FAILED[*]}"
    exit 1
fi
echo "build.sh: all steps succeeded, all expected libraries are present, and the bundle is relocatable."

rm -rf output
mkdir -p output


# The archive's top-level directory name and the published asset name are part
# of the contract with consumers, NOT cosmetic. xLights' download_deps fetches
# "xLights-macOS-dependencies.tar.zst" and then does
#
#     mv xLights-macOS-dependencies xLights-macOS-dependencies-${TAG}
#
# so renaming either would break every existing checkout. They therefore stay
# fixed even though this repo is no longer named that - do not "tidy" them to
# match the repository.
#
# What must NOT be hardcoded is the directory being archived: that is the
# checkout name, which the repository rename changed. Derive it, and use tar's
# -s substitution to present it under the name consumers expect.
ARCHIVE_NAME="xLights-macOS-dependencies"
CHECKOUT_NAME=$( basename "${BASE_DEPS_DIR}" )

cd ..

tar  --exclude-vcs --exclude submodules --exclude .github --exclude build.sh --exclude env.sh --exclude output \
     -s "|^${CHECKOUT_NAME}|${ARCHIVE_NAME}|" \
     -c "${CHECKOUT_NAME}" \
  | zstd -18 -T0 -f -o "${CHECKOUT_NAME}/output/${ARCHIVE_NAME}.tar.zst"
