#!/bin/bash

. ../env.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( dirname -- "${SCRIPT_DIR}" )

ISPC_VERSION=v1.28.2
wget https://github.com/ispc/ispc/releases/download/${ISPC_VERSION}/ispc-${ISPC_VERSION}-macOS.universal.tar.gz
tar -xzf ispc-${ISPC_VERSION}-macOS.universal.tar.gz
cp ispc-${ISPC_VERSION}-macOS.universal/bin/ispc ${BASE_DEPS_DIR}/bin
rm -rf ispc-${ISPC_VERSION}-macOS.universal*


