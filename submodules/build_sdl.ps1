# build_sdl.ps1 - Windows analog of build_sdl.sh.
#
# Built SHARED, unlike the macOS leg which produces a static libSDL2.a. That is
# deliberate: xLights on Windows already links the SDL2 import library and ships
# SDL2.dll, so a static build here would force an xLights link change for no
# benefit. Only one configuration is produced - a DLL has no debug/release ABI
# split at the C boundary - and the same import library is installed into both
# lib/ and libdbg/ so either xLights configuration resolves it.
. "$PSScriptRoot\..\env.ps1"

$src   = Join-Path $PSScriptRoot 'SDL'
$build = Join-Path $PSScriptRoot 'SDL\build-win-Release'
Build-CMakeProject -Source $src -BuildDir $build -Config Release -Options @(
    '-DSDL_SHARED=ON', '-DSDL_STATIC=OFF', '-DSDL_TEST=OFF', '-DSDL_TESTS=OFF',
    '-DSDL_INSTALL_TESTS=OFF')

Install-Artifact -Path (Join-Path $build 'SDL2.lib') -Destination $XL_LIB_DIR
Install-Artifact -Path (Join-Path $build 'SDL2.lib') -Destination $XL_DBG_DIR
Install-Artifact -Path (Join-Path $build 'SDL2.dll') -Destination $XL_BIN_DIR
Copy-Item (Join-Path $src 'include') (Join-Path $XL_INC_DIR 'SDL2') -Recurse -Force
Write-Host "==> sdl done" -ForegroundColor Green
