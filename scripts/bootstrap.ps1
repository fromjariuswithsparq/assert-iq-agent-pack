# Assert.IQ Agent Pack — workspace bootstrap (Windows / PowerShell)
#
# Copies workspace-loaded surfaces (instructions, .assert-iq/, CLAUDE.md,
# copilot-instructions.md, AGENTS.md) from a plugin install into the
# user's workspace or user-global slots. Flag-driven; no interactive
# prompts (the agent does the prompting in chat).
#
# See .github\skills\assert-iq-bootstrap\SKILL.md for full docs.

[CmdletBinding()]
param(
    [ValidateSet('solo', 'pod', '')]
    [string]$Preset = '',

    [ValidateSet('workspace', 'user', 'skip', '')]
    [string]$AssertIq = '',

    [ValidateSet('workspace', 'user', 'skip', '')]
    [string]$Instructions = '',

    [ValidateSet('workspace', 'user', 'skip', '')]
    [string]$Claude = '',

    [ValidateSet('workspace', 'user', 'skip', '')]
    [string]$Copilot = '',

    [ValidateSet('workspace', 'user', 'skip', '')]
    [string]$Agents = '',

    [string]$Workspace = (Get-Location).Path,

    [string]$Source = ''
)

$ErrorActionPreference = 'Stop'

