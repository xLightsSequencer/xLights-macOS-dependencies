#!/bin/bash
#
# make_relocatable.sh - rewrite absolute Mach-O paths in the bundle to @rpath.
#
# wxWidgets' debug configuration builds shared libraries (the release one is
# static). Those dylibs are installed with an absolute install name taken from
# configure's --prefix, which on CI is the runner's working directory:
#
#   /Users/runner/work/xLights-macOS-dependencies/.../libdbg/libwx_baseu-3.3.dylib
#
# That path exists on no consumer machine, so every consumer has had to rewrite
# it with install_name_tool at ITS build time. Fixing it here instead means the
# published bundle is relocatable and consumers only need to add an rpath.
#
# Debug wx stays shared deliberately: linking it statically would copy a large
# amount of code into every executable and make debug links much slower.
#
# Usage: make_relocatable.sh <bundle-root>
set -u

ROOT="${1:?usage: make_relocatable.sh <bundle-root>}"
CHANGED=0

# A dependency is bundle-internal if a file of that name lives in lib/ or
# libdbg/. Matching by basename rather than by path prefix keeps this correct
# when the bundle is reached through a symlink (/opt/local) instead of its
# real location.
is_internal() {
    local base="$1"
    [ -e "${ROOT}/lib/${base}" ] || [ -e "${ROOT}/libdbg/${base}" ]
}

while IFS= read -r dylib; do
    [ -n "${dylib}" ] || continue
    [ -L "${dylib}" ] && continue          # symlinks follow their target

    # 1. Its own install name. Keep the basename the library ALREADY publishes
    #    (wx advertises the short "libwx_baseu-3.3.dylib", not the versioned
    #    file name) - substituting the file's own name changes the library's
    #    identity, and anything still referring to it by the old name would
    #    then resolve to what the loader treats as a second, separate library.
    current_id=$(otool -D "${dylib}" 2>/dev/null \
                 | grep -v '(architecture' | grep -v ':[[:space:]]*$' \
                 | awk 'NF{print $1; exit}')
    if [ -n "${current_id}" ]; then
        base=$(basename "${current_id}")
    else
        base=$(basename "${dylib}")
    fi
    install_name_tool -id "@rpath/${base}" "${dylib}" 2>/dev/null && CHANGED=$((CHANGED+1))

    # 2. Every dependency that resolves inside the bundle. Skip otool's header
    #    lines, which name the file being inspected rather than a dependency.
    deps=$(otool -L "${dylib}" 2>/dev/null \
           | grep -v '(architecture' | grep -v ':[[:space:]]*$' \
           | awk '{print $1}' | grep '^/' | sort -u)
    while IFS= read -r dep; do
        [ -n "${dep}" ] || continue
        depbase=$(basename "${dep}")
        if is_internal "${depbase}"; then
            install_name_tool -change "${dep}" "@rpath/${depbase}" "${dylib}" 2>/dev/null
        fi
    done <<< "${deps}"

    # 3. Editing a Mach-O invalidates its code signature. On Apple silicon an
    #    invalid signature makes the dylib unloadable, so re-sign ad-hoc.
    codesign --force --sign - "${dylib}" 2>/dev/null || true
done <<< "$(find "${ROOT}/lib" "${ROOT}/libdbg" -name '*.dylib' -type f 2>/dev/null)"

echo "make_relocatable: rewrote ${CHANGED} dylib(s) under ${ROOT}"
