# build_shader_translate.ps1 - Windows analog of build_shader_translate.sh.
#
# glslang (GLSL->SPIR-V) + SPIRV-Tools (spirv-opt) + SPIRV-Cross, used by the
# runtime shader-translation path. Release only, installed into both lib/ and
# libdbg/ - the macOS leg makes the same call: these translators are not
# perf- or debug-sensitive enough to justify doubling the build time.
#
# On Windows xLights currently points AdditionalLibraryDirectories at
# ..\dependencies\glslang-build\install\lib, a hand-made tree. This replaces it.
. "$PSScriptRoot\..\env.ps1"

$stage = Join-Path $PSScriptRoot '.shader_translate_stage_win'
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$glslang = Join-Path $PSScriptRoot 'glslang'
$cross   = Join-Path $PSScriptRoot 'SPIRV-Cross'
foreach ($p in @($glslang, $cross)) {
    if (-not (Test-Path (Join-Path $p 'CMakeLists.txt'))) { throw "build_shader_translate: missing $p" }
}

# glslang pulls version-matched SPIRV-Tools + SPIRV-Headers into External/ via
# its own updater; without this the ENABLE_OPT build cannot find SPIRV-Tools.
Write-Host "==> glslang: fetching External sources" -ForegroundColor Cyan
# Windows ships an "App execution alias" stub at
# %LOCALAPPDATA%\Microsoft\WindowsApps\python.exe that is NOT Python - it
# exits 9009 and tells you to visit the Store. Get-Command finds it happily, so
# probe each candidate by actually running it rather than trusting the lookup.
function Find-Python {
    $cands = @(Get-Command python.exe, python3.exe, py.exe -All -ErrorAction SilentlyContinue |
               ForEach-Object { $_.Source })
    foreach ($p in ($cands | Select-Object -Unique)) {
        $out = & $p --version 2>&1
        if ($LASTEXITCODE -eq 0 -and "$out" -match 'Python\s+3') { return $p }
    }
    return $null
}
$python = Find-Python
if (-not $python) {
    throw ("build_shader_translate: a real Python 3 is required by " +
           "update_glslang_sources.py, but none was found (the " +
           "WindowsApps\python.exe stub does not count). Install Python 3 - " +
           "e.g. winget install Python.Python.3.12 - and reopen the shell. " +
           "GitHub runners ship one preinstalled.")
}
Write-Host "    python: $python" -ForegroundColor DarkGray
Push-Location $glslang
try { Invoke-Checked $python update_glslang_sources.py } finally { Pop-Location }

$common = @(
    '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
    "-DCMAKE_INSTALL_PREFIX=$stage",
    '-DBUILD_SHARED_LIBS=OFF')

Build-CMakeProject -Source $glslang -BuildDir (Join-Path $glslang 'build-win-Release') -Config Release -Options (
    $common + @('-DENABLE_OPT=ON', '-DGLSLANG_TESTS=OFF', '-DENABLE_GLSLANG_BINARIES=OFF',
                '-DGLSLANG_ENABLE_INSTALL=ON', '-DSPIRV_SKIP_TESTS=ON', '-DSPIRV_SKIP_EXECUTABLES=ON'))
Invoke-Checked $XL_CMAKE --build (Join-Path $glslang 'build-win-Release') --target install

Build-CMakeProject -Source $cross -BuildDir (Join-Path $cross 'build-win-Release') -Config Release -Options (
    $common + @('-DSPIRV_CROSS_ENABLE_TESTS=OFF', '-DSPIRV_CROSS_CLI=OFF',
                '-DSPIRV_CROSS_STATIC=ON', '-DSPIRV_CROSS_SHARED=OFF',
                '-DSPIRV_CROSS_ENABLE_C_API=ON'))
Invoke-Checked $XL_CMAKE --build (Join-Path $cross 'build-win-Release') --target install

# MSVC drops the lib prefix and uses .lib; this is the macOS LIBS list mapped
# onto those names.
$libs = @('glslang.lib', 'SPIRV.lib', 'MachineIndependent.lib', 'GenericCodeGen.lib',
          'glslang-default-resource-limits.lib', 'OSDependent.lib',
          'SPIRV-Tools-opt.lib', 'SPIRV-Tools.lib',
          'spirv-cross-msl.lib', 'spirv-cross-glsl.lib', 'spirv-cross-core.lib')
foreach ($l in $libs) {
    $src = Join-Path $stage "lib\$l"
    Install-Artifact -Path $src -Destination $XL_LIB_DIR
    Install-Artifact -Path $src -Destination $XL_DBG_DIR
}
foreach ($d in @('glslang', 'spirv-tools', 'spirv_cross')) {
    Copy-Item (Join-Path $stage "include\$d") $XL_INC_DIR -Recurse -Force
}
Remove-Item -Recurse -Force $stage
Write-Host "==> shader_translate done" -ForegroundColor Green