# ---- Resolve source ---------------------------------------------------------
if (-not $Source) {
    if ($env:CLAUDE_PLUGIN_ROOT) {
        $Source = $env:CLAUDE_PLUGIN_ROOT
    } else {
        $Source = Split-Path -Parent $PSScriptRoot
        if (-not $Source) { $Source = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
    }
}

# ---- Apply preset defaults --------------------------------------------------
switch ($Preset) {
    'solo' {
        if (-not $AssertIq)     { $AssertIq     = 'workspace' }
        if (-not $Instructions) { $Instructions = 'user' }
        if (-not $Claude)       { $Claude       = 'user' }
        if (-not $Copilot)      { $Copilot      = 'workspace' }
        if (-not $Agents)       { $Agents       = 'workspace' }
    }
    default {
        # pod (and unset)
        if (-not $AssertIq)     { $AssertIq     = 'workspace' }
        if (-not $Instructions) { $Instructions = 'workspace' }
        if (-not $Claude)       { $Claude       = 'workspace' }
        if (-not $Copilot)      { $Copilot      = 'workspace' }
        if (-not $Agents)       { $Agents       = 'workspace' }
    }
}

# ---- Resolve user-global paths by OS ----------------------------------------
$isWin = $IsWindows -or ($env:OS -eq 'Windows_NT')
if ($isWin) {
    $userPrompts = Join-Path $env:APPDATA 'Code\User\prompts'
    $userAssertIq = Join-Path $env:USERPROFILE '.assert-iq'
    $userClaudeMd = Join-Path $env:USERPROFILE '.claude\CLAUDE.md'
} elseif ($IsMacOS) {
    $userPrompts  = Join-Path $HOME 'Library/Application Support/Code/User/prompts'
    $userAssertIq = Join-Path $HOME '.assert-iq'
    $userClaudeMd = Join-Path $HOME '.claude/CLAUDE.md'
} else {
    $userPrompts  = Join-Path $HOME '.config/Code/User/prompts'
    $userAssertIq = Join-Path $HOME '.assert-iq'
    $userClaudeMd = Join-Path $HOME '.claude/CLAUDE.md'
}

# ---- Result tracking --------------------------------------------------------
$results = New-Object System.Collections.Generic.List[object]

function Record($label, $result, $dst) {
    $results.Add([pscustomobject]@{
        Surface     = $label
        Result      = $result
        Destination = $dst
    }) | Out-Null
}

function Copy-IfAbsent {
    param([string]$Label, [string]$Src, [string]$Dst)

    if (-not (Test-Path -LiteralPath $Src)) {
        Record $Label 'missing-source' $Src
        return
    }
    if (Test-Path -LiteralPath $Dst) {
        Record $Label 'skipped (already present)' $Dst
        return
    }

    $parent = Split-Path -Parent $Dst
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    if ((Get-Item -LiteralPath $Src).PSIsContainer) {
        Copy-Item -LiteralPath $Src -Destination $Dst -Recurse -Force:$false
    } else {
        Copy-Item -LiteralPath $Src -Destination $Dst -Force:$false
    }
    Record $Label 'copied' $Dst
}

# ---- Per-surface handlers ---------------------------------------------------
function Process-AssertIq {
    switch ($AssertIq) {
        'workspace' { Copy-IfAbsent '.assert-iq' (Join-Path $Source '.assert-iq') (Join-Path $Workspace '.assert-iq') }
        'user'      { Copy-IfAbsent '.assert-iq' (Join-Path $Source '.assert-iq') $userAssertIq }
        'skip'      { Record '.assert-iq' 'skipped (user choice)' '-' }
        default     { throw "Invalid -AssertIq: '$AssertIq'" }
    }
}

function Process-Instructions {
    $src = Join-Path $Source '.github\instructions'
    if (-not (Test-Path -LiteralPath $src)) {
        Record 'instructions' 'missing-source' $src
        return
    }

    switch ($Instructions) {
        'workspace' {
            $dest = Join-Path $Workspace '.github\instructions'
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            Get-ChildItem -LiteralPath $src -Filter '*.instructions.md' | ForEach-Object {
                Copy-IfAbsent "instructions/$($_.Name)" $_.FullName (Join-Path $dest $_.Name)
            }
        }
        'user' {
            New-Item -ItemType Directory -Force -Path $userPrompts | Out-Null
            Get-ChildItem -LiteralPath $src -Filter '*.instructions.md' | ForEach-Object {
                Copy-IfAbsent "instructions/$($_.Name)" $_.FullName (Join-Path $userPrompts $_.Name)
            }
        }
        'skip' { Record 'instructions' 'skipped (user choice)' '-' }
        default { throw "Invalid -Instructions: '$Instructions'" }
    }
}

function Process-Claude {
    $src = Join-Path $Source 'CLAUDE.md'
    switch ($Claude) {
        'workspace' { Copy-IfAbsent 'CLAUDE.md' $src (Join-Path $Workspace 'CLAUDE.md') }
        'user'      { Copy-IfAbsent 'CLAUDE.md' $src $userClaudeMd }
        'skip'      { Record 'CLAUDE.md' 'skipped (user choice)' '-' }
        default     { throw "Invalid -Claude: '$Claude'" }
    }
}

function Process-Copilot {
    $src = Join-Path $Source '.github\copilot-instructions.md'
    switch ($Copilot) {
        'workspace' {
            Copy-IfAbsent 'copilot-instructions.md' $src (Join-Path $Workspace '.github\copilot-instructions.md')
        }
        'user' {
            Write-Warning 'copilot-instructions.md has no native user-global slot. Skipping.'
            Write-Warning '  (The .instructions.md files under -Instructions user cover the same QI rules and load globally.)'
            Record 'copilot-instructions.md' 'skipped (no user-global slot)' '-'
        }
        'skip' { Record 'copilot-instructions.md' 'skipped (user choice)' '-' }
        default { throw "Invalid -Copilot: '$Copilot'" }
    }
}

function Process-Agents {
    $src = Join-Path $Source 'AGENTS.md'
    switch ($Agents) {
        'workspace' { Copy-IfAbsent 'AGENTS.md' $src (Join-Path $Workspace 'AGENTS.md') }
        'user' {
            Write-Warning 'AGENTS.md has no native user-global slot. Skipping.'
            Record 'AGENTS.md' 'skipped (no user-global slot)' '-'
        }
        'skip' { Record 'AGENTS.md' 'skipped (user choice)' '-' }
        default { throw "Invalid -Agents: '$Agents'" }
    }
}

Process-AssertIq
Process-Instructions
Process-Claude
Process-Copilot
Process-Agents

# ---- Summary ----------------------------------------------------------------
Write-Host ''
Write-Host '=== Assert.IQ bootstrap summary ==='
Write-Host "Source:    $Source"
Write-Host "Workspace: $Workspace"
$presetLabel = if ($Preset) { $Preset } else { '(none)' }
Write-Host "Preset:    $presetLabel"
Write-Host ''
$results | Format-Table -AutoSize Surface, Result, Destination
Write-Host ''
Write-Host 'Reload your editor window so the new instructions and config are picked up:'
Write-Host '  - VS Code:     Ctrl+Shift+P -> "Developer: Reload Window"'
Write-Host '  - Claude Code: restart the session'
