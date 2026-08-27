# build_minizip.ps1 - Windows analog of build_minizip.sh.
#
# minizip is the zip/unzip layer that ships inside zlib's contrib/, so it needs
# no submodule of its own - build_zlib.ps1 must run first, both because minizip
# includes zlib.h and because it is checked out with zlib.
#
# xLights uses this for sequence packages and FPP uploads, not for spreadsheets.
# It previously compiled the copy vendored inside libxlsxwriter, which is the
# 2010 release of the same code; that copy carries no local patches, so this is
# a version upgrade rather than a fork being abandoned. Debian's libminizip-dev
# is built from this same contrib/ source, so Linux and the bundle stay on
# matching code instead of two unrelated vintages.
. "$PSScriptRoot\..\env.ps1"

$src = Join-Path $PSScriptRoot 'zlib\contrib\minizip'
if (-not (Test-Path (Join-Path $src 'unzip.c'))) {
    throw "build_minizip: zlib submodule not checked out ($src)"
}

# iowin32.c is the Win32 file-I/O backend and belongs only in this build; the
# command-line tools (minizip.c, miniunz.c) define main() and must stay out.
$names = @('ioapi.c', 'iowin32.c', 'unzip.c', 'zip.c', 'mztools.c')
$sources = @()
foreach ($n in $names) {
    $p = Join-Path $src $n
    if (-not (Test-Path $p)) { throw "build_minizip: expected source missing: $n" }
    $sources += $p
}
Write-Host ("==> minizip: {0} source files" -f $sources.Count) -ForegroundColor Cyan

foreach ($cfg in @('Release', 'Debug')) {
    $obj = Join-Path $src "build-win-$cfg"
    Remove-Item -Recurse -Force $obj -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $obj | Out-Null

    # Same rule as everything else here: match xLights' CRT, and keep debug info
    # inside the objects so the bundle ships no separate .pdb.
    $flags = if ($cfg -eq 'Release') { @('/O2', '/MD', '/DNDEBUG') }
             else                    { @('/Od', '/MDd', '/D_DEBUG', '/Z7') }

    # zlib.h comes from the copy build_zlib.ps1 already installed, so minizip is
    # built against the same zlib xLights links rather than whatever is nearby.
    $zlibHeader = Join-Path $XL_INC_DIR 'zlib.h'
    if (-not (Test-Path $zlibHeader)) {
        throw "build_minizip: zlib.h has not been installed into the bundle yet - build_zlib must run first"
    }

    $clArgs = @('/nologo', '/c', '/W3', '/MP', '/D_CRT_SECURE_NO_WARNINGS') +
              $flags + @("/I$src", "/I$XL_INC_DIR") + $sources

    Push-Location $obj
    try {
        Invoke-Checked cl @clArgs
        $objs = @(Get-ChildItem '*.obj' | ForEach-Object { $_.FullName })
        if ($objs.Count -ne $sources.Count) {
            throw "build_minizip: expected $($sources.Count) objects, got $($objs.Count)"
        }
        $libArgs = @('/nologo', "/OUT:$(Join-Path $obj 'minizip.lib')") + $objs
        Invoke-Checked lib @libArgs
    } finally { Pop-Location }

    $dest = if ($cfg -eq 'Release') { $XL_LIB_DIR } else { $XL_DBG_DIR }
    Install-Artifact -Path (Join-Path $obj 'minizip.lib') -Destination $dest
}

# Consumers include <minizip/unzip.h>, matching where Debian's libminizip-dev
# puts them, so the same include works on every platform.
$incDir = Join-Path $XL_INC_DIR 'minizip'
New-Item -ItemType Directory -Force -Path $incDir | Out-Null
# The closure of what zip.h/unzip.h actually include: ioapi.h pulls in ints.h,
# and mz64conf.h / bzlib.h sit behind #ifdefs this build does not define.
foreach ($h in @('zip.h', 'unzip.h', 'ioapi.h', 'ints.h', 'iowin32.h', 'crypt.h', 'mztools.h')) {
    Install-Artifact -Path (Join-Path $src $h) -Destination $incDir
}
Write-Host "==> minizip done" -ForegroundColor Green
