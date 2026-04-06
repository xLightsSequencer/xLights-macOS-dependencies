
# --- macOS targets ---
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

# --- iOS targets ---
export IOS_MIN_VERSION=26.0
export IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
export IOS_VERSION_MIN="-miphoneos-version-min=${IOS_MIN_VERSION}"
export IOS_ARM64_TARGETS="-target arm64-apple-ios${IOS_MIN_VERSION} -arch arm64 -isysroot ${IOS_SDK}"

NUMCPUS=$(sysctl -n hw.ncpu)
