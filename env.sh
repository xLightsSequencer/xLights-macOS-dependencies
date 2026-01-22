

export MACOSX_DEPLOYMENT_TARGET=11.0
export OSX_VERSION_MIN="-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
export ARM64_TARGETS="-target arm64-apple-macos11.0 -arch arm64"
export X86_64_TARGETS="-target x86_64-apple-macos11.0 -arch x86_64"

#need ONE of these lines, default is to build for both arm64 and x86_64
export XL_TARGETS="${X86_64_TARGETS} ${ARM64_TARGETS}"
# export XL_TARGETS="${X86_64_TARGETS}"
# export XL_TARGETS="${ARM64_TARGETS}"

# need ONE of these
# export BUILD_HOST=x86_64
# export BUILD_HOST=arm
export BUILD_HOST=$( uname -p )

NUMCPUS=$(sysctl -n hw.ncpu)
