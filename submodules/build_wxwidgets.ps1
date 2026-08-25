# build_wxwidgets.ps1 - Windows analog of build_wxwidgets.sh.
#
# Builds the pinned wxWidgets fork with the MSVC solution and installs it into
# the bundle as wxWidgets/{include,lib/vc_x64_lib}. Consumers point
# WXWIDGETS_ROOT at that directory - which is exactly what xLights'
# Xlights.vcxproj LibraryPath already expects, so no project change is needed.
#
# This is the single biggest developer win in the bundle: today a Windows
# contributor has to clone and build wxWidgets by hand before xLights will
# link, and xLights' win_CI.yml builds it from HEAD rather than the pinned tag
# the macOS leg uses.
#
# Note on setup.h: the macOS leg passes --enable-std_containers and
# --enable-std_string_conv_in_wxstring. On MSW those come from
# include/wx/msw/setup.h, and the xLightsSequencer fork already ships both set
# to 1, so the two platforms agree with no patching. (xLights carries a
# build_scripts/msw/wxwidgets_win.patch for this; against this fork it is
# vestigial.) If that ever drifts, wx and xLights disagree about wxString's
# ABI and the failure is a link error, not a warning - so verify rather than
# assume when bumping the pin.

. "$PSScriptRoot\..\env.ps1"

$wx = Join-Path $PSScriptRoot 'wxWidgets'
if (-not (Test-Path (Join-Path $wx 'build\msw\wx_vc17.sln'))) {
    throw "build_wxwidgets: submodule not checked out ($wx)"
}

# wx vendors zlib/png/expat/tiff/jpeg/pcre/scintilla/lexilla/libwebp as its own
# submodules; without them the solution fails partway through.
Write-Host "==> wxWidgets: initialising vendored submodules" -ForegroundColor Cyan
Push-Location $wx
try { Invoke-Checked git submodule update --init --recursive --depth 1 }
finally { Pop-Location }

$sln    = Join-Path $wx 'build\msw\wx_vc17.sln'
$libSrc = Join-Path $wx 'lib\vc_x64_lib'

# The exact libraries xLights links, mirroring the #pragma comment(lib, ...)
# block in src-ui-wx/xLightsApp.cpp. {0} = wx version tag, {1} = debug suffix.
$requiredTemplates = @(
    'wxbase{0}u{1}.lib', 'wxbase{0}u{1}_net.lib', 'wxbase{0}u{1}_xml.lib',
    'wxmsw{0}u{1}_core.lib', 'wxmsw{0}u{1}_aui.lib', 'wxmsw{0}u{1}_gl.lib',
    'wxmsw{0}u{1}_qa.lib', 'wxmsw{0}u{1}_html.lib', 'wxmsw{0}u{1}_propgrid.lib',
    'wxscintilla{1}.lib', 'wxregexu{1}.lib', 'wxtiff{1}.lib', 'wxjpeg{1}.lib',
    'wxpng{1}.lib', 'wxzlib{1}.lib', 'wxexpat{1}.lib', 'wxwebp{1}.lib'
)

# Returns the list of xLights-required libraries MISSING from $libSrc, or the
# sentinel '<no-build>' when nothing has been built at all. Empty list = ready.
function Get-MissingWxLibs {
    if (-not (Test-Path $libSrc)) { return ,@('<no-build>') }
    $baseLib = Get-ChildItem $libSrc -Filter 'wxbase*u.lib' -ErrorAction SilentlyContinue |
               Select-Object -First 1
    if (-not $baseLib -or $baseLib.Name -notmatch '^wxbase(\d+)u\.lib$') { return ,@('<no-build>') }
    $wxVer = $Matches[1]
    $missing = @()
    foreach ($suffix in @('', 'd')) {
        foreach ($tpl in $requiredTemplates) {
            $name = $tpl -f $wxVer, $suffix
            if (-not (Test-Path (Join-Path $libSrc $name))) { $missing += $name }
        }
    }
    foreach ($sh in @('mswu\wx\setup.h', 'mswud\wx\setup.h')) {
        if (-not (Test-Path (Join-Path $libSrc $sh))) { $missing += $sh }
    }
    return ,$missing
}

