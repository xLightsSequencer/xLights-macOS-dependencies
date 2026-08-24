# env.ps1 - Windows analog of env.sh.
#
# Dot-source this from build_windows.ps1 and from each submodules/build_*.ps1
# so every library is compiled with the same toolset, flags and output layout:
#
#   . $PSScriptRoot\..\env.ps1
#
# It resolves the Visual Studio install, imports the x64 developer environment
# into the current PowerShell session (so cl/link/cmake/msbuild are on PATH),
# and exports the $XL_* variables the per-library scripts consume.

$ErrorActionPreference = 'Stop'

# --- output layout ----------------------------------------------------------
# Mirrors the macOS tree (lib/libdbg/include/bin) so the two bundles have the
# same shape. wxWidgets is the exception: it keeps its native
# wxWidgets/lib/vc_x64_lib layout because the MSW build hardcodes that path for
# setup.h, and xLights' WXWIDGETS_ROOT expects it.
$Global:XL_DEPS_DIR = (Resolve-Path $PSScriptRoot).Path
$Global:XL_LIB_DIR  = Join-Path $XL_DEPS_DIR 'lib'
$Global:XL_DBG_DIR  = Join-Path $XL_DEPS_DIR 'libdbg'
$Global:XL_INC_DIR  = Join-Path $XL_DEPS_DIR 'include'
$Global:XL_BIN_DIR  = Join-Path $XL_DEPS_DIR 'bin'
$Global:XL_WX_DIR   = Join-Path $XL_DEPS_DIR 'wxWidgets'

foreach ($d in @($XL_LIB_DIR, $XL_DBG_DIR, $XL_INC_DIR, $XL_BIN_DIR)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# --- parallelism ------------------------------------------------------------
$Global:XL_NUMCPUS = if ($env:NUMBER_OF_PROCESSORS) { $env:NUMBER_OF_PROCESSORS } else { 4 }

# --- toolset ----------------------------------------------------------------
# xLights is Visual Studio 2026 (MSVC v14.5x / VS major 18) only. VS 2022 was
# dropped, so there is no cross-toolset ABI question to manage and no toolset
# pin here: whatever the VS 2026 install provides is used, and the exact
# version is recorded in BUILD_INFO.json so an ABI report can be diagnosed from
# the artifact rather than guessed at.
#
# XL_VCVARS_VER can still force a specific toolset (same values as vcvars'
# -vcvars_ver, e.g. 14.51.36231) when bisecting a compiler problem.
$Global:XL_VCVARS_VER = $env:XL_VCVARS_VER
$Global:XL_ARCH       = 'x64'

# Minimum Visual Studio major version. 18 = VS 2026.
$Global:XL_VS_MIN_VERSION = 18

function Find-VisualStudio {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) {
        throw "env.ps1: vswhere.exe not found. Install Visual Studio 2026."
    }
    # -version constrains to VS 2026+. Without it, vswhere happily returns a
    # VS 2022 install and the build fails much later with confusing errors
    # instead of saying which Visual Studio is required.
    $path = & $vswhere -latest -products * `
        -version "[$XL_VS_MIN_VERSION.0,)" `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if (-not $path) {
        throw ("env.ps1: no Visual Studio 2026 (major >= $XL_VS_MIN_VERSION) with the C++ x64 " +
               "toolset was found. xLights dropped VS 2022; install VS 2026.")
    }
    return $path
}

