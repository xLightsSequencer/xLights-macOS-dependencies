#!/bin/bash
#
# verify_bundle.sh - prove the macOS bundle is actually USABLE, not just built.
#
# Building successfully says nothing about whether a consumer can use the
# result. The failure this exists to catch is absolute paths baked into the
# artifact at build time: a dylib whose install name is the CI runner's
# directory resolves fine on the machine that built it and nowhere else. That
# is why xLights carries scripts/mac_fix_dylibs - it rewrites those paths with
# install_name_tool on every consumer build.
#
# RELOCATION IS THE WHOLE POINT. The checks run against a COPY at a different
# path, because a bundle inspected in place cannot fail this test.
#
# Usage: verify_bundle.sh [<bundle-root>]   (default: this repo)
set -u

SRC="${1:-$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )}"
RELOC="${TMPDIR:-/tmp}/xl-bundle-verify.$$"
FAILURES=()

cleanup() { rm -rf "${RELOC}"; }
trap cleanup EXIT

echo "==> Relocating bundle for verification"
echo "    from: ${SRC}"
echo "    to:   ${RELOC}"
mkdir -p "${RELOC}"
for d in lib libdbg include bin share; do
    [ -d "${SRC}/${d}" ] && cp -R "${SRC}/${d}" "${RELOC}/" 2>/dev/null
done

# ---------------------------------------------------------------------------
# 1. Mach-O paths. Anything that is not @rpath/@loader_path/@executable_path or
#    a system location is an absolute path into the build machine.
# ---------------------------------------------------------------------------
echo "==> Checking Mach-O install names and dependencies"
BAD_MACHO=0
while IFS= read -r dylib; do
    [ -n "${dylib}" ] || continue
    # otool emits header lines - "<file>:" and "<file> (architecture x86_64):" -
    # which name the file being INSPECTED, not a dependency. Including them
    # reports the bundle's own location as a fault, so drop them first: a
    # checker that cries wolf gets switched off.
    paths=$( { otool -D "${dylib}"; otool -L "${dylib}"; } 2>/dev/null \
             | grep -v '(architecture' | grep -v ':[[:space:]]*$' \
             | awk '{print $1}' | grep '^/' | sort -u )
    while IFS= read -r p; do
        [ -n "${p}" ] || continue
        case "${p}" in
            /usr/lib/*|/System/*|/Library/Frameworks/*) ;;   # OS-provided, fine
            /*)
                echo "    NOT RELOCATABLE: $(basename "${dylib}") -> ${p}"
                BAD_MACHO=$((BAD_MACHO+1))
                ;;
        esac
    done <<< "${paths}"
done <<< "$(find "${RELOC}" -name '*.dylib' -type f 2>/dev/null)"

if [ "${BAD_MACHO}" -gt 0 ]; then
    FAILURES+=("${BAD_MACHO} absolute Mach-O path(s)")
else
    echo "    OK - no absolute paths in any dylib"
fi

# ---------------------------------------------------------------------------
# 2. Text files that embed a configure --prefix (wx-config, .pc, .cmake, .la).
# ---------------------------------------------------------------------------
echo "==> Checking text files for a baked-in build prefix"
BAD_TEXT=0
while IFS= read -r f; do
    [ -n "${f}" ] || continue
    if grep -qE "(/Users/runner/|${SRC})" "${f}" 2>/dev/null; then
        echo "    EMBEDS BUILD PATH: ${f#${RELOC}/}"
        BAD_TEXT=$((BAD_TEXT+1))
    fi
done <<< "$(find "${RELOC}" \( -name '*.pc' -o -name '*.cmake' -o -name '*.la' -o -name 'wx-config*' \) -type f 2>/dev/null)"
[ "${BAD_TEXT}" -gt 0 ] && FAILURES+=("${BAD_TEXT} file(s) embedding a build path") \
                        || echo "    OK - no build prefix in shipped text files"

# ---------------------------------------------------------------------------
# 3. Link AND RUN against the relocated static libraries. Linking alone would
#    miss an architecture mismatch; running proves the slice is usable.
# ---------------------------------------------------------------------------
echo "==> Linking and running a smoke test against the relocated bundle"
REQUIRED_LIBS=(libavcodec.a libavformat.a libavutil.a libswresample.a liblua.a libzstd.a libminizip.a libxlsxwriter.a)
MISSING_LIBS=()
for l in "${REQUIRED_LIBS[@]}"; do
    [ -f "${RELOC}/lib/${l}" ] || MISSING_LIBS+=("${l}")
done
if [ ${#MISSING_LIBS[@]} -gt 0 ]; then
    echo "    SKIPPED - bundle has no lib/ for: ${MISSING_LIBS[*]}"
    FAILURES+=("bundle missing libraries: ${MISSING_LIBS[*]}")
    SMOKE=""
fi

SMOKE="${SMOKE-unset}"
[ -n "${SMOKE}" ] && SMOKE="${RELOC}/smoke.cpp"
if [ -n "${SMOKE}" ]; then
cat > "${SMOKE}" <<'CPP'
#include <cstdio>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <lua.h>
#include <minizip/unzip.h>
#include <xlsxwriter.h>
#include <lauxlib.h>
}
#include <zstd.h>
int main() {
    unsigned c = avcodec_version(), f = avformat_version();
    lua_State* L = luaL_newstate();
    if (!L) { printf("lua init failed\n"); return 1; }
    lua_close(L);
    unzFile uf = unzOpen("definitely-not-a-zip");
    if (uf) { unzClose(uf); printf("minizip opened a non-zip\n"); return 1; }
    // libxlsxwriter takes its zip half from minizip now, so prove the pair links.
    lxw_workbook* wb = workbook_new("verify.xlsx");
    if (!wb) { printf("xlsxwriter init failed\n"); return 1; }
    workbook_close(wb);
    printf("avcodec=%u.%u avformat=%u.%u zstd=%s lua=ok minizip=ok xlsxwriter=ok\n",
           c >> 16, (c >> 8) & 0xff, f >> 16, (f >> 8) & 0xff, ZSTD_versionString());
    return 0;
}
CPP

if clang++ -std=c++17 -o "${RELOC}/smoke" "${SMOKE}" \
     -I"${RELOC}/include" \
     "${RELOC}/lib/libavcodec.a" "${RELOC}/lib/libavformat.a" \
     "${RELOC}/lib/libavutil.a" "${RELOC}/lib/libswresample.a" \
     "${RELOC}/lib/liblua.a" "${RELOC}/lib/libzstd.a" \
     "${RELOC}/lib/libxlsxwriter.a" "${RELOC}/lib/libminizip.a" \
     -framework CoreFoundation -framework CoreMedia -framework CoreVideo \
     -framework VideoToolbox -framework AudioToolbox -framework Security \
     -framework CoreServices -framework CoreGraphics -framework OpenGL \
     -framework Metal -framework AppKit \
     -liconv -lbz2 -lz 2>"${RELOC}/link.err"; then
    if out=$( "${RELOC}/smoke" 2>&1 ); then
        echo "    OK - ${out}"
    else
        echo "    RAN BUT FAILED: ${out}"
        FAILURES+=("smoke test did not run")
    fi
else
    echo "    LINK FAILED:"
    sed 's/^/      /' "${RELOC}/link.err" | head -15
    FAILURES+=("smoke test did not link")
fi
fi

# ---------------------------------------------------------------------------
echo ""
if [ ${#FAILURES[@]} -gt 0 ]; then
    echo "verify_bundle: FAILED - ${FAILURES[*]}"
    exit 1
fi
echo "verify_bundle: bundle is relocatable and usable."
