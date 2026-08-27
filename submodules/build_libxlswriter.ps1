# build_libxlswriter.ps1 - Windows analog of build_libxlswriter.sh.
# Static, both configurations, matching xlsxwriter.lib / xlsxwriterd.lib.
# Depends on zlib, so build_zlib.ps1 must run first (build_windows.ps1 orders it).
. "$PSScriptRoot\..\env.ps1"

$src = Join-Path $PSScriptRoot 'libxlswriter'

# libxlsxwriter forces debug info into its RELEASE build - it appends
#   /Ox /Zi /Fd"${CMAKE_BINARY_DIR}/xlsxwriter.pdb"
# to CMAKE_C_FLAGS_RELEASE. Because it appends, it wins over anything passed on
# the command line, so -DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT cannot undo it and
# neither can overriding CMAKE_C_FLAGS_RELEASE. The result is a release library
# carrying debug info it has no use for, pointing at a .pdb that only ever
# existed in this build tree: consumers then get an LNK4099 per object. Strip
# it at the source, the same way liquidfun's /W4 /WX is neutralised.
$top = Join-Path $src 'CMakeLists.txt'
$orig = Get-Content $top -Raw
$patched = [regex]::Replace($orig, '\s*/Zi\s+/Fd\\?"\$\{CMAKE_BINARY_DIR\}/\$\{PROJECT_NAME\}\.pdb\\?"', '')
if ($patched -eq $orig) {
    throw "build_libxlswriter: could not strip /Zi + /Fd from CMakeLists.txt - upstream changed"
}
Set-Content -Path $top -Value $patched -NoNewline
Write-Host "    stripped release /Zi + external pdb" -ForegroundColor DarkGray

# USE_SYSTEM_MINIZIP stops libxlsxwriter compiling its own copy of minizip's
# write half, which otherwise defines the same 19 zip* symbols this bundle's
# minizip does - leaving which implementation runs up to link order. Its
# discovery expects a vcpkg-style package on MSVC and pkg-config elsewhere, and
# this bundle ships neither by design, so point it straight at what was built.
$mzPatched = [regex]::Replace($patched,
    '(?s)if\(MSVC\)\s*\r?\n\s*find_package\(MINIZIP[^\r\n]*\r?\n\s*set\(MINIZIP_LIBRARIES[^\r\n]*\r?\n\s*else\(\)\s*\r?\n\s*find_package\(PkgConfig[^\r\n]*\r?\n\s*pkg_check_modules\(MINIZIP[^\r\n]*\r?\n\s*list\(APPEND LXW_PRIVATE_INCLUDE_DIRS[^\r\n]*\r?\n\s*endif\(\)',
    "set(MINIZIP_LIBRARIES `${XL_MINIZIP_LIBRARY})`n    list(APPEND LXW_PRIVATE_INCLUDE_DIRS `${XL_MINIZIP_INCLUDE_DIR})")
if ($mzPatched -eq $patched) {
    throw "build_libxlswriter: could not redirect the USE_SYSTEM_MINIZIP discovery - upstream CMakeLists changed"
}
Set-Content -Path $top -Value $mzPatched -NoNewline
Write-Host "    redirected system-minizip discovery at the bundle" -ForegroundColor DarkGray

try {
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

    $mzLib = Join-Path $(if ($cfg -eq 'Release') { $XL_LIB_DIR } else { $XL_DBG_DIR }) 'minizip.lib'
    if (-not (Test-Path $mzLib)) {
        throw "build_libxlswriter: minizip ($cfg) has not been installed into the bundle yet - build_minizip must run first"
    }
    Build-CMakeProject -Source $src -BuildDir $build -Config $cfg -Options @(
        '-DBUILD_SHARED_LIBS=OFF', '-DBUILD_TESTS=OFF', '-DBUILD_EXAMPLES=OFF',
        '-DUSE_SYSTEM_MINIZIP=ON',
        "-DXL_MINIZIP_LIBRARY=$mzLib",
        "-DXL_MINIZIP_INCLUDE_DIR=$XL_INC_DIR",
        "-DZLIB_LIBRARY=$zlibLib",
        "-DZLIB_INCLUDE_DIR=$XL_INC_DIR")

    $built = Get-ChildItem $build -Recurse -Filter 'xlsxwriter*.lib' | Select-Object -First 1
    if (-not $built) { throw "build_libxlswriter: library not produced in $build" }
    $dest = if ($cfg -eq 'Release') { $XL_LIB_DIR } else { $XL_DBG_DIR }
    $name = if ($cfg -eq 'Release') { 'xlsxwriter.lib' } else { 'xlsxwriterd.lib' }
    Install-Artifact -Path $built.FullName -Destination $dest -NewName $name
}
} finally {
    # Leave the submodule pristine so the parent repo's git status stays clean.
    Push-Location $src
    try { & git checkout -- . 2>&1 | Out-Null } finally { Pop-Location }
}
Copy-Item (Join-Path $src 'include\*') $XL_INC_DIR -Recurse -Force
Write-Host "==> libxlswriter done" -ForegroundColor Green
