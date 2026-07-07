#!/bin/bash
# Builds the runtime shader-translation toolchain used by the native Metal (and
# future Vulkan) Shader effect path: glslang (GLSL->SPIR-V) + SPIRV-Tools
# (spirv-opt: merge-return + inline) + SPIRV-Cross (SPIR-V->MSL). Produces
# universal (arm64+x86_64) static libs into lib/ (+ libdbg/) and headers into
# include/{glslang,spirv-tools,spirv_cross}. Runtime, in-app translation (user
# shaders are arbitrary/downloaded), same pipeline ISFMSLKit uses.
set -e
. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )
STAGE="${SCRIPT_DIR}/.shader_translate_stage"
rm -rf "${STAGE}"; mkdir -p "${STAGE}"

# glslang carries version-matched SPIRV-Tools + SPIRV-Headers via its updater
# (fetched into glslang/External each run; cleaned up below).
[ -f glslang/CMakeLists.txt ]     || git clone --depth 1 https://github.com/KhronosGroup/glslang.git
[ -f SPIRV-Cross/CMakeLists.txt ] || git clone --depth 1 https://github.com/KhronosGroup/SPIRV-Cross.git
( cd glslang && python3 update_glslang_sources.py )

COMMON=(
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET}"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  -DCMAKE_INSTALL_PREFIX="${STAGE}"
  -DBUILD_SHARED_LIBS=OFF
)

cmake -S glslang -B glslang/build "${COMMON[@]}" \
  -DENABLE_OPT=ON -DGLSLANG_TESTS=OFF -DENABLE_GLSLANG_BINARIES=OFF \
  -DGLSLANG_ENABLE_INSTALL=ON -DSPIRV_SKIP_TESTS=ON -DSPIRV_SKIP_EXECUTABLES=ON
cmake --build glslang/build -j"${NUMCPUS}" --target install

cmake -S SPIRV-Cross -B SPIRV-Cross/build "${COMMON[@]}" \
  -DSPIRV_CROSS_ENABLE_TESTS=OFF -DSPIRV_CROSS_CLI=OFF \
  -DSPIRV_CROSS_STATIC=ON -DSPIRV_CROSS_SHARED=OFF -DSPIRV_CROSS_ENABLE_C_API=ON
cmake --build SPIRV-Cross/build -j"${NUMCPUS}" --target install

# Install only the libs the app links (release libs into both lib/ and libdbg/;
# these translators aren't perf/debug-sensitive, so a dedicated debug build is
# not worth the extra time).
LIBS="libglslang.a libSPIRV.a libMachineIndependent.a libGenericCodeGen.a \
      libglslang-default-resource-limits.a libOSDependent.a \
      libSPIRV-Tools-opt.a libSPIRV-Tools.a \
      libspirv-cross-msl.a libspirv-cross-glsl.a libspirv-cross-core.a"
for l in ${LIBS}; do
  cp "${STAGE}/lib/${l}" "${BASE_DEPS_DIR}/lib/${l}"
  cp "${STAGE}/lib/${l}" "${BASE_DEPS_DIR}/libdbg/${l}"
done
cp -R "${STAGE}/include/glslang"     "${BASE_DEPS_DIR}/include/"
cp -R "${STAGE}/include/spirv-tools"  "${BASE_DEPS_DIR}/include/"
cp -R "${STAGE}/include/spirv_cross"  "${BASE_DEPS_DIR}/include/"
rm -rf "${STAGE}"

# Leave the checkouts pristine so the parent repo's git status stays clean
# (removes build dirs and glslang/External; both are re-created on next run).
( cd glslang     && git clean -dffx -q )
( cd SPIRV-Cross && git clean -dffx -q )
echo "shader-translate deps installed."
