#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

cd sdl

export CXXFLAGS="-g -O3 -flto=thin ${XL_TARGETS} ${OSX_VERSION_MIN} "
export CFLAGS="-g -O3 -flto=thin ${XL_TARGETS} ${OSX_VERSION_MIN} "
export LDFLAGS="-g -O3 -flto=thin ${XL_TARGETS} ${OSX_VERSION_MIN} "
./configure --disable-shared --enable-static --disable-render-metal --disable-video-metal --disable-video-dummy  --disable-video-x11 --disable-video-opengles --disable-video-opengles2 --disable-video-vulkan --disable-haptic --disable-joystick --prefix=${BASE_DEPS_DIR}
make clean
make -j ${NUMCPUS}
cp ./build/.libs/libSDL2.a ${BASE_DEPS_DIR}/lib
export CXXFLAGS="-g ${XL_TARGETS} ${OSX_VERSION_MIN} "
export CFLAGS="-g ${XL_TARGETS} ${OSX_VERSION_MIN} "
export LDFLAGS="-g ${XL_TARGETS} ${OSX_VERSION_MIN} "
./configure --disable-shared --enable-static --disable-render-metal --disable-video-metal --disable-video-dummy  --disable-video-x11 --disable-video-opengles --disable-video-opengles2 --disable-video-vulkan --disable-haptic --disable-joystick --prefix=${BASE_DEPS_DIR}
make clean
make -j ${NUMCPUS}
cp ./build/.libs/libSDL2.a ${BASE_DEPS_DIR}/libdbg
make clean
git checkout -- include/SDL_config.h
git checkout -- include/SDL_revision.h
git status --ignored --short . | colrm 1 2 | xargs rm -rf
unset CXXFLAGS
unset CFLAGS
unset LDFLAGS


cd ..

