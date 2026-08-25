<#
build_windows.ps1 - Windows analog of build.sh.

Builds the Windows x64 dependency bundle from the SAME submodule pins the macOS
leg uses, so the two platforms cannot drift. Publishes
output\xLights-windows-dependencies-x64.zip, which xLights fetches the way the
macOS build fetches xLights-macOS-dependencies.tar.zst.

FFmpeg is the one exception - it is downloaded rather than built. See
submodules\build_ffmpeg.ps1 for why.

Usage:
  pwsh .\build_windows.ps1                 # everything
  pwsh .\build_windows.ps1 -Only zstd,lua  # a subset (iterating on one library)
  pwsh .\build_windows.ps1 -SkipPackage    # build, don't zip
#>
[CmdletBinding()]
param(
    [string[]]$Only,
    [switch]$SkipPackage
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\env.ps1"

# Order matters only in that wxWidgets is by far the longest pole; run it first
# so a failure in it surfaces early rather than after everything else.
$Libraries = @(
    @{ Name = 'wxwidgets';        Script = 'build_wxwidgets.ps1';        Submodule = 'submodules/wxWidgets' }
    @{ Name = 'zstd';             Script = 'build_zstd.ps1';             Submodule = 'submodules/zstd' }
    # zlib has no macOS counterpart (system-provided there) but must precede
    # libxlswriter, which links against it.
    @{ Name = 'zlib';             Script = 'build_zlib.ps1';             Submodule = 'submodules/zlib' }
    @{ Name = 'liquidfun';        Script = 'build_liquidfun.ps1';        Submodule = 'submodules/liquidfun' }
    @{ Name = 'sdl';              Script = 'build_sdl.ps1';              Submodule = 'submodules/SDL' }
    @{ Name = 'lua';              Script = 'build_lua.ps1';              Submodule = 'submodules/lua' }
    @{ Name = 'libxlswriter';     Script = 'build_libxlswriter.ps1';     Submodule = 'submodules/libxlswriter' }
    @{ Name = 'hidapi';           Script = 'build_hidapi.ps1';           Submodule = 'submodules/hidapi' }
    @{ Name = 'curl';             Script = 'build_curl.ps1';             Submodule = 'submodules/curl' }
    # FFmpeg is downloaded, not built - but the submodule is still needed so the
    # version-sync gate below can compare against the tag the macOS leg builds.
    @{ Name = 'ffmpeg';           Script = 'build_ffmpeg.ps1';           Submodule = @() }
    @{ Name = 'shader_translate'; Script = 'build_shader_translate.ps1'; Submodule = 'submodules/glslang', 'submodules/SPIRV-Cross' }
)


# --- version-sync gate ------------------------------------------------------
# The whole point of building Windows from this repo is that Mac and Windows
# share one set of pins. FFmpeg is downloaded, so its pin lives in
# FFMPEG_VERSION instead of a submodule SHA - which means nothing structurally
# forces the two to agree. Check it explicitly, or the sync guarantee silently
# becomes a sync aspiration.
function Test-FFmpegSync {
    $versionFile = Join-Path $PSScriptRoot 'FFMPEG_VERSION'
    if (-not (Test-Path $versionFile)) { throw "FFMPEG_VERSION missing" }
    $pinned = (Get-Content $versionFile -Raw).Trim()
    if (-not $pinned) { throw "FFMPEG_VERSION is empty" }

    Push-Location $PSScriptRoot
    try {
        # The authoritative pin is the commit this superproject records for the
        # submodule - read straight out of the tree, so the submodule does not
        # need to be checked out at all.
        $entry = & git ls-tree HEAD submodules/ffmpeg
        if (-not $entry) { throw "submodules/ffmpeg is not a tracked submodule" }
        $recorded = ($entry -split '\s+')[2]

        # Resolve what FFMPEG_VERSION names upstream. Deliberately NOT
        # `git describe` in the submodule: the checkout is --depth 1 with no
        # tags, so describe returns a bare SHA and the comparison would either
        # fail spuriously or, worse, be silently skipped.
        $url = & git config -f .gitmodules --get submodule.submodules/ffmpeg.url
        if (-not $url) { throw "no URL for submodules/ffmpeg in .gitmodules" }

        # Annotated tags need the peeled ref (^{}) to reach the commit;
        # lightweight tags only have the plain ref. Try peeled, then plain.
        $expected = $null
        foreach ($ref in @("refs/tags/$pinned^{}", "refs/tags/$pinned")) {
            $line = & git ls-remote $url $ref 2>$null | Select-Object -First 1
            if ($line) { $expected = ($line -split '\s+')[0]; break }
        }
        if (-not $expected) {
            throw "FFmpeg tag '$pinned' not found at $url (is FFMPEG_VERSION a real release tag?)"
        }

        if ($recorded -ne $expected) {
            throw ("FFmpeg version skew: FFMPEG_VERSION says '$pinned' (commit " +
                   "$($expected.Substring(0,10))) but submodules/ffmpeg is pinned to " +
                   "$($recorded.Substring(0,10)). The macOS leg builds the submodule and " +
                   "Windows downloads $pinned, so they must name the same release. " +
                   "See README.deps.")
        }
        Write-Host "    ffmpeg pin OK: $pinned ($($recorded.Substring(0,10)))" -ForegroundColor DarkGray
    } finally { Pop-Location }
}

# --- submodule checkout -----------------------------------------------------
# build.sh does `git submodule update --init` for everything; doing the same
# here would clone FFmpeg's full history for a leg that only downloads FFmpeg.
# Instead init exactly what the selected libraries need. submodules/ffmpeg is
# NOT among them: nothing builds it here, and the version-sync gate reads the
# recorded commit out of the superproject tree rather than the checkout.
#
# --depth 1 keeps the checkout cheap; the pinned commits are all release tags,
# which the server can serve directly.
function Initialize-Submodules {
    param([Parameter(Mandatory)][string[]]$Paths)
    $needed = @($Paths | Where-Object {
        -not (Test-Path (Join-Path $PSScriptRoot ((Join-Path $_ '.git') -replace '/', '\')))
    })
    if ($needed.Count -eq 0) {
        Write-Host "    all required submodules already checked out" -ForegroundColor DarkGray
        return
    }
    Write-Host ("    initialising: {0}" -f ($needed -join ', ')) -ForegroundColor DarkGray
    Push-Location $PSScriptRoot
    try {
        $gitArgs = @('submodule', 'update', '--init', '--depth', '1') + $needed
        Invoke-Checked git @gitArgs
    } finally { Pop-Location }
}

# `powershell -File script.ps1 -Only a,b,c` hands the whole list over as ONE
# string (unlike -Command), so split on commas before matching or every
# multi-library invocation looks like an unknown name.
$onlyNames = @()
if ($Only) { $onlyNames = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

$selected = if ($onlyNames) { $Libraries | Where-Object { $onlyNames -contains $_.Name } } else { $Libraries }
if ($onlyNames) {
    $unknown = $onlyNames | Where-Object { $_ -notin ($Libraries | ForEach-Object { $_.Name }) }
    if ($unknown) {
        $known = ($Libraries | ForEach-Object { $_.Name }) -join ', '
        throw "build_windows: unknown -Only value(s): $($unknown -join ', '). Known: $known"
    }
}

# --- clean ------------------------------------------------------------------
# The output tree is never pruned otherwise, so headers that move or get
# renamed between versions linger and can shadow the current ones. That is the
# exact header/library mismatch this bundle exists to prevent - a stale
# FFmpeg 6 header sitting beside an 8.x library, for instance.
#
# Only on a full build: a -Only run is a developer iterating on one library and
# must not wipe everything else.
if (-not $onlyNames) {
    Write-Host "==> Cleaning previous output tree" -ForegroundColor Cyan
    foreach ($d in @($XL_LIB_DIR, $XL_DBG_DIR, $XL_INC_DIR, $XL_BIN_DIR, $XL_WX_DIR)) {
        Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue
    }
    foreach ($d in @($XL_LIB_DIR, $XL_DBG_DIR, $XL_INC_DIR, $XL_BIN_DIR)) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
}

Write-Host "==> Checking out submodules" -ForegroundColor Cyan
$subPaths = @($selected | ForEach-Object { $_.Submodule })
Initialize-Submodules -Paths ($subPaths | Select-Object -Unique)

Write-Host "==> Checking cross-platform version pins" -ForegroundColor Cyan
Test-FFmpegSync

$logDir = Join-Path $PSScriptRoot 'submodules'
foreach ($lib in $selected) {
    $script = Join-Path $logDir $lib.Script
    if (-not (Test-Path $script)) {
        throw "build_windows: $($lib.Name) has no Windows build script yet ($($lib.Script))"
    }
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "==> $($lib.Name)" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    $log = Join-Path $logDir ("build_" + $lib.Name + "_win.log")
    # Tee to a log the way build.sh does, but still fail the run on error.
    #
    # $ErrorActionPreference must be relaxed across this call: with 'Stop', any
    # line a child process writes to stderr - a CMake *warning*, a compiler
    # note - is promoted to a terminating NativeCommandError and aborts the
    # build. The exit code, checked below, is the real success signal.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $script 2>&1 | Tee-Object -FilePath $log
        $rc = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prevEAP }
    if ($rc -ne 0) { throw "build_windows: $($lib.Name) failed (rc=$rc, see $log)" }
}

# --- stamp ------------------------------------------------------------------
# Records what produced this bundle. Without it, an ABI or version bug report
# arrives with no way to tell which toolset or pins were used.
$stamp = [ordered]@{
    built_utc     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    msvc_version  = $XL_MSVC_VERSION
    vs_path       = $XL_VS_PATH
    arch          = $XL_ARCH
    ffmpeg        = (Get-Content (Join-Path $PSScriptRoot 'FFMPEG_VERSION') -Raw).Trim()
}
$stamp | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'BUILD_INFO.json')

# --- verify -----------------------------------------------------------------
# Building is not the same as being usable. Check the bundle survives being
# moved to a different path and can still be linked and run against, before it
# is packaged for anyone to consume.
if ($onlyNames) {
    Write-Host "==> Skipping bundle verification (-Only build is partial)" -ForegroundColor DarkGray
} else {
    Write-Host "==> Verifying the bundle is relocatable and usable" -ForegroundColor Cyan
    & "$PSScriptRoot\verify_bundle.ps1" -Bundle $PSScriptRoot
}

# --- package ----------------------------------------------------------------
if (-not $SkipPackage) {
    $output = Join-Path $PSScriptRoot 'output'
    Remove-Item -Recurse -Force $output -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $output | Out-Null

    $stage = Join-Path $output 'xLights-windows-dependencies'
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    foreach ($d in @('lib', 'libdbg', 'include', 'bin', 'wxWidgets')) {
        $src = Join-Path $PSScriptRoot $d
        if (Test-Path $src) { Copy-Item $src $stage -Recurse -Force }
    }
    Copy-Item (Join-Path $PSScriptRoot 'BUILD_INFO.json') $stage -Force

    $zip = Join-Path $output 'xLights-windows-dependencies-x64.zip'
    Write-Host "==> Packaging $zip" -ForegroundColor Cyan
    # bsdtar (in-box on Windows 10+) is dramatically faster than
    # Compress-Archive on a tree this size and handles long paths.
    Push-Location $output
    try { Invoke-Checked tar -a -c -f $zip 'xLights-windows-dependencies' }
    finally { Pop-Location }
    Remove-Item -Recurse -Force $stage
    Write-Host ("    Wrote {0} ({1:N0} MB)" -f $zip, ((Get-Item $zip).Length / 1MB)) -ForegroundColor Green
}

Write-Host ""
Write-Host "==> Windows dependency build complete." -ForegroundColor Green
