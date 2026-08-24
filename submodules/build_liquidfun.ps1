# build_liquidfun.ps1 - Windows analog of build_liquidfun.sh.
#
# liquidfun is an unmaintained Box2D fork (last upstream activity years ago),
# so its CMake predates current minimums - hence CMAKE_POLICY_VERSION_MINIMUM.
# Static, both configurations, matching liquidfun.lib / liquidfund.lib.
. "$PSScriptRoot\..\env.ps1"

$src = Join-Path $PSScriptRoot 'liquidfun\liquidfun\Box2D'
if (-not (Test-Path (Join-Path $src 'CMakeLists.txt'))) {
    throw "build_liquidfun: submodule not checked out ($src)"
}

# liquidfun declares cmake_minimum_required(VERSION 2.8). CMake 4.3 (the copy
# bundled with VS 2026) has REMOVED compatibility with < 3.5 outright, and
# CMAKE_POLICY_VERSION_MINIMUM no longer rescues it. Upstream is dormant, so
# raise the declared minimum in the working tree and restore it afterwards.
#
# The macOS leg will hit exactly this once its cmake reaches 4.3 - see
# README.deps.
$patched = @()
foreach ($f in (Get-ChildItem $src -Recurse -Filter 'CMakeLists.txt')) {
    $text = Get-Content $f.FullName -Raw
    $new  = [regex]::Replace($text, '(?i)cmake_minimum_required\s*\(\s*VERSION\s+2(\.\d+)*',
                             'cmake_minimum_required(VERSION 3.10')
    if ($new -ne $text) { Set-Content -Path $f.FullName -Value $new -NoNewline; $patched += $f.FullName }
}
Write-Host ("    raised cmake_minimum_required in {0} file(s)" -f $patched.Count) -ForegroundColor DarkGray
if ($patched.Count -eq 0) { throw "build_liquidfun: expected to patch at least one CMakeLists.txt" }

# liquidfun sets C_FLAGS_WARNINGS to "/W4 /WX" and APPENDS it to
# CMAKE_CXX_FLAGS, so it wins over anything passed on the command line - which
# is why passing -DCMAKE_CXX_FLAGS=/WX- alone does nothing. Neutralise it at
# the source. (The macOS script solves the same problem by post-patching the
# generated flags.make, which has no Ninja equivalent.)
$top = Join-Path $src 'CMakeLists.txt'
$text = Get-Content $top -Raw
$new  = $text -replace '(?m)^(\s*set\(C_FLAGS_WARNINGS\s+)"[^"]*"', '$1"/W0"'
if ($new -eq $text) { throw "build_liquidfun: could not neutralise C_FLAGS_WARNINGS - upstream CMakeLists changed" }
Set-Content -Path $top -Value $new -NoNewline
Write-Host "    neutralised /W4 /WX" -ForegroundColor DarkGray

try {
foreach ($cfg in @('Release', 'Debug')) {
    $build = Join-Path $PSScriptRoot "liquidfun\build-win-$cfg"
    Build-CMakeProject -Source $src -BuildDir $build -Config $cfg -Options @(
        '-DBOX2D_BUILD_EXAMPLES=OFF', '-DBOX2D_BUILD_UNITTESTS=OFF',
        '-DBOX2D_BUILD_SHARED=OFF', '-DBOX2D_BUILD_STATIC=ON',
        # The fork triggers several warnings that are errors under current MSVC
        # defaults; it is not our code to fix and upstream is dormant.
        # /WX- is the load-bearing part: liquidfun's own CMake turns on
        # warnings-as-errors, and current MSVC diagnoses code this dormant fork
        # will never fix.
        '-DCMAKE_C_FLAGS=/W0 /WX-', '-DCMAKE_CXX_FLAGS=/W0 /WX-')

    # The CMake target is called Box2D but its OUTPUT_NAME is liquidfun.
    $built = Get-ChildItem $build -Recurse -Filter 'liquidfun*.lib' | Select-Object -First 1
    if (-not $built) { throw "build_liquidfun: Box2D library not produced in $build" }
    $dest = if ($cfg -eq 'Release') { $XL_LIB_DIR } else { $XL_DBG_DIR }
    $name = if ($cfg -eq 'Release') { 'liquidfun.lib' } else { 'liquidfund.lib' }
    Install-Artifact -Path $built.FullName -Destination $dest -NewName $name
}
} finally {
    # Leave the submodule pristine so the parent repo's git status stays clean,
    # matching what build_liquidfun.sh does on macOS.
    Push-Location $src
    try { & git checkout -- . 2>&1 | Out-Null } finally { Pop-Location }
}
Write-Host "==> liquidfun done" -ForegroundColor Green
