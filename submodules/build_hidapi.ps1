# build_hidapi.ps1 - Windows analog of build_hidapi.sh.
# Shared, matching the hidapi.lib/hidapi.dll pair xLights ships today.
. "$PSScriptRoot\..\env.ps1"

$src   = Join-Path $PSScriptRoot 'hidapi'
$build = Join-Path $PSScriptRoot 'hidapi\build-win-Release'
Build-CMakeProject -Source $src -BuildDir $build -Config Release -Options @(
    '-DBUILD_SHARED_LIBS=ON', '-DHIDAPI_BUILD_HIDTEST=OFF')

# hidapi's MSVC output lands under a windows/ subdirectory of the build tree.
$lib = Get-ChildItem $build -Recurse -Filter 'hidapi.lib' | Select-Object -First 1
$dll = Get-ChildItem $build -Recurse -Filter 'hidapi.dll' | Select-Object -First 1
if (-not $lib) { throw "build_hidapi: hidapi.lib not produced" }
if (-not $dll) { throw "build_hidapi: hidapi.dll not produced" }
Install-Artifact -Path $lib.FullName -Destination $XL_LIB_DIR
Install-Artifact -Path $lib.FullName -Destination $XL_DBG_DIR
Install-Artifact -Path $dll.FullName -Destination $XL_BIN_DIR
Install-Artifact -Path (Join-Path $src 'hidapi\hidapi.h') -Destination $XL_INC_DIR
Write-Host "==> hidapi done" -ForegroundColor Green
