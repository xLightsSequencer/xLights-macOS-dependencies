# build_curl.ps1 - Windows analog of build_curl.sh.
#
# Shared, using Schannel (the OS TLS stack) so the bundle carries no OpenSSL.
#
# NOTE: xLights currently links "libcurl.dll.a" - a MinGW import library - and
# ships libcurl-x64.dll plus libgcc_s_seh-1.dll / libstdc++-6.dll /
# libwinpthread-1.dll to satisfy it. An MSVC build produces libcurl_imp.lib +
# libcurl.dll and needs none of the MinGW runtime DLLs, so switching to this
# bundle means updating that #pragma comment(lib, ...) and deleting three DLLs
# from bin64. See README.deps.
. "$PSScriptRoot\..\env.ps1"

$src   = Join-Path $PSScriptRoot 'curl'
$build = Join-Path $PSScriptRoot 'curl\build-win-Release'
Build-CMakeProject -Source $src -BuildDir $build -Config Release -Options @(
    '-DBUILD_SHARED_LIBS=ON', '-DBUILD_CURL_EXE=OFF', '-DBUILD_TESTING=OFF',
    '-DCURL_USE_SCHANNEL=ON', '-DCURL_USE_LIBPSL=OFF', '-DCURL_ZLIB=OFF',
    '-DCURL_USE_LIBSSH2=OFF', '-DUSE_NGHTTP2=OFF')

$imp = Get-ChildItem $build -Recurse -Filter 'libcurl*.lib' | Select-Object -First 1
$dll = Get-ChildItem $build -Recurse -Filter 'libcurl*.dll' | Select-Object -First 1
if (-not $imp) { throw "build_curl: import library not produced" }
if (-not $dll) { throw "build_curl: DLL not produced" }
Install-Artifact -Path $imp.FullName -Destination $XL_LIB_DIR -NewName 'libcurl.lib'
Install-Artifact -Path $imp.FullName -Destination $XL_DBG_DIR -NewName 'libcurl.lib'
Install-Artifact -Path $dll.FullName -Destination $XL_BIN_DIR
Copy-Item (Join-Path $src 'include\curl') $XL_INC_DIR -Recurse -Force
Write-Host "==> curl done" -ForegroundColor Green