# Import vcvars64.bat's environment into this PowerShell session. Running the
# .bat directly is useless - it mutates a child cmd.exe and exits - so capture
# `set` output and re-apply it here.
function Import-VsDevEnv {
    param([string]$VsPath)
    if ($env:XL_VSDEV_IMPORTED -eq $VsPath) { return }   # idempotent across dot-sources
    $vcvars = Join-Path $VsPath 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path $vcvars)) { throw "env.ps1: vcvars64.bat not found at $vcvars" }

    Write-Host "==> Importing VS dev environment ($VsPath)" -ForegroundColor Cyan
    # `-vcvars_ver` pins the toolset that vcvars puts on PATH.
    $verArg = ''
    if ($XL_VCVARS_VER) { $verArg = "-vcvars_ver=$XL_VCVARS_VER" }
    $out = & cmd.exe /c "`"$vcvars`" $verArg >nul 2>&1 && set"
    if ($LASTEXITCODE -ne 0) { throw "env.ps1: vcvars64.bat failed (exit $LASTEXITCODE)" }
    foreach ($line in $out) {
        if ($line -match '^([^=]+)=(.*)$') {
            Set-Item -Path ("Env:" + $Matches[1]) -Value $Matches[2] -ErrorAction SilentlyContinue
        }
    }
    $env:XL_VSDEV_IMPORTED = $VsPath
}

$Global:XL_VS_PATH = Find-VisualStudio
Import-VsDevEnv -VsPath $XL_VS_PATH

# cmake/ninja ship inside VS, so no separate install is needed once the dev
# environment is imported. Prefer whatever is on PATH, fall back to the bundled
# copies.
function Resolve-Tool {
    param([string]$Name, [string[]]$Fallbacks)
    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($f in $Fallbacks) { if (Test-Path $f) { return $f } }
    return $null
}
$Global:XL_CMAKE = Resolve-Tool 'cmake' @(
    (Join-Path $XL_VS_PATH 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'))
$Global:XL_NINJA = Resolve-Tool 'ninja' @(
    (Join-Path $XL_VS_PATH 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe'))
$Global:XL_MSBUILD = Resolve-Tool 'msbuild' @(
    (Join-Path $XL_VS_PATH 'MSBuild\Current\Bin\amd64\MSBuild.exe'),
    (Join-Path $XL_VS_PATH 'MSBuild\Current\Bin\MSBuild.exe'))

if (-not $XL_CMAKE)   { throw "env.ps1: cmake not found (looked on PATH and in the VS install)." }
if (-not $XL_MSBUILD) { throw "env.ps1: msbuild not found (looked on PATH and in the VS install)." }

# --- helpers used by the per-library scripts --------------------------------

# Run a native command and fail the script if it returns non-zero. PowerShell
# does NOT do this by default - $ErrorActionPreference has no effect on native
# exit codes - so without this a failed compile scrolls by and the packaging
# step happily ships a bundle with a missing library.
# NOTE: deliberately a SIMPLE function, not an advanced one with [Parameter()]
# attributes. An advanced function performs parameter binding on every argument,
# so a pass-through flag that prefix-matches a parameter name gets swallowed -
# e.g. `Invoke-Checked tar -a -c -f x.zip` bound `-a` to `-Arguments` and then
# failed on `-f`. With no declared parameters everything lands in $args verbatim.
function Invoke-Checked {
    if ($args.Count -lt 1) { throw "Invoke-Checked: no command given" }
    $exe = $args[0]
    # [object[]] on the variable is load-bearing. PowerShell UNROLLS a
    # single-element array coming out of an if-block, so a plain assignment
    # leaves $rest as a bare string when there is exactly one trailing
    # argument - and splatting a string splats its CHARACTERS, turning
    # `python update_glslang_sources.py` into `python u`. The type constraint
    # forces it back to an array. Only reproduces with exactly one argument,
    # which is why multi-argument calls looked fine.
    [object[]]$rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
    Write-Host "    $exe $($rest -join ' ')" -ForegroundColor DarkGray
    & $exe @rest
    if ($LASTEXITCODE -ne 0) {
        throw "command failed (exit $LASTEXITCODE): $exe $($rest -join ' ')"
    }
}

# Configure + build a CMake project with Ninja. Used by most of the per-library
# Windows scripts; keeps generator/flag choices in one place so they cannot
# drift apart between libraries.
function Build-CMakeProject {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$BuildDir,
        [Parameter(Mandatory)][ValidateSet('Release','Debug')][string]$Config,
        [string[]]$Options = @()
    )
    if (-not (Test-Path $Source)) { throw "Build-CMakeProject: source not found: $Source" }
    Remove-Item -Recurse -Force $BuildDir -ErrorAction SilentlyContinue

    $cfgArgs = @('-S', $Source, '-B', $BuildDir, '-G', 'Ninja', "-DCMAKE_BUILD_TYPE=$Config") + $Options
    Invoke-Checked $XL_CMAKE @cfgArgs
    Invoke-Checked $XL_CMAKE --build $BuildDir --parallel $XL_NUMCPUS
}

# Copy a build product into the bundle, failing loudly if it is not there.
# A silent miss here is the failure mode that produces a bundle that only
# breaks later, on a developer's machine, at link time.
function Install-Artifact {
    param([Parameter(Mandatory)][string]$Path,
          [Parameter(Mandatory)][string]$Destination,
          [string]$NewName)
    if (-not (Test-Path $Path)) { throw "expected build product not found: $Path" }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    if ($NewName) { Copy-Item $Path (Join-Path $Destination $NewName) -Force }
    else          { Copy-Item $Path $Destination -Force }
}

# Record the toolset actually used - vcvars sets VCToolsVersion. This goes into
# the bundle stamp so a mismatched-ABI bug report can be diagnosed from the
# artifact alone rather than guessed at.
$Global:XL_MSVC_VERSION = $env:VCToolsVersion
Write-Host ("env.ps1: VS={0} msvc={1} cpus={2}" -f $XL_VS_PATH, $XL_MSVC_VERSION, $XL_NUMCPUS) -ForegroundColor DarkGray