# Skip the (very long) msbuild when a complete build for THIS EXACT wx commit is
# already present. CI always starts from a clean runner, so this only ever
# helps a developer rebuilding locally.
#
# The commit check is the load-bearing part. Testing only for the presence of
# the libraries would silently reuse a stale build after the wx submodule pin
# moves - linking libraries from the previous wx against the current headers.
# Set XL_FORCE_REBUILD=1 to rebuild regardless.
$stampFile = Join-Path $libSrc '.xl-built-from'
$wxCommit = (& git -C $wx rev-parse HEAD 2>$null)
$stamped = if (Test-Path $stampFile) { (Get-Content $stampFile -Raw).Trim() } else { '' }

[object[]]$missing = Get-MissingWxLibs
if ($missing.Count -eq 0 -and $wxCommit -and $stamped -eq $wxCommit -and -not $env:XL_FORCE_REBUILD) {
    Write-Host "==> wxWidgets: complete build already present, skipping msbuild" -ForegroundColor Green
} else {
    if ($missing -contains '<no-build>') {
        Write-Host "    no existing wx build found" -ForegroundColor DarkGray
    } elseif ($missing.Count -gt 0) {
        Write-Host ("    incomplete wx build ({0} missing, e.g. {1})" -f $missing.Count, $missing[0]) -ForegroundColor DarkGray
    } elseif ($stamped -ne $wxCommit) {
        Write-Host ("    existing wx build is from a different commit ({0} != {1}); rebuilding" -f
                    $(if ($stamped) { $stamped.Substring(0, [Math]::Min(10, $stamped.Length)) } else { 'unstamped' }),
                    $wxCommit.Substring(0, 10)) -ForegroundColor DarkGray
    }

    # Both configurations write into lib\vc_x64_lib - Release as wx*.lib with
    # setup.h under mswu\, Debug as wx*d.lib under mswud\. xLights links the
    # 'd' variants in its Debug configuration, so a Release-only build (what
    # xLights CI does today) leaves developers unable to build Debug at all.
    foreach ($cfg in @('Release', 'Debug')) {
        Write-Host "==> wxWidgets ($cfg x64)" -ForegroundColor Cyan
        Invoke-Checked $XL_MSBUILD /m /nologo /v:minimal $sln `
            "/p:Configuration=$cfg" '/p:Platform=x64'
    }
}

# Verify the bundle actually satisfies xLights rather than just "msbuild said
# ok". msbuild can report success while skipping projects, and a missing debug
# library only surfaces later, as a link error on a developer's machine.
[object[]]$missing = Get-MissingWxLibs
if ($missing.Count -gt 0) {
    throw ("build_wxwidgets: xLights requires libraries the build did not produce: " +
           ($missing -join ', '))
}
Write-Host ("    all {0} xLights-required libraries present (release + debug)" -f ($requiredTemplates.Count * 2)) -ForegroundColor DarkGray

# Record which wx commit produced this build so a later run can tell whether it
# is still current rather than assuming presence means correctness.
if ($wxCommit) { Set-Content -Path $stampFile -Value $wxCommit -NoNewline }

Write-Host "==> wxWidgets: installing into bundle" -ForegroundColor Cyan
Remove-Item -Recurse -Force $XL_WX_DIR -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $XL_WX_DIR 'lib') | Out-Null
Copy-Item (Join-Path $wx 'include') $XL_WX_DIR -Recurse -Force
Copy-Item $libSrc (Join-Path $XL_WX_DIR 'lib') -Recurse -Force

$total = (Get-ChildItem $XL_WX_DIR -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ("==> wxWidgets done ({0:N0} MB)" -f ($total / 1MB)) -ForegroundColor Green
