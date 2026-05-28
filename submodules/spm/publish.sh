#!/bin/bash
#
# Publish the ANGLE Swift package to xLightsSequencer/xLights-spm.
#
# Usage: submodules/spm/publish.sh <release|latest>
#
#   release  Stable channel (run from the tag-triggered release workflow).
#            Uses the per-tag release assets already attached by the release
#            step, generates Package.swift pointing at them, pushes to the
#            xLights-spm `main` branch and tags a semver derived from the deps
#            tag: xlights_2026.10 -> 2026.10.0. Consumers: from: "2026.10.0".
#
#   latest   Rolling channel (run from CI on every push to main). (Re)builds a
#            `latest` prerelease on this repo with SHA-stamped assets (a fresh
#            URL each commit, so GitHub's CDN can never serve stale bytes under
#            a reused URL), generates Package.swift pointing at them, and
#            force-pushes the xLights-spm `latest` branch. Consumers:
#            branch: "latest".
#
# Required env:
#   SPM_REPO_TOKEN  token with Contents:read/write on xLights-spm
#   GH_TOKEN        token for `gh` against THIS repo (latest channel only)
#   plus the standard GitHub Actions GITHUB_* variables.
#
# If SPM_REPO_TOKEN is absent the script no-ops with a notice (so forks / PRs
# and unconfigured repos don't fail the build).
set -e

CHANNEL="${1:?usage: publish.sh <release|latest>}"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BASE_DEPS_DIR=$( cd -- "${SCRIPT_DIR}/../.." &> /dev/null && pwd )
cd "${BASE_DEPS_DIR}"

if [ -z "${SPM_REPO_TOKEN}" ]; then
    echo "::notice::SPM_REPO_TOKEN not set — skipping xLights-spm publish."
    exit 0
fi

REPO_URL="https://github.com/${GITHUB_REPOSITORY}"

case "${CHANNEL}" in
  release)
    SUFFIX=""
    ASSET_BASE="${REPO_URL}/releases/download/${GITHUB_REF_NAME}"
    SPM_VER="${GITHUB_REF_NAME#xlights_}.0"          # xlights_2026.10 -> 2026.10.0
    ;;
  latest)
    SHA="$(git rev-parse --short HEAD)"
    SUFFIX="-${SHA}"
    ASSET_BASE="${REPO_URL}/releases/download/latest"
    # Ensure the rolling prerelease exists, then clear its old assets.
    gh release create latest --prerelease --title "latest" \
        --notes "Rolling latest build of the ANGLE Swift package." 2>/dev/null || true
    for a in $(gh release view latest --json assets -q '.assets[].name' 2>/dev/null); do
        gh release delete-asset latest "$a" -y 2>/dev/null || true
    done
    # SHA-stamped copies of the freshly built zips, then upload them.
    for FW in libEGL libGLESv2; do
      for v in macos ios; do
        cp "output/${FW}-${v}.xcframework.zip" "output/${FW}-${v}${SUFFIX}.xcframework.zip"
      done
    done
    gh release upload latest output/*"${SUFFIX}".xcframework.zip --clobber
    ;;
  *) echo "unknown channel: ${CHANNEL}" >&2; exit 1 ;;
esac

# Checksums of the (suffixed) zips consumers will actually download.
sha() { swift package compute-checksum "output/$1${SUFFIX}.xcframework.zip"; }
EGL_MAC_SHA=$(sha libEGL-macos)
EGL_IOS_SHA=$(sha libEGL-ios)
GLES_MAC_SHA=$(sha libGLESv2-macos)
GLES_IOS_SHA=$(sha libGLESv2-ios)

rm -rf spm-repo
git clone --depth 1 "https://x-access-token:${SPM_REPO_TOKEN}@github.com/xLightsSequencer/xLights-spm.git" spm-repo
cd spm-repo

mkdir -p Sources/ANGLE/include
rm -rf Sources/ANGLE/include/EGL Sources/ANGLE/include/GLES2 \
       Sources/ANGLE/include/GLES3 Sources/ANGLE/include/KHR
cp -R ../include/EGL ../include/GLES2 ../include/GLES3 ../include/KHR Sources/ANGLE/include/
[ -f Sources/ANGLE/shim.c ] || printf '// header-only umbrella target for ANGLE\n' > Sources/ANGLE/shim.c
[ -f .gitignore ] || printf '.build/\n' > .gitignore

sed -e "s|__ASSET_BASE__|${ASSET_BASE}|g" \
    -e "s|__SUFFIX__|${SUFFIX}|g" \
    -e "s|__LIBEGL_MACOS_SHA__|${EGL_MAC_SHA}|g" \
    -e "s|__LIBEGL_IOS_SHA__|${EGL_IOS_SHA}|g" \
    -e "s|__LIBGLESV2_MACOS_SHA__|${GLES_MAC_SHA}|g" \
    -e "s|__LIBGLESV2_IOS_SHA__|${GLES_IOS_SHA}|g" \
    ../submodules/spm/Package.swift.in > Package.swift

git config user.name  "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A

if [ "${CHANNEL}" = "release" ]; then
    git commit -m "ANGLE ${SPM_VER} (from ${GITHUB_REF_NAME})" || echo "No changes to commit"
    git push origin HEAD:main
    git tag -f "${SPM_VER}"
    git push -f origin "${SPM_VER}"
    echo "::notice::Published xLights-spm ${SPM_VER}"
else
    git checkout -B latest
    git commit -m "ANGLE latest (${GITHUB_SHA})" || echo "No changes to commit"
    git push -f origin latest
    echo "::notice::Published xLights-spm latest branch (${SHA})"
fi
