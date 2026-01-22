#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

cd liquidfun/liquidfun/Box2D
git status --ignored -s | colrm 1 2 | xargs rm -rf
export CXX=clang++
export CXXFLAGS="-g -O3 -flto=thin  ${XL_TARGETS} ${OSX_VERSION_MIN} "
cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DBOX2D_BUILD_EXAMPLES=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5
echo "CXX_FLAGS += -Wno-unused-but-set-variable -Wno-error " >> ./Box2D/CMakeFiles/Box2D.dir/flags.make
make clean
make -j ${NUMCPUS}
cp ./Box2D/Release/libliquidfun.a ${BASE_DEPS_DIR}/lib
git status --ignored -s | colrm 1 2 | xargs rm -rf
export CXXFLAGS="-g ${XL_TARGETS} ${OSX_VERSION_MIN} "
cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DBOX2D_BUILD_EXAMPLES=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5
echo "CXX_FLAGS += -Wno-unused-but-set-variable -Wno-error " >> ./Box2D/CMakeFiles/Box2D.dir/flags.make
make clean
make -j ${NUMCPUS}
cp ./Box2D/Release/libliquidfun.a ${BASE_DEPS_DIR}/libdbg
make clean

unset CXXFLAGS
unset CXX

cd ../..
git reset --hard
git status --ignored --short . | colrm 1 2 | xargs rm -rf
cd ..
