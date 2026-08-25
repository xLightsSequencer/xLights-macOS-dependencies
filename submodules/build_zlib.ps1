# build_zlib.ps1 - Windows-only; there is no macOS counterpart.
#
# macOS and Linux take zlib from the system, so this repo never needed it.
# Windows has no system zlib, and two things here require it: libxlsxwriter
# links it, and xLights itself links z.lib. Built static, both configurations.
. "$PSScriptRoot\..\env.ps1"

$src = Join-Path $PSScriptRoot 'zlib'
foreach ($cfg in @('Release', 'Debug')) {
    $build = Join-Path $PSScriptRoot "zlib\build-win-$cfg"
    # zlib 1.3.2 renamed its CMake options: BUILD_SHARED_LIBS and
    # ZLIB_BUILD_EXAMPLES no longer do anything here, so passing them silently
    # built the shared library too.
    Build-CMakeProject -Source $src -BuildDir $build -Config $cfg -Options @(
        '-DZLIB_BUILD_SHARED=OFF', '-DZLIB_BUILD_STATIC=ON',
        '-DZLIB_BUILD_TESTING=OFF', '-DZLIB_INSTALL=OFF')

    # Do NOT hardcode the produced file name. It is not stable across releases:
    # 1.3.1 emitted zlibstatic.lib, while 1.3.2 sets OUTPUT_NAME to
    # z${zlib_static_suffix} - "zs.lib" on Windows, "zsd.lib" in Debug. With
    # the shared library and tests disabled exactly one .lib should exist, so
    # take that and fail loudly if the assumption ever stops holding.
    $libs = @(Get-ChildItem $build -Recurse -Filter '*.lib' -File)
    if ($libs.Count -eq 0) { throw "build_zlib: no static library produced in $build" }
    if ($libs.Count -gt 1) {
        throw ("build_zlib: expected exactly one library, found: " +
               (($libs | ForEach-Object { $_.Name }) -join ', '))
    }
    $built = $libs[0]
    Write-Host ("    zlib produced $($built.Name)") -ForegroundColor DarkGray
    $dest = if ($cfg -eq 'Release') { $XL_LIB_DIR } else { $XL_DBG_DIR }
    Install-Artifact -Path $built.FullName -Destination $dest -NewName 'z.lib'
    # Keep the canonical name too, so find_package(ZLIB) style consumers work.
    Install-Artifact -Path $built.FullName -Destination $dest -NewName 'zlib.lib'
}
Install-Artifact -Path (Join-Path $src 'zlib.h') -Destination $XL_INC_DIR
$zconf = Get-ChildItem (Join-Path $PSScriptRoot 'zlib\build-win-Release') -Recurse -Filter 'zconf.h' -File | Select-Object -First 1
if (-not $zconf) { throw "build_zlib: generated zconf.h not found" }
Install-Artifact -Path $zconf.FullName -Destination $XL_INC_DIR
Write-Host "==> zlib done" -ForegroundColor Green
