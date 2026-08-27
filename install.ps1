# install.ps1 -- wire the Assert.IQ agent pack into a repo for dual-target use.
# Idempotent: safe to re-run.
#
# What it does:
#   1. Renders .assert-iq\dreaming\session-events.json from its template with
#      the pack root baked in (VS Code Copilot has no env equivalent of
#      CLAUDE_PLUGIN_ROOT, so the absolute path must be substituted at
#      install time).
#   2. Syncs the rendered file -> .claude\settings.json (hooks key -- the
#      harness contract), preserving any other keys you already have there.
#      Written via staged temp file + Move-Item so an interrupt mid-write
#      cannot truncate your existing settings.
#   3. Scaffolds the Dreaming memory store at .assert-iq\memory\.
#   4. Creates .claude\skills as a symlink to ..\.github\skills so Claude
#      Code discovers the same skills Copilot does. Falls back to copy when
#      symlink creation requires Developer Mode and that mode is off.
#
# Copilot needs no extra wiring -- it reads .github\* natively.
#
# Uninstall: pass -Uninstall to reverse the above. Other keys in
# .claude\settings.json and your .assert-iq\memory\ store are preserved.

[CmdletBinding()]
param(
    [switch]$Uninstall,
    # No-op; accepted for parity with bootstrap.ps1 (no prompts here).
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

# UTF-8 WITHOUT BOM, ON EVERY HOST.
#
# `Set-Content -Encoding UTF8` writes a byte-order mark on Windows PowerShell
# 5.1; PowerShell 7's UTF8 means UTF-8 *without* BOM. The pack's Python tooling
# reads JSON with encoding="utf-8", which REJECTS a BOM
# (json.JSONDecodeError: Expecting value: line 1 column 1), so on a stock
# Windows box every JSON file written here -- dream state, verdicts, the install
# manifest, .claude/settings.json -- became unparseable to calibration.py,
# memory-sanity.py, the verdict recorder and dreaming_service.py. The
# `-Encoding utf8NoBOM` value that would fix this exists only in PowerShell 6+,
# so write through .NET instead. Semantics match Set-Content: an array is joined
# with newlines and a trailing newline is added unless -NoNewline is given.
$script:AiqUtf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-AiqUtf8 {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter()][AllowEmptyString()][AllowNull()] $Value,
        [switch] $NoNewline,
        [switch] $Append
    )
    if ($null -eq $Value) { $Value = @() }
    # Order matters. A [string] is itself IEnumerable (of chars), so it must be
    # tested FIRST. And the collection test must be IEnumerable, not
    # [System.Array]: several callers pass a
    # System.Collections.Generic.List[string], which is NOT an array. Getting
    # that wrong sent a List down the [string] cast, which joins with $OFS -- a
    # SPACE -- collapsing .git/info/exclude into a single line so git matched
    # nothing and trial mode silently stopped hiding anything.
    if ($Value -is [string]) {
        $text = $Value
    } elseif ($Value -is [System.Collections.IEnumerable]) {
        $text = (@($Value) | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    } else {
        $text = [string]$Value
    }
    if (-not $NoNewline -and $text.Length -ge 0) { $text += [Environment]::NewLine }
    if ($Append) {
        [System.IO.File]::AppendAllText($Path, $text, $script:AiqUtf8NoBom)
    } else {
        [System.IO.File]::WriteAllText($Path, $text, $script:AiqUtf8NoBom)
    }
}

$root         = Split-Path -Parent $PSCommandPath
$eventsTpl    = Join-Path $root '.assert-iq\dreaming\session-events.template.json'
$eventsSrc    = Join-Path $root '.assert-iq\dreaming\session-events.json'
# Claude Code needs a DIFFERENT hook shape than VS Code Copilot; see the
# comment at the sync step below. Rendered from its own template.
$claudeHooksTpl = Join-Path $root '.assert-iq\dreaming\claude-hooks.windows.template.json'
$claudeHooksSrc = Join-Path $root '.assert-iq\dreaming\.claude-hooks.rendered.json'
$memoryDir    = Join-Path $root '.assert-iq\memory'
$hooksSrcLegacy = Join-Path $root 'hooks\hooks.json'
$settingsDst  = Join-Path $root '.claude\settings.json'
$skillsDst    = Join-Path $root '.claude\skills'
$skillsSrcRel = '..\.github\skills'
$skillsSrcAbs = Join-Path $root '.github\skills'
$renderLib    = Join-Path $root '.assert-iq\dreaming\scripts\lib\render-events.ps1'

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
                Write-AiqUtf8 -Path $tmp -Value ([pscustomobject]$out | ConvertTo-Json -Depth 32)
                Move-Item -LiteralPath $tmp -Destination $settingsDst -Force
                Say "[ok] stripped hooks key from $settingsDst"
            }
        } catch {
            Say "[skip] could not parse ${settingsDst}: $_  (left untouched)"
        }
    }
    if (Test-Path -LiteralPath $eventsSrc -PathType Leaf) {
        Remove-Item -LiteralPath $eventsSrc -Force -ErrorAction SilentlyContinue
        Say "[ok] removed $eventsSrc"
    }
    if (Test-Path -LiteralPath $claudeHooksSrc -PathType Leaf) {
        Remove-Item -LiteralPath $claudeHooksSrc -Force -ErrorAction SilentlyContinue
        Say "[ok] removed $claudeHooksSrc"
    }
    if (Test-Path -LiteralPath $hooksSrcLegacy -PathType Leaf) {
        Remove-Item -LiteralPath $hooksSrcLegacy -Force -ErrorAction SilentlyContinue
        Say "[ok] removed legacy $hooksSrcLegacy"
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
    Say 'Your .assert-iq\memory\ store is preserved.'
    return
}

