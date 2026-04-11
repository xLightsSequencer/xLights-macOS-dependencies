#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

cd liquidfun/liquidfun/Box2D

# --- iOS Release build (arm64) ---
git status --ignored -s | colrm 1 2 | xargs rm -rf
export CXX=clang++
export CXXFLAGS="-g -O3 -flto=thin ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DBOX2D_BUILD_EXAMPLES=OFF \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_MIN_VERSION} \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
echo "CXX_FLAGS += -Wno-unused-but-set-variable -Wno-nontrivial-memcall -Wno-uninitialized-const-pointer -Wno-error " >> ./Box2D/CMakeFiles/Box2D.dir/flags.make
make clean
make -j ${NUMCPUS} Box2D/fast
cp ./Box2D/Release/libliquidfun.a ${BASE_DEPS_DIR}/lib-ios/

# --- iOS Debug build (arm64) ---
git status --ignored -s | colrm 1 2 | xargs rm -rf
export CXXFLAGS="-g ${IOS_ARM64_TARGETS} ${IOS_VERSION_MIN}"
cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DBOX2D_BUILD_EXAMPLES=OFF \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_MIN_VERSION} \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
echo "CXX_FLAGS += -Wno-unused-but-set-variable -Wno-nontrivial-memcall -Wno-uninitialized-const-pointer -Wno-error " >> ./Box2D/CMakeFiles/Box2D.dir/flags.make
make clean
make -j ${NUMCPUS} Box2D/fast
cp ./Box2D/Release/libliquidfun.a ${BASE_DEPS_DIR}/libdbg-ios/
make clean

# --- iOS Simulator Release build (arm64-simulator) ---
git status --ignored -s | colrm 1 2 | xargs rm -rf
export CXXFLAGS="-g -O3 -flto=thin ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}"
cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DBOX2D_BUILD_EXAMPLES=OFF \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_MIN_VERSION} \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
echo "CXX_FLAGS += -Wno-unused-but-set-variable -Wno-nontrivial-memcall -Wno-uninitialized-const-pointer -Wno-error " >> ./Box2D/CMakeFiles/Box2D.dir/flags.make
make clean
make -j ${NUMCPUS} Box2D/fast
cp ./Box2D/Release/libliquidfun.a ${BASE_DEPS_DIR}/lib-ios-sim/

# --- iOS Simulator Debug build (arm64-simulator) ---
git status --ignored -s | colrm 1 2 | xargs rm -rf
export CXXFLAGS="-g ${IOS_SIM_ARM64_TARGETS} ${IOS_SIM_VERSION_MIN}"
cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DBOX2D_BUILD_EXAMPLES=OFF \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_MIN_VERSION} \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
echo "CXX_FLAGS += -Wno-unused-but-set-variable -Wno-nontrivial-memcall -Wno-uninitialized-const-pointer -Wno-error " >> ./Box2D/CMakeFiles/Box2D.dir/flags.make
make clean
make -j ${NUMCPUS} Box2D/fast
cp ./Box2D/Release/libliquidfun.a ${BASE_DEPS_DIR}/libdbg-ios-sim/
make clean

unset CXXFLAGS
unset CXX

cd ../..
git reset --hard
git status --ignored --short . | colrm 1 2 | xargs rm -rf
cd ..
