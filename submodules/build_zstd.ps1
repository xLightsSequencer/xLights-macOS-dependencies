# build_zstd.ps1 - Windows analog of build_zstd.sh.
#
# zstd ships a CMake project under build/cmake. We build it twice (Release into
# lib/, Debug into libdbg/) with Ninja, mirroring how the macOS script builds
# an optimised and a -g copy.
#
# Output names match the #pragma comment(lib, ...) entries in xLights'
# src-ui-wx/xLightsApp.cpp so the bundle is a drop-in replacement for the
# binaries currently committed under lib/windows64.

. "$PSScriptRoot\..\env.ps1"

$src = Join-Path $PSScriptRoot 'zstd\build\cmake'
if (-not (Test-Path $src)) { throw "build_zstd: submodule not checked out ($src)" }

foreach ($cfg in @('Release', 'Debug')) {
    $build = Join-Path $PSScriptRoot "zstd\build-win-$cfg"
    Remove-Item -Recurse -Force $build -ErrorAction SilentlyContinue

    Write-Host "==> zstd ($cfg)" -ForegroundColor Cyan
    Invoke-Checked $XL_CMAKE -S $src -B $build -G Ninja `
        "-DCMAKE_BUILD_TYPE=$cfg" `
        '-DZSTD_BUILD_STATIC=ON' '-DZSTD_BUILD_SHARED=OFF' `
        '-DZSTD_BUILD_PROGRAMS=OFF' '-DZSTD_BUILD_TESTS=OFF' `
        '-DZSTD_MULTITHREAD_SUPPORT=ON' `
        '-DCMAKE_POLICY_VERSION_MINIMUM=3.5'
    Invoke-Checked $XL_CMAKE --build $build --parallel $XL_NUMCPUS

    # MSVC emits zstd_static.lib; xLights links libzstd_static_VS.lib /
    # libzstdd_static_VS.lib, so rename on install.
    $dest = if ($cfg -eq 'Release') { $XL_LIB_DIR } else { $XL_DBG_DIR }
    $name = if ($cfg -eq 'Release') { 'libzstd_static_VS.lib' } else { 'libzstdd_static_VS.lib' }
    Install-Artifact -Path (Join-Path $build 'lib\zstd_static.lib') -Destination $dest -NewName $name
}

foreach ($h in @('zstd.h', 'zdict.h', 'zstd_errors.h')) {
    Install-Artifact -Path (Join-Path $PSScriptRoot "zstd\lib\$h") -Destination $XL_INC_DIR
}
Write-Host "==> zstd done" -ForegroundColor Green
