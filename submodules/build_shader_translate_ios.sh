#!/bin/bash
# iOS (device arm64 + simulator arm64) builds of the shader-translation
# toolchain: glslang + SPIRV-Tools + SPIRV-Cross. See build_shader_translate.sh
# for the macOS build and background. Installs into lib-ios/libdbg-ios and
# lib-ios-sim/libdbg-ios-sim.
set -e
. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

# Self-contained: sources come from the submodules (or build_shader_translate.sh's
# clones); glslang's External deps are re-fetched if a prior cleanup removed them.
[ -f glslang/CMakeLists.txt ] || { echo "glslang sources missing (init submodules or run build_shader_translate.sh)"; exit 1; }
[ -d glslang/External/spirv-tools ] || ( cd glslang && python3 update_glslang_sources.py )

LIBS="libglslang.a libSPIRV.a libMachineIndependent.a libGenericCodeGen.a \
      libglslang-default-resource-limits.a libOSDependent.a \
      libSPIRV-Tools-opt.a libSPIRV-Tools.a \
      libspirv-cross-msl.a libspirv-cross-glsl.a libspirv-cross-core.a"

build_variant() {  # $1=tag $2=sysroot("" for device) $3=libtree $4=dbgtree
    local tag="$1" sysroot="$2" libtree="$3" dbgtree="$4"
    local stage="${SCRIPT_DIR}/.shader_translate_stage_ios_${tag}"
    rm -rf "${stage}"
    local common=(
        -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${IOS_MIN_VERSION}"
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5
        -DCMAKE_INSTALL_PREFIX="${stage}" -DBUILD_SHARED_LIBS=OFF
    )
    [ -n "${sysroot}" ] && common+=("-DCMAKE_OSX_SYSROOT=${sysroot}")

    rm -rf "glslang/build-ios-${tag}" "SPIRV-Cross/build-ios-${tag}"
    cmake -S glslang -B "glslang/build-ios-${tag}" "${common[@]}" \
        -DENABLE_OPT=ON -DGLSLANG_TESTS=OFF -DENABLE_GLSLANG_BINARIES=OFF \
        -DGLSLANG_ENABLE_INSTALL=ON -DSPIRV_SKIP_TESTS=ON -DSPIRV_SKIP_EXECUTABLES=ON
    cmake --build "glslang/build-ios-${tag}" -j"${NUMCPUS}" --target install

    cmake -S SPIRV-Cross -B "SPIRV-Cross/build-ios-${tag}" "${common[@]}" \
        -DSPIRV_CROSS_ENABLE_TESTS=OFF -DSPIRV_CROSS_CLI=OFF \
        -DSPIRV_CROSS_STATIC=ON -DSPIRV_CROSS_SHARED=OFF -DSPIRV_CROSS_ENABLE_C_API=ON
    cmake --build "SPIRV-Cross/build-ios-${tag}" -j"${NUMCPUS}" --target install

    for l in ${LIBS}; do
        cp "${stage}/lib/${l}" "${BASE_DEPS_DIR}/${libtree}/${l}"
        cp "${stage}/lib/${l}" "${BASE_DEPS_DIR}/${dbgtree}/${l}"
    done
    rm -rf "${stage}"
    echo "shader-translate iOS ${tag} installed."
}

build_variant device ""               lib-ios     libdbg-ios
build_variant sim    iphonesimulator  lib-ios-sim libdbg-ios-sim

# Leave the checkouts pristine so the parent repo's git status stays clean.
( cd glslang     && git clean -dffx -q )
( cd SPIRV-Cross && git clean -dffx -q )
