#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )


cd ffmpeg

rm -rf x86_64
git status --ignored -s . | colrm 1 2 | xargs rm -rf
./configure --disable-inline-asm --enable-static --disable-shared --disable-securetransport --extra-cflags="${OSX_VERSION_MIN}" --disable-indev=lavfi --disable-libx264 --disable-lzma --enable-gpl --enable-opengl --disable-programs --arch=x86_64
sed -i -e "s/^CFLAGS=/CFLAGS=-g ${X86_64_TARGETS} ${OSX_VERSION_MIN} -DGL_SILENCE_DEPRECATION=1 -Wno-incompatible-function-pointer-types -fno-common /" ffbuild/config.mak
sed -i -e "s/^CXXFLAGS=/CXXFLAGS=-g ${X86_64_TARGETS} ${OSX_VERSION_MIN} -DGL_SILENCE_DEPRECATION=1 -fno-common /" ffbuild/config.mak
sed -i -e "s/^LDFLAGS=/LDFLAGS=-g ${X86_64_TARGETS} ${OSX_VERSION_MIN} -fno-common /" ffbuild/config.mak
make -j ${NUMCPUS} ; make
mkdir ./x86_64
find . -name "*.a" -exec cp -f {} ./x86_64 \;
make clean
git status --ignored -s . | colrm 1 2  | grep -v x86_64 | xargs rm -rf
./configure --enable-static --disable-shared --disable-securetransport --extra-cflags="${OSX_VERSION_MIN}" --disable-indev=lavfi --disable-libx264 --disable-lzma --enable-gpl --enable-opengl --disable-programs --arch=arm64
sed -i -e "s/^CFLAGS=/CFLAGS=-g ${ARM64_TARGETS} ${OSX_VERSION_MIN} -DGL_SILENCE_DEPRECATION=1 -Wno-incompatible-function-pointer-types -fno-common /" ffbuild/config.mak
sed -i -e "s/^CXXFLAGS=/CXXFLAGS=-g ${ARM64_TARGETS} ${OSX_VERSION_MIN} -DGL_SILENCE_DEPRECATION=1 -fno-common /" ffbuild/config.mak
sed -i -e "s/^LDFLAGS=/LDFLAGS=-g ${ARM64_TARGETS} ${OSX_VERSION_MIN} -fno-common /" ffbuild/config.mak
make -j ${NUMCPUS} ; make
# Install the public headers alongside the libraries.
#
# Without this the bundle ships FFmpeg libraries but no FFmpeg headers, and
# consumers compile against some other copy - which is how a build ends up
# linking 8.x libraries against 6.x headers. AVFrame/AVCodecContext layouts
# differ across major versions, so that mismatch compiles cleanly and then
# misbehaves at runtime.
#
# This is an in-tree build, so the configure-generated headers (avconfig.h,
# ffversion.h) sit next to the checked-in ones and are picked up by the glob.
for _ffdir in libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale; do
    mkdir -p "${BASE_DEPS_DIR}/include/${_ffdir}"
    cp -f ./${_ffdir}/*.h "${BASE_DEPS_DIR}/include/${_ffdir}/"
done

lipo -create -output ${BASE_DEPS_DIR}/lib/libavutil.a ./libavutil/libavutil.a ./x86_64/libavutil.a
lipo -create -output ${BASE_DEPS_DIR}/lib/libavfilter.a ./libavfilter/libavfilter.a ./x86_64/libavfilter.a
lipo -create -output ${BASE_DEPS_DIR}/lib/libavcodec.a ./libavcodec/libavcodec.a ./x86_64/libavcodec.a
lipo -create -output ${BASE_DEPS_DIR}/lib/libavformat.a ./libavformat/libavformat.a ./x86_64/libavformat.a
lipo -create -output ${BASE_DEPS_DIR}/lib/libavdevice.a ./libavdevice/libavdevice.a ./x86_64/libavdevice.a
lipo -create -output ${BASE_DEPS_DIR}/lib/libswresample.a ./libswresample/libswresample.a ./x86_64/libswresample.a
lipo -create -output ${BASE_DEPS_DIR}/lib/libswscale.a ./libswscale/libswscale.a ./x86_64/libswscale.a
make clean
git status --ignored -s . | colrm 1 2 | xargs rm  -rf
./configure --disable-asm --disable-x86asm --enable-static --disable-shared --disable-securetransport --extra-cflags="${OSX_VERSION_MIN}" --disable-indev=lavfi --disable-libx264 --disable-lzma --enable-gpl --enable-opengl --disable-programs --disable-optimizations
sed -i -e "s/^CFLAGS=/CFLAGS=-g ${XL_TARGETS} ${OSX_VERSION_MIN} -DGL_SILENCE_DEPRECATION=1 -Wno-incompatible-function-pointer-types -fno-common /" ffbuild/config.mak
sed -i -e "s/^CXXFLAGS=/CXXFLAGS=-g ${XL_TARGETS} ${OSX_VERSION_MIN} -DGL_SILENCE_DEPRECATION=1 -fno-common /" ffbuild/config.mak
sed -i -e "s/^LDFLAGS=/LDFLAGS=-g ${XL_TARGETS} ${OSX_VERSION_MIN} -fno-common /" ffbuild/config.mak
make -j ${NUMCPUS} ; make
find . -name "*.a" -exec cp {} ${BASE_DEPS_DIR}/libdbg/ \;

make clean
git status --ignored --short . | colrm 1 2 | xargs rm -rf

cd ..
