# build_ffmpeg.ps1 - Windows FFmpeg.
#
# UNLIKE every other library here, FFmpeg on Windows is DOWNLOADED, not built
# from the submodule. Reasons:
#
#   * The value in FFmpeg is the hardware-decode matrix (nvenc/nvdec, QSV, AMF,
#     D3D11VA, Vulkan, OpenCL) plus x264/x265. Getting that configure surface
#     right against MSYS2 for every GPU vendor is a large, permanent maintenance
#     burden for no gain over a build someone else already validates daily.
#   * It is what xLights already does. The binaries currently committed under
#     bin64/lib/windows64 ARE a downloaded MinGW build - avcodec.lib is a
#     dlltool import archive (_head_libavcodec_avcodec_lib) pointing at
#     avcodec-60.dll, and bin64 carries libgcc_s_seh-1.dll / libstdc++-6.dll /
#     libwinpthread-1.dll alongside it. So this is like-for-like, not a new
#     risk: MSVC links these import libraries today.
#
# Version sync with the macOS leg is enforced, not hoped for: FFMPEG_VERSION at
# the repo root is the single pin, and check_ffmpeg_sync verifies the macOS
# submodule is on the same tag. See README.deps.

. "$PSScriptRoot\..\env.ps1"

$versionFile = Join-Path $XL_DEPS_DIR 'FFMPEG_VERSION'
if (-not (Test-Path $versionFile)) { throw "build_ffmpeg: $versionFile missing" }
$ffVersion = (Get-Content $versionFile -Raw).Trim()
if (-not $ffVersion) { throw "build_ffmpeg: FFMPEG_VERSION is empty" }

# BtbN/FFmpeg-Builds publishes per-release-branch shared builds with import
# libraries and headers. 'gpl' matches the feature set xLights uses (x264/x265).
$branch = $ffVersion -replace '^n', ''
$asset  = "ffmpeg-$ffVersion-latest-win64-gpl-shared-$branch.zip"
$url    = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/$asset"

$work = Join-Path $PSScriptRoot 'ffmpeg-win'
Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $work | Out-Null

Write-Host "==> ffmpeg $ffVersion -> $url" -ForegroundColor Cyan
$zip = Join-Path $work 'ffmpeg.zip'
$ProgressPreference = 'SilentlyContinue'   # progress stream is enormous in CI logs
try {
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
} catch {
    throw ("build_ffmpeg: download failed for $url : " + $_.Exception.Message +
           " (check FFMPEG_VERSION names a branch BtbN still publishes)")
}
Expand-Archive -Path $zip -DestinationPath $work -Force

# The zip contains a single top-level directory.
$root = Get-ChildItem $work -Directory | Select-Object -First 1
if (-not $root) { throw "build_ffmpeg: archive did not expand to a directory" }

# Import libs (.lib) -> lib/ AND libdbg/. FFmpeg is consumed as a DLL, so there
# is no separate debug build; both configurations link the same import library.
$libs = Get-ChildItem (Join-Path $root.FullName 'lib\*.lib')
if ($libs.Count -eq 0) { throw "build_ffmpeg: no import libraries in $($root.FullName)\lib" }
foreach ($l in $libs) {
    Install-Artifact -Path $l.FullName -Destination $XL_LIB_DIR
    Install-Artifact -Path $l.FullName -Destination $XL_DBG_DIR
}

# Runtime DLLs -> bin/
$dlls = Get-ChildItem (Join-Path $root.FullName 'bin\*.dll')
if ($dlls.Count -eq 0) { throw "build_ffmpeg: no DLLs in $($root.FullName)\bin" }
foreach ($d in $dlls) { Install-Artifact -Path $d.FullName -Destination $XL_BIN_DIR }

# Headers -> include/ (libavcodec/, libavutil/, ...)
foreach ($d in (Get-ChildItem (Join-Path $root.FullName 'include') -Directory)) {
    Copy-Item $d.FullName $XL_INC_DIR -Recurse -Force
}

Write-Host ("==> ffmpeg done ({0} libs, {1} dlls)" -f $libs.Count, $dlls.Count) -ForegroundColor Green
