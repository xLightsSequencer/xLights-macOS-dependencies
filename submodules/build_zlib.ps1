# build_zlib.ps1 - Windows-only; there is no macOS counterpart.
#
# macOS and Linux take zlib from the system, so this repo never needed it.
# Windows has no system zlib, and two things here require it: libxlsxwriter
# links it, and xLights itself links z.lib. Built static, both configurations.
. "$PSScriptRoot\..\env.ps1"

$src = Join-Path $PSScriptRoot 'zlib'
foreach ($cfg in @('Release', 'Debug')) {
    $build = Join-Path $PSScriptRoot "zlib\build-win-$cfg"
    Build-CMakeProject -Source $src -BuildDir $build -Config $cfg -Options @(
        '-DZLIB_BUILD_EXAMPLES=OFF', '-DBUILD_SHARED_LIBS=OFF')

    # MSVC static zlib is zlibstatic.lib (Debug: zlibstaticd.lib). xLights
    # links "z.lib", so install under that name.
    $built = Get-ChildItem $build -Filter 'zlibstatic*.lib' | Select-Object -First 1
    if (-not $built) { throw "build_zlib: static library not produced in $build" }
    $dest = if ($cfg -eq 'Release') { $XL_LIB_DIR } else { $XL_DBG_DIR }
    Install-Artifact -Path $built.FullName -Destination $dest -NewName 'z.lib'
    # Keep the canonical name too, so find_package(ZLIB) style consumers work.
    Install-Artifact -Path $built.FullName -Destination $dest -NewName 'zlib.lib'
}
Install-Artifact -Path (Join-Path $src 'zlib.h') -Destination $XL_INC_DIR
$zconf = Get-ChildItem (Join-Path $PSScriptRoot 'zlib\build-win-Release') -Filter 'zconf.h' | Select-Object -First 1
if (-not $zconf) { throw "build_zlib: generated zconf.h not found" }
Install-Artifact -Path $zconf.FullName -Destination $XL_INC_DIR
Write-Host "==> zlib done" -ForegroundColor Green
