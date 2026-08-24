# build_lua.ps1 - Windows analog of build_lua.sh.
#
# Lua ships no build system beyond a hand-written Makefile, so compile the
# library sources directly with cl. lua.c and luac.c are the standalone
# interpreter/compiler entry points and must be excluded from the library.
#
# NOTE: this builds the pinned submodule (Lua 5.4.x), whereas the binary
# currently committed in xLights' lib/windows64 is lua5.3.5-static.lib. That
# skew is exactly what this repo exists to remove, but it means xLights'
# #pragma comment(lib, "lua5.3.5-static.lib") must be updated to "lua.lib"
# when it switches to the bundle. See README.deps.

. "$PSScriptRoot\..\env.ps1"

$luaSrc = Join-Path $PSScriptRoot 'lua'
if (-not (Test-Path (Join-Path $luaSrc 'lua.c'))) { throw "build_lua: submodule not checked out ($luaSrc)" }

# Lua's sources sit flat in the repo root (not src/) in the upstream git mirror.
# lua.c/luac.c are the standalone interpreter and compiler entry points;
# ltests.c is Lua's internal test harness and only compiles in a LUA_DEBUG
# build. None of them belong in the library.
$sources = Get-ChildItem (Join-Path $luaSrc '*.c') |
           Where-Object { $_.Name -notin @('lua.c', 'luac.c', 'onelua.c', 'ltests.c') }
if ($sources.Count -eq 0) { throw "build_lua: no library sources found in $luaSrc" }
Write-Host ("==> lua: {0} source files" -f $sources.Count) -ForegroundColor Cyan

foreach ($cfg in @('Release', 'Debug')) {
    $obj = Join-Path $luaSrc "build-win-$cfg"
    Remove-Item -Recurse -Force $obj -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $obj | Out-Null

    # /MD and /MDd must match what xLights builds with; a CRT mismatch here
    # surfaces as duplicate-symbol or heap-corruption bugs far from the cause.
    $flags = if ($cfg -eq 'Release') { @('/O2', '/MD', '/DNDEBUG') } else { @('/Od', '/MDd', '/D_DEBUG') }

    # Build one flat argument array and splat it. Passing an array as a single
    # argument to a ValueFromRemainingArguments parameter collapses it into one
    # space-joined string, which cl then treats as a single (nonexistent) path.
    $clArgs = @('/nologo', '/c', '/Zi', '/W3', '/MP', '/D_CRT_SECURE_NO_WARNINGS') +
              $flags + @("/I$luaSrc") + $sources.FullName

    Push-Location $obj
    try {
        Invoke-Checked cl @clArgs
        $objs = @(Get-ChildItem '*.obj' | ForEach-Object { $_.FullName })
        if ($objs.Count -ne $sources.Count) {
            throw "build_lua: expected $($sources.Count) objects, got $($objs.Count)"
        }
        # Splat from a variable (@name). @(...) is an array *expression*, which
        # binds as a single argument and gets space-joined into one bogus flag.
        $libArgs = @('/nologo', "/OUT:$(Join-Path $obj 'lua.lib')") + $objs
        Invoke-Checked lib @libArgs
    } finally { Pop-Location }

    $dest = if ($cfg -eq 'Release') { $XL_LIB_DIR } else { $XL_DBG_DIR }
    Install-Artifact -Path (Join-Path $obj 'lua.lib') -Destination $dest
}

foreach ($h in @('lua.h', 'luaconf.h', 'lualib.h', 'lauxlib.h')) {
    Install-Artifact -Path (Join-Path $luaSrc $h) -Destination $XL_INC_DIR
}
Write-Host "==> lua done" -ForegroundColor Green
