#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )


cd wxWidgets
git submodule update --init

cd build

export BINARY_PLATFORMS="x86_64,arm64"
export CXXFLAGS=""
export OBJCXXFLAGS=""
export CPPFLAGS="-g -flto=thin"
export LDFLAGS="-g -flto=thin"
export CXX=clang++
export CXXCPP="clang++ -E"
export CC=clang
export CPP="clang -E"
export CFLAGS="-g"
../configure  --disable-debug_flag --enable-debug_info --enable-optimise --prefix=${BASE_DEPS_DIR} --enable-universal_binary=${BINARY_PLATFORMS} \
            --with-osx_cocoa --with-macosx-version-min=11.0 --disable-dependency-tracking \
            --disable-compat30  --enable-mimetype --enable-aui --with-opengl \
            --enable-webview --enable-webviewwebkit --disable-mdi --disable-mdidoc --disable-loggui \
            --disable-xrc --disable-stc --disable-ribbon --disable-htmlhelp --disable-mediactrl \
            --with-cxx=17 --enable-cxx11 --enable-std_containers --enable-std_string_conv_in_wxstring \
            --without-liblzma  --with-expat=builtin --with-zlib=builtin --with-libjpeg=builtin  --without-libtiff \
            --disable-sys-libs \
            --enable-backtrace --enable-exceptions --disable-shared
make -j ${NUMCPUS}
make install
make clean


export BINARY_PLATFORMS="x86_64,arm64"
export CXXFLAGS=""
export OBJCXXFLAGS=""
export CPPFLAGS="-g"
export LDFLAGS=""
export CXX=clang++
export CXXCPP="clang++ -E"
export CC=clang
export CPP="clang -E"
export CFLAGS="-g"
../configure  --prefix=${BASE_DEPS_DIR} --libdir=${BASE_DEPS_DIR}/libdbg \
            --enable-debug --enable-debug_info --disable-optimise --enable-universal_binary=${BINARY_PLATFORMS} \
            --with-osx_cocoa --with-macosx-version-min=11.0 --disable-dependency-tracking \
            --disable-compat30  --enable-mimetype --enable-aui --with-opengl \
            --enable-webview --enable-webviewwebkit --disable-mdi --disable-mdidoc --disable-loggui \
            --disable-xrc --disable-stc --disable-ribbon --disable-htmlhelp --disable-mediactrl \
            --with-cxx=17 --enable-cxx11 --enable-std_containers --enable-std_string_conv_in_wxstring \
            --without-liblzma  --with-expat=builtin --with-zlib=builtin --with-libjpeg=builtin  --without-libtiff \
            --disable-sys-libs \
            --enable-backtrace --enable-exceptions
make -j ${NUMCPUS}
rm -rf ${BASE_DEPS_DIR}/libdbg/libwx*.dylib
make install

cd ..
git status --ignored -s . | colrm 1 2 | xargs rm  -rf


cd ../..
