# install.ps1 — wire the Assert.IQ agent pack into a repo for dual-target use.
# Idempotent: safe to re-run.
#
# What it does:
#   1. Syncs hooks\hooks.json -> .claude\settings.json (hooks key),
#      preserving any other keys you already have in .claude\settings.json.
#   2. Creates .claude\skills as a symlink to ..\.github\skills so Claude
#      Code discovers the same skills Copilot does. Falls back to copy when
#      symlink creation requires Developer Mode and that mode is off.
#
# Copilot needs no extra wiring — it reads .github\* natively.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root         = Split-Path -Parent $PSCommandPath
$hooksTpl     = Join-Path $root 'hooks\hooks.template.json'
$hooksSrc     = Join-Path $root 'hooks\hooks.json'
$settingsDst  = Join-Path $root '.claude\settings.json'
$skillsDst    = Join-Path $root '.claude\skills'
$skillsSrcRel = '..\.github\skills'
$skillsSrcAbs = Join-Path $root '.github\skills'

function Say($msg) { Write-Host $msg }
function Fail($msg) { Write-Error "install.ps1: $msg"; exit 1 }

if (-not (Test-Path $hooksTpl)) { Fail "missing $hooksTpl" }

New-Item -ItemType Directory -Force -Path (Join-Path $root '.claude\agents') | Out-Null

# ---- 0. render hooks.json from template ----------------------------------
# Substitute __PACK_ROOT__ with this absolute pack path. VS Code Copilot
# does not propagate any env var that carries the workspace path to hook
# commands, so the fallback path must be baked in at install time. Claude
# Code's CLAUDE_PLUGIN_ROOT still takes precedence at runtime. Backslashes
# in $root are doubled because the template embeds the path inside a
# PowerShell single-quoted string passed via -Command "& { ... }".
$packRootEscaped = $root.Replace('\','\\')
(Get-Content $hooksTpl -Raw) -replace '__PACK_ROOT__', $packRootEscaped |
    Set-Content -Path $hooksSrc -Encoding UTF8
Say "[ok] rendered hooks\hooks.json (pack root: $root)"

# ---- 1. sync hooks block -------------------------------------------------
$newHooks = Get-Content $hooksSrc -Raw | ConvertFrom-Json
if (Test-Path $settingsDst) {
    $existing = Get-Content $settingsDst -Raw | ConvertFrom-Json
    if ($null -eq $existing) { $existing = [pscustomobject]@{} }
    $existing | Add-Member -NotePropertyName hooks -NotePropertyValue $newHooks.hooks -Force
    $existing | ConvertTo-Json -Depth 50 | Set-Content -Path $settingsDst -Encoding UTF8
} else {
    $newHooks | ConvertTo-Json -Depth 50 | Set-Content -Path $settingsDst -Encoding UTF8
}
Say "[ok] synced hooks -> .claude\settings.json"

# ---- 2. wire skills ------------------------------------------------------
if (Test-Path $skillsDst) {
    Remove-Item -Recurse -Force $skillsDst
}
try {
    New-Item -ItemType SymbolicLink -Path $skillsDst -Target $skillsSrcRel -ErrorAction Stop | Out-Null
    Say "[ok] linked .claude\skills -> $skillsSrcRel"
} catch {
    Copy-Item -Recurse -Force $skillsSrcAbs $skillsDst
    Say "[ok] copied .github\skills -> .claude\skills (symlink unsupported; re-run install.ps1 after skill changes)"
}

Say ""
Say "Pack installed."
Say "  Copilot reads .github\copilot-instructions.md, .github\instructions\*, .github\agents\*, .github\skills\*"
Say "  Claude  reads CLAUDE.md, .claude\agents\*, .claude\skills\*, .claude\settings.json (hooks)"