if (-not (Test-Path -LiteralPath $eventsTpl)) { Fail "missing $eventsTpl" }
if (-not (Test-Path -LiteralPath $renderLib)) { Fail "missing $renderLib" }

. $renderLib

New-Item -ItemType Directory -Force -Path (Join-Path $root '.claude\agents') | Out-Null

# ---- 0. scaffold the Dreaming memory store -------------------------------
New-Item -ItemType Directory -Force -Path (Join-Path $memoryDir 'topics') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $memoryDir 'logs') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $memoryDir '.dream') | Out-Null

# Verdict archive (v1.7.0+) and pre-dream memory snapshots. Both are
# git-ignored runtime sinks, so a fresh clone has neither; without them the
# first /risk-assess-pr or /dream has nowhere to write.
New-Item -ItemType Directory -Force -Path (Join-Path $root '.assert-iq\verdicts\archive') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $root '.assert-iq\dreaming\.snapshots') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $root '.assert-iq\business-metrics\reports') | Out-Null
$statePath = Join-Path $memoryDir '.dream\state.json'
if (-not (Test-Path -LiteralPath $statePath)) {
    Write-AiqUtf8 -Path $statePath -Value "{`n  `"last_dream_utc`": null,`n  `"sessions_since_dream`": 0`n}"
}
# MEMORY.md is git-ignored (never ship maintainer memory); seed a clean index
# if this clone doesn't have one yet.
$memoryIndex = Join-Path $memoryDir 'MEMORY.md'
if (-not (Test-Path -LiteralPath $memoryIndex)) {
    $seed = @'
# MEMORY.md -- Project Memory Index

_Last consolidated: never -- run `/dream` to populate_

<!--
Long-term memory INDEX for the Assert.IQ Dreaming feature (loaded at session
start, index only). Maintained by the /dream consolidation pass:
  - Hard cap: 200 lines; one-line pointers into topics/.
  - Absolute dates only. Facts/decisions/preferences, not transcript excerpts.
Hand-edit freely; the instruction files under .github/instructions/ are the
immutable rules tier and are never modified by dreaming.
-->

## Architecture

_(no entries yet)_

## Workflow

_(no entries yet)_

## Active Gotchas

_(no entries yet)_
'@
    Write-AiqUtf8 -Path $memoryIndex -Value $seed
}
Say "[ok] ensured Dreaming memory store at .assert-iq\memory\"

# ---- 1. render session-events wiring from template -----------------------
Render-EventsTemplate -Template $eventsTpl -Out $eventsSrc -PackRoot $root
Say "[ok] rendered .assert-iq\dreaming\session-events.json (pack root: $root)"

# ---- 1. sync hooks block -------------------------------------------------
# IMPORTANT: .claude\settings.json is NOT a copy of session-events.json. The two
# consumers use incompatible hook schemas:
#
#   VS Code Copilot : handlers sit directly in the event array and support
#                     osx/linux/windows command overrides.
#   Claude Code     : requires a matcher-group wrapper with a nested "hooks"
#                     array, has no platform keys, and picks the interpreter via
#                     a "shell" field.
#
# Copying the Copilot shape into .claude\settings.json yields a file Claude Code
# silently ignores -- exactly how Dreaming came to be dead under Claude Code
# while still working under VS Code on macOS. Render the Claude-shaped template
# (Windows variant: powershell handlers, so the bash/python3 path is never used
# on Windows). Enforced by unit-hook-schema.py.
if (-not (Test-Path -LiteralPath $claudeHooksTpl)) { Fail "missing $claudeHooksTpl" }
Render-EventsTemplate -Template $claudeHooksTpl -Out $claudeHooksSrc -PackRoot $root

# Stage the merged JSON to a sibling temp file, validate non-empty, then
# atomically Move-Item into place. Prevents truncation of the user's
# existing .claude\settings.json on interrupt or partial-write.
$newHooksRaw = Get-Content -LiteralPath $claudeHooksSrc -Raw
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
    Write-AiqUtf8 -Path $settingsTmp -Value $merged
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
    # Create the link from INSIDE its parent directory. NTFS stores a relative
    # symlink target verbatim and resolves it against the link's own directory,
    # but Windows PowerShell 5.1 first validates -Target against the CURRENT
    # working directory. Run install.ps1 from anywhere other than the pack root
    # and 5.1 rejected '..\.github\skills' ("Cannot find path
    # 'C:\Users\<you>\.github\skills'"), silently degrading .claude\skills to a
    # COPY even with Developer Mode enabled. Pushing to the parent makes the
    # validation agree with the filesystem while keeping the stored target
    # relative -- which matters, because bootstrap.ps1 recognises a pack-owned
    # link by comparing that exact relative string.
    $skillsParent = Split-Path -Parent $skillsDst
    Push-Location -LiteralPath $skillsParent
    try {
        New-Item -ItemType SymbolicLink -Path $skillsDst -Target $skillsSrcRel -ErrorAction Stop | Out-Null
    } finally {
        Pop-Location
    }
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
Say "  Claude  reads CLAUDE.md, .claude\agents\*, .claude\skills\*, .claude\settings.json (session events)"
Say "  Dreaming memory store: .assert-iq\memory\ (run /dream to consolidate)"
