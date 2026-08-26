#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

# --debug-only rebuilds just the debug libraries. Release wx is static and
# takes about as long again, so when iterating on a wx source change - the one
# situation where this script gets run repeatedly - it is wasted work.
WX_DEBUG_ONLY=no
if [ "${1:-}" = "--debug-only" ]; then
    WX_DEBUG_ONLY=yes
    echo "==> wxwidgets: debug-only build"
fi


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
            --with-osx_cocoa --with-macosx-version-min=${MACOSX_DEPLOYMENT_TARGET} --disable-dependency-tracking \
            --disable-compat30  --enable-mimetype --enable-aui --with-opengl \
            --enable-webview --enable-webviewwebkit --disable-mdi --disable-mdidoc --disable-loggui \
            --disable-xrc --disable-stc --disable-ribbon --disable-htmlhelp --disable-mediactrl \
            --with-cxx=17 --enable-cxx11 --enable-std_containers --enable-std_string_conv_in_wxstring \
            --without-liblzma  --with-expat=builtin --with-zlib=builtin --with-libjpeg=builtin  --without-libtiff \
            --disable-sys-libs --enable-utf8 --enable-utf8only \
            --enable-backtrace --enable-exceptions --disable-shared
if [ "${WX_DEBUG_ONLY}" = "no" ]; then
    make -j ${NUMCPUS}
    make install
fi
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
            --with-osx_cocoa --with-macosx-version-min=${MACOSX_DEPLOYMENT_TARGET} --disable-dependency-tracking \
            --disable-compat30  --enable-mimetype --enable-aui --with-opengl \
            --enable-webview --enable-webviewwebkit --disable-mdi --disable-mdidoc --disable-loggui \
            --disable-xrc --disable-stc --disable-ribbon --disable-htmlhelp --disable-mediactrl \
            --with-cxx=17 --enable-cxx11 --enable-std_containers --enable-std_string_conv_in_wxstring \
            --without-liblzma  --with-expat=builtin --with-zlib=builtin --with-libjpeg=builtin  --without-libtiff \
            --disable-sys-libs --enable-utf8 --enable-utf8only \
            --enable-backtrace --enable-exceptions
make -j ${NUMCPUS}
rm -rf ${BASE_DEPS_DIR}/libdbg/libwx*.dylib
make install

# Make the debug information self-contained.
#
# Without this, the debug dylibs carry only a debug MAP: N_OSO stabs pointing
# at the .o files they were linked from. The cleanup at the end of this script
# deletes those objects, so the map dangles and a debugger shows wxWidgets
# frames greyed out with no source. For a bundle downloaded from CI it can
# never work at all, because the paths refer to the build machine.
#
# dsymutil resolves the map into a .dSYM beside each library while the objects
# still exist, which is what makes wx debuggable from an unpacked bundle.
echo "==> wxwidgets: generating dSYM bundles for the debug libraries"
for _dylib in "${BASE_DEPS_DIR}"/libdbg/libwx*.dylib; do
    # Only real files; the install leaves version symlinks beside them.
    [ -f "${_dylib}" ] && [ ! -L "${_dylib}" ] || continue
    dsymutil "${_dylib}" -o "${_dylib}.dSYM" || {
        echo "build_wxwidgets: dsymutil failed for ${_dylib}" >&2
        exit 1
    }
done

cd ..
# Remove build artifacts only.
#
# This used to be `git status --ignored -s . | colrm 1 2 | xargs rm -rf`, which
# also listed MODIFIED TRACKED FILES - so editing wxWidgets in place and then
# rebuilding silently deleted the edits. Harmless while the tree is clean,
# which is why it survived; ruinous exactly when someone is working on wx.
#
# git clean is the right primitive: it only ever removes UNTRACKED files, so
# tracked edits are safe by construction rather than by careful filtering.
#   -d  descend into untracked directories
#   -f  actually do it
#   -x  include ignored files too
#
# Both -x and untracked-but-not-ignored matter here: wxWidgets does not
# gitignore build/, so its artifacts are plain untracked. Matching only
# ignored files would leave the entire build tree behind.
git clean -dfxq .


cd ../..
