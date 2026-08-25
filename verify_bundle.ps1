<#
verify_bundle.ps1 - prove the Windows bundle is actually USABLE, not just built.

The macOS counterpart exists because that bundle bakes absolute build-machine
paths into its dylibs. Windows import libraries reference DLLs by name rather
than by path, so the same failure is unlikely here - but "unlikely" is not
"checked", and the cost of finding out from a developer instead of from CI is
high.

RELOCATION IS THE POINT: everything runs against a COPY at a different path,
because a bundle inspected where it was built cannot fail this test.

Usage: verify_bundle.ps1 [-Bundle <path>]   (default: this repo)
#>
[CmdletBinding()]
param([string]$Bundle = "")

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\env.ps1"

if (-not $Bundle) { $Bundle = $PSScriptRoot }
$reloc = Join-Path ([System.IO.Path]::GetTempPath()) "xl-bundle-verify-$PID"
$failures = @()

Write-Host "==> Relocating bundle for verification" -ForegroundColor Cyan
Write-Host "    from: $Bundle"
Write-Host "    to:   $reloc"
Remove-Item -Recurse -Force $reloc -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $reloc | Out-Null
foreach ($d in @('lib', 'libdbg', 'include', 'bin', 'wxWidgets')) {
    $src = Join-Path $Bundle $d
    if (Test-Path $src) { Copy-Item $src $reloc -Recurse -Force }
}

# --- 1. absolute build paths in shipped text files --------------------------
Write-Host "==> Checking text files for a baked-in build prefix" -ForegroundColor Cyan
$escaped = [regex]::Escape($Bundle)
$leaks = @()
foreach ($f in (Get-ChildItem $reloc -Recurse -Include '*.cmake', '*.pc', '*.props', '*.config' -File -ErrorAction SilentlyContinue)) {
    $t = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    if ($t -and ($t -match $escaped -or $t -match 'D:\\a\\xLights')) { $leaks += $f.FullName.Substring($reloc.Length + 1) }
}
if ($leaks.Count -gt 0) {
    $leaks | ForEach-Object { Write-Host "    EMBEDS BUILD PATH: $_" -ForegroundColor Red }
    $failures += "$($leaks.Count) file(s) embedding a build path"
} else {
    Write-Host "    OK - no build prefix in shipped text files" -ForegroundColor DarkGray
}

# --- 2. link AND RUN against the relocated bundle ---------------------------
# Linking alone would not catch a DLL that cannot be loaded, so the smoke test
# calls into FFmpeg (a DLL) and lua/zstd (static) and is executed.
Write-Host "==> Linking and running a smoke test against the relocated bundle" -ForegroundColor Cyan
$required = @('lib\avcodec.lib', 'lib\avformat.lib', 'lib\lua.lib', 'lib\libzstd_static_VS.lib')
$missing = @($required | Where-Object { -not (Test-Path (Join-Path $reloc $_)) })
if ($missing.Count -gt 0) {
    Write-Host "    SKIPPED - bundle missing: $($missing -join ', ')" -ForegroundColor Red
    $failures += "bundle missing libraries: $($missing -join ', ')"
} else {
    $smoke = Join-Path $reloc 'smoke.cpp'
    @'
#include <cstdio>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <lua.h>
#include <lauxlib.h>
}
#include <zstd.h>
int main() {
    unsigned c = avcodec_version(), f = avformat_version();
    lua_State* L = luaL_newstate();
    if (!L) { printf("lua init failed\n"); return 1; }
    lua_close(L);
    printf("avcodec=%u.%u avformat=%u.%u zstd=%s lua=ok\n",
           c >> 16, (c >> 8) & 0xff, f >> 16, (f >> 8) & 0xff, ZSTD_versionString());
    return 0;
}
'@ | Set-Content -Encoding Ascii $smoke

    Push-Location $reloc
    try {
        $clArgs = @('/nologo', '/std:c++17', '/EHsc', '/MD', "/I$reloc\include",
                    'smoke.cpp', '/Fe:smoke.exe', '/link', "/LIBPATH:$reloc\lib",
                    'avcodec.lib', 'avformat.lib', 'avutil.lib', 'lua.lib',
                    'libzstd_static_VS.lib')
        & cl @clArgs 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    LINK FAILED (cl exit $LASTEXITCODE)" -ForegroundColor Red
            & cl @clArgs 2>&1 | Select-Object -Last 12 | ForEach-Object { Write-Host "      $_" }
            $failures += 'smoke test did not link'
        } else {
            # The FFmpeg DLLs live in bin/; put it on PATH so the loader finds
            # them. A missing DLL surfaces here as a startup failure, which is
            # exactly the class of breakage this test is for.
            $env:PATH = "$reloc\bin;$env:PATH"
            $out = & "$reloc\smoke.exe" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    OK - $out" -ForegroundColor Green
            } else {
                Write-Host "    RAN BUT FAILED (exit $LASTEXITCODE): $out" -ForegroundColor Red
                $failures += 'smoke test did not run'
            }
        }
    } finally { Pop-Location }
}

Remove-Item -Recurse -Force $reloc -ErrorAction SilentlyContinue
Write-Host ""
if ($failures.Count -gt 0) {
    throw "verify_bundle: FAILED - $($failures -join '; ')"
}
Write-Host "verify_bundle: bundle is relocatable and usable." -ForegroundColor Green
