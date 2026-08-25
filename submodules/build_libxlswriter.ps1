# build_libxlswriter.ps1 - Windows analog of build_libxlswriter.sh.
# Static, both configurations, matching xlsxwriter.lib / xlsxwriterd.lib.
# Depends on zlib, so build_zlib.ps1 must run first (build_windows.ps1 orders it).
. "$PSScriptRoot\..\env.ps1"

$src = Join-Path $PSScriptRoot 'libxlswriter'
foreach ($cfg in @('Release', 'Debug')) {
    $build = Join-Path $PSScriptRoot "libxlswriter\build-win-$cfg"
    # Point at the zlib copy this bundle already installed rather than reaching
    # into zlib's build tree. The installed name is one we control and keep
    # stable; upstream's is not - 1.3.1 emitted zlibstatic.lib and 1.3.2 emits
    # zs.lib, which silently broke this lookup.
    $zlibDir = if ($cfg -eq 'Release') { $XL_LIB_DIR } else { $XL_DBG_DIR }
    $zlibLib = Join-Path $zlibDir 'zlib.lib'
    if (-not (Test-Path $zlibLib)) {
        throw "build_libxlswriter: zlib ($cfg) has not been installed into the bundle yet - build_zlib must run first"
    }

    Build-CMakeProject -Source $src -BuildDir $build -Config $cfg -Options @(
        '-DBUILD_SHARED_LIBS=OFF', '-DBUILD_TESTS=OFF', '-DBUILD_EXAMPLES=OFF',
        "-DZLIB_LIBRARY=$zlibLib",
        "-DZLIB_INCLUDE_DIR=$XL_INC_DIR")

    $built = Get-ChildItem $build -Recurse -Filter 'xlsxwriter*.lib' | Select-Object -First 1
    if (-not $built) { throw "build_libxlswriter: library not produced in $build" }
    $dest = if ($cfg -eq 'Release') { $XL_LIB_DIR } else { $XL_DBG_DIR }
    $name = if ($cfg -eq 'Release') { 'xlsxwriter.lib' } else { 'xlsxwriterd.lib' }
    Install-Artifact -Path $built.FullName -Destination $dest -NewName $name
}
Copy-Item (Join-Path $src 'include\*') $XL_INC_DIR -Recurse -Force
Write-Host "==> libxlswriter done" -ForegroundColor Green
