# install.ps1 — wire the Assert.IQ agent pack into a repo for dual-target use.
# Idempotent: safe to re-run.
#
# What it does:
#   1. Renders hooks\hooks.json from hooks\hooks.template.json with the
#      pack root baked in (VS Code Copilot has no env equivalent of
#      CLAUDE_PLUGIN_ROOT, so the absolute path must be substituted at
#      install time).
#   2. Syncs hooks\hooks.json -> .claude\settings.json (hooks key),
#      preserving any other keys you already have in .claude\settings.json.
#      Written via staged temp file + Move-Item so an interrupt mid-write
#      cannot truncate your existing settings.
#   3. Creates .claude\skills as a symlink to ..\.github\skills so Claude
#      Code discovers the same skills Copilot does. Falls back to copy when
#      symlink creation requires Developer Mode and that mode is off.
#
# Copilot needs no extra wiring — it reads .github\* natively.
#
# Uninstall: pass -Uninstall to reverse the above. Other keys in
# .claude\settings.json are preserved (only the hooks key is stripped).

[CmdletBinding()]
param(
    [switch]$Uninstall,
    # No-op; accepted for parity with bootstrap.ps1 (no prompts here).
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$root         = Split-Path -Parent $PSCommandPath
$hooksTpl     = Join-Path $root 'hooks\hooks.template.json'
$hooksSrc     = Join-Path $root 'hooks\hooks.json'
$settingsDst  = Join-Path $root '.claude\settings.json'
$skillsDst    = Join-Path $root '.claude\skills'
$skillsSrcRel = '..\.github\skills'
$skillsSrcAbs = Join-Path $root '.github\skills'
$renderLib    = Join-Path $root 'hooks\scripts\lib\render-hooks.ps1'

function Say($msg) { Write-Host $msg }
function Fail($msg) { throw "install.ps1: $msg" }

# Defense-in-depth: refuse to operate if $root is empty or a filesystem root.
if ([string]::IsNullOrWhiteSpace($root) -or
    $root -match '^[A-Za-z]:\\?$' -or
    $root -eq '\' -or $root -eq '/') {
    Fail "refusing to operate at filesystem root (root='$root')"
}

# ---- Uninstall path ------------------------------------------------------
if ($Uninstall) {
    Say '=== Assert.IQ install.ps1: uninstall ==='
    if (Test-Path -LiteralPath $skillsDst) {
        # PS 5.1 will follow a directory symlink/junction with -Recurse and
        # delete the real .github\skills source. Detect and unlink instead.
        $skillsItem = Get-Item -LiteralPath $skillsDst -Force
        if ($skillsItem.LinkType -in @('SymbolicLink','Junction')) {
            try { [System.IO.Directory]::Delete($skillsDst) }
            catch { Remove-Item -LiteralPath $skillsDst -Force -ErrorAction SilentlyContinue }
        } else {
            Remove-Item -LiteralPath $skillsDst -Recurse -Force -ErrorAction SilentlyContinue
        }
        Say "[ok] removed $skillsDst"
    }
    if (Test-Path -LiteralPath $settingsDst -PathType Leaf) {
        try {
            $existing = Get-Content -LiteralPath $settingsDst -Raw | ConvertFrom-Json
            $out = [ordered]@{}
            foreach ($prop in $existing.PSObject.Properties) {
                if ($prop.Name -ne 'hooks') { $out[$prop.Name] = $prop.Value }
            }
            if ($out.Keys.Count -eq 0) {
                Remove-Item -LiteralPath $settingsDst -Force
                Say "[ok] removed $settingsDst (was hooks-only)"
            } else {
                $tmp = "$settingsDst.$([guid]::NewGuid().ToString('N')).tmp"
                Set-Content -LiteralPath $tmp -Value ([pscustomobject]$out | ConvertTo-Json -Depth 32) -Encoding UTF8
                Move-Item -LiteralPath $tmp -Destination $settingsDst -Force
                Say "[ok] stripped hooks key from $settingsDst"
            }
        } catch {
            Say "[skip] could not parse ${settingsDst}: $_  (left untouched)"
        }
    }
    if (Test-Path -LiteralPath $hooksSrc -PathType Leaf) {
        Remove-Item -LiteralPath $hooksSrc -Force -ErrorAction SilentlyContinue
        Say "[ok] removed $hooksSrc"
    }
    $claudeDir = Join-Path $root '.claude'
    if ((Test-Path -LiteralPath $claudeDir) -and `
        -not (Get-ChildItem -LiteralPath $claudeDir -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $claudeDir -Force -ErrorAction SilentlyContinue
        Say "[ok] removed empty .claude\"
    }
    Say ''
    Say 'Uninstall complete.'
    Say 'Pack source files (.github\, CLAUDE.md, AGENTS.md, etc.) are unchanged.'
    return
}

if (-not (Test-Path -LiteralPath $hooksTpl)) { Fail "missing $hooksTpl" }
if (-not (Test-Path -LiteralPath $renderLib)) { Fail "missing $renderLib" }

. $renderLib

New-Item -ItemType Directory -Force -Path (Join-Path $root '.claude\agents') | Out-Null

# ---- 0. render hooks.json from template ----------------------------------
Render-HooksTemplate -Template $hooksTpl -Out $hooksSrc -PackRoot $root
Say "[ok] rendered hooks\hooks.json (pack root: $root)"

# ---- 1. sync hooks block -------------------------------------------------
# Stage the merged JSON to a sibling temp file, validate non-empty, then
# atomically Move-Item into place. Prevents truncation of the user's
# existing .claude\settings.json on interrupt or partial-write.
$newHooksRaw = Get-Content -LiteralPath $hooksSrc -Raw
try {
    $newHooks = $newHooksRaw | ConvertFrom-Json
} catch {
    Fail "rendered $hooksSrc is not valid JSON: $($_.Exception.Message)"
}

if (Test-Path -LiteralPath $settingsDst) {
    $existingRaw = Get-Content -LiteralPath $settingsDst -Raw
    try {
        $existing = $existingRaw | ConvertFrom-Json
    } catch {
        Fail "existing $settingsDst is not valid JSON; left untouched"
    }
    if ($null -eq $existing) { $existing = [pscustomobject]@{} }
    $existing | Add-Member -NotePropertyName hooks -NotePropertyValue $newHooks.hooks -Force
    $merged = $existing | ConvertTo-Json -Depth 50
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $settingsDst) | Out-Null
    $merged = $newHooks | ConvertTo-Json -Depth 50
}

if ([string]::IsNullOrWhiteSpace($merged)) {
    Fail "refusing to write empty settings.json"
}

$settingsTmp = "$settingsDst.$([guid]::NewGuid().ToString('N')).tmp"
try {
    Set-Content -LiteralPath $settingsTmp -Value $merged -Encoding UTF8
    if (-not (Test-Path -LiteralPath $settingsTmp) -or
        (Get-Item -LiteralPath $settingsTmp).Length -eq 0) {
        Fail "staged settings file is empty: $settingsTmp"
    }
    Move-Item -LiteralPath $settingsTmp -Destination $settingsDst -Force
    $settingsTmp = $null
} finally {
    if ($settingsTmp -and (Test-Path -LiteralPath $settingsTmp)) {
        Remove-Item -LiteralPath $settingsTmp -Force -ErrorAction SilentlyContinue
    }
}
Say "[ok] synced hooks -> .claude\settings.json"

# ---- 2. wire skills ------------------------------------------------------
if (-not (Test-Path -LiteralPath $skillsSrcAbs)) {
    Fail "missing skills source: $skillsSrcAbs"
}
if (Test-Path -LiteralPath $skillsDst) {
    # Same LinkType-aware delete used in -Uninstall: PS 5.1 will follow a
    # directory symlink/junction with -Recurse and destroy the .github\skills
    # source. Detect link types and unlink them.
    $skillsItem = Get-Item -LiteralPath $skillsDst -Force
    if ($skillsItem.LinkType -in @('SymbolicLink','Junction')) {
        try { [System.IO.Directory]::Delete($skillsDst) }
        catch { Remove-Item -LiteralPath $skillsDst -Force -ErrorAction SilentlyContinue }
    } else {
        Remove-Item -Recurse -Force -LiteralPath $skillsDst
    }
}
try {
    New-Item -ItemType SymbolicLink -Path $skillsDst -Target $skillsSrcRel -ErrorAction Stop | Out-Null
    Say "[ok] linked .claude\skills -> $skillsSrcRel"
} catch {
    # Symlink creation on Windows requires Developer Mode or admin rights.
    # Fall back to a recursive copy so the install still succeeds.
    Copy-Item -Recurse -Force -LiteralPath $skillsSrcAbs -Destination $skillsDst
    Say "[ok] copied .github\skills -> .claude\skills (symlink unsupported: $($_.Exception.Message); re-run install.ps1 after skill changes)"
}

Say ""
Say "Pack installed."
Say "  Copilot reads .github\copilot-instructions.md, .github\instructions\*, .github\agents\*, .github\skills\*"
Say "  Claude  reads CLAUDE.md, .claude\agents\*, .claude\skills\*, .claude\settings.json (hooks)"
