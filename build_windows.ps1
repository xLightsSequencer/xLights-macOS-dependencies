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
    @{ Name = 'wxwidgets';        Script = 'build_wxwidgets.ps1' }
    @{ Name = 'zstd';             Script = 'build_zstd.ps1' }
    # zlib has no macOS counterpart (system-provided there) but must precede
    # libxlswriter, which links against it.
    @{ Name = 'zlib';             Script = 'build_zlib.ps1' }
    @{ Name = 'liquidfun';        Script = 'build_liquidfun.ps1' }
    @{ Name = 'sdl';              Script = 'build_sdl.ps1' }
    @{ Name = 'lua';              Script = 'build_lua.ps1' }
    @{ Name = 'libxlswriter';     Script = 'build_libxlswriter.ps1' }
    @{ Name = 'hidapi';           Script = 'build_hidapi.ps1' }
    @{ Name = 'curl';             Script = 'build_curl.ps1' }
    @{ Name = 'ffmpeg';           Script = 'build_ffmpeg.ps1' }
    @{ Name = 'shader_translate'; Script = 'build_shader_translate.ps1' }
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

    $sub = Join-Path $PSScriptRoot 'submodules\ffmpeg'
    if (-not (Test-Path (Join-Path $sub '.git'))) {
        Write-Host "    ffmpeg submodule not checked out; skipping sync check" -ForegroundColor DarkGray
        return
    }
    Push-Location $sub
    try { $actual = (& git describe --tags --always 2>$null) } finally { Pop-Location }

    # The macOS leg compiles the submodule; Windows downloads $pinned. If they
    # name different releases the bundles are NOT version-synced.
    if ($actual -and -not $actual.StartsWith($pinned)) {
        throw ("FFmpeg version skew: FFMPEG_VERSION says '$pinned' but the " +
               "submodule is at '$actual'. Move the submodule to $pinned (the " +
               "macOS leg builds it) or update FFMPEG_VERSION. See README.deps.")
    }
    Write-Host "    ffmpeg pin OK: $pinned" -ForegroundColor DarkGray
}

Write-Host "==> Checking cross-platform version pins" -ForegroundColor Cyan
Test-FFmpegSync

# --- build ------------------------------------------------------------------
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
