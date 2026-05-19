# Assert.IQ Agent Pack — workspace bootstrap (Windows / PowerShell)
#
# Copies workspace-loaded surfaces (instructions, .assert-iq/, CLAUDE.md,
# copilot-instructions.md, AGENTS.md) from a plugin install into the
# user's workspace or user-global slots.
#
# Three install modes:
#   -Mode committed   Files are visible to git; user opts in to commit.
#   -Mode trial       Files are added to .git/info/exclude (local-only,
#                     codebase .gitignore untouched). User can graduate
#                     to committed later with -Graduate.
#   -Mode ask         Interactive prompt (default when TTY). Non-TTY
#                     falls back to committed.
#
# Other switches:
#   -Graduate / -Untrial   Reverse trial mode: remove pack entries from
#                          .git/info/exclude. Files stay on disk.
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

    [ValidateSet('workspace', 'user', 'skip', '')]
    [string]$VSCode = '',

    [ValidateSet('workspace', 'skip', '')]
    [string]$Hooks = '',

    [ValidateSet('workspace', 'skip', '')]
    [string]$ClaudeSettings = '',

    [string]$Workspace = (Get-Location).Path,

    [string]$Source = '',

    [ValidateSet('trial', 'committed', 'ask', '')]
    [string]$Mode = '',

    [switch]$Trial,
    [switch]$Committed,
    [switch]$Graduate,
    [switch]$Untrial
)

$ErrorActionPreference = 'Stop'

# Resolve mode shorthand switches.
if ($Trial)     { $Mode = 'trial' }
if ($Committed) { $Mode = 'committed' }
$doGraduate = $Graduate -or $Untrial

$ExcludeBegin = '# >>> assert-iq trial mode (managed) >>>'
$ExcludeEnd   = '# <<< assert-iq trial mode (managed) <<<'

# ---- Resolve source ---------------------------------------------------------
if (-not $Source) {
    if ($env:CLAUDE_PLUGIN_ROOT) {
        $Source = $env:CLAUDE_PLUGIN_ROOT
    } else {
        $Source = Split-Path -Parent $PSScriptRoot
        if (-not $Source) { $Source = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
    }
}

# ---- Resolve user-global paths by OS ----------------------------------------
$isWin = $IsWindows -or ($env:OS -eq 'Windows_NT')
if ($isWin) {
    $userPrompts  = Join-Path $env:APPDATA 'Code\User\prompts'
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

$manifestPath = Join-Path $Workspace '.assert-iq\.install-manifest.json'

# =============================================================================
# Manifest, sha256, git-exclude helpers
# =============================================================================

$script:ManifestEntries = New-Object System.Collections.Generic.List[object]
$script:ConflictBulkChoice = ''   # 'K', 'O', 'S', or ''

function Get-Sha256($path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
}

function Manifest-Add($action, $path, $scope) {
    $script:ManifestEntries.Add([pscustomobject]@{
        action = $action
        path   = $path
        scope  = $scope
    }) | Out-Null
}

function Manifest-Write {
    $outDir = Split-Path -Parent $manifestPath
    if (-not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }

    $packVersion = 'unknown'
    $pluginJson = Join-Path $Source '.claude-plugin\plugin.json'
    if (Test-Path -LiteralPath $pluginJson) {
        try {
            $pv = (Get-Content -LiteralPath $pluginJson -Raw | ConvertFrom-Json).version
            if ($pv) { $packVersion = $pv }
        } catch {}
    }
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Merge with existing manifest if present (preserve older paths not touched this run).
    $newPaths = $script:ManifestEntries
    $allPaths = $newPaths
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $existing = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            if ($existing.paths) {
                $newPathSet = $newPaths | ForEach-Object { $_.path }
                $preserved = $existing.paths | Where-Object { $newPathSet -notcontains $_.path }
                $allPaths = @($preserved) + @($newPaths)
            }
        } catch {}
    }

    $manifest = [pscustomobject]@{
        version      = $packVersion
        installed_at = $now
        mode         = $Mode
        paths        = $allPaths
    }
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}

function Get-GitDir {
    try {
        $gd = git -C $Workspace rev-parse --git-dir 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $gd) { return '' }
        if ([System.IO.Path]::IsPathRooted($gd)) { return $gd }
        return (Join-Path $Workspace $gd)
    } catch { return '' }
}

function Get-ExcludeFilePath {
    $gd = Get-GitDir
    if (-not $gd) { return '' }
    return (Join-Path $gd 'info\exclude')
}

function Is-Tracked($absPath) {
    $rel = $absPath
    if ($absPath.StartsWith($Workspace)) {
        $rel = $absPath.Substring($Workspace.Length).TrimStart('\','/')
    }
    git -C $Workspace ls-files --error-unmatch -- $rel 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Write-ExcludeBlock {
    $excl = Get-ExcludeFilePath
    if (-not $excl) {
        Write-Warning "Not inside a git repo — skipping .git/info/exclude wiring."
        Write-Warning "Pack files are present on disk; commit them only when ready."
        return
    }
    $exclDir = Split-Path -Parent $excl
    if (-not (Test-Path -LiteralPath $exclDir)) {
        New-Item -ItemType Directory -Force -Path $exclDir | Out-Null
    }
    if (-not (Test-Path -LiteralPath $excl)) {
        New-Item -ItemType File -Force -Path $excl | Out-Null
    }

    $rels = New-Object System.Collections.Generic.List[string]
    $skippedTracked = New-Object System.Collections.Generic.List[string]
    foreach ($e in $script:ManifestEntries) {
        if ($e.scope -ne 'workspace') { continue }
        if (@('created','unchanged_owned','overwritten','merged_hooks_key','merged_settings','rendered','sidecar') -notcontains $e.action) { continue }
        $rel = $e.path
        if ($e.path.StartsWith($Workspace)) {
            $rel = $e.path.Substring($Workspace.Length).TrimStart('\','/')
        }
        $rel = $rel -replace '\\','/'
        if (Is-Tracked $e.path) {
            $skippedTracked.Add($rel) | Out-Null
        } else {
            $rels.Add($rel) | Out-Null
        }
    }

    # Always exclude the manifest itself.
    $manifestRel = $manifestPath
    if ($manifestPath.StartsWith($Workspace)) {
        $manifestRel = $manifestPath.Substring($Workspace.Length).TrimStart('\','/')
    }
    $manifestRel = $manifestRel -replace '\\','/'
    if (-not (Is-Tracked $manifestPath)) {
        $rels.Add($manifestRel) | Out-Null
    }

    # Read current exclude, strip any prior managed block, then append fresh block.
    $existing = Get-Content -LiteralPath $excl -ErrorAction SilentlyContinue
    if ($null -eq $existing) { $existing = @() }
    $kept = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($line in $existing) {
        if ($line -eq $ExcludeBegin) { $skip = $true; continue }
        if ($skip -and $line -eq $ExcludeEnd) { $skip = $false; continue }
        if (-not $skip) { $kept.Add($line) | Out-Null }
    }

    $newLines = New-Object System.Collections.Generic.List[string]
    foreach ($l in $kept) { $newLines.Add($l) | Out-Null }
    $newLines.Add($ExcludeBegin) | Out-Null
    $newLines.Add('# Managed by scripts/bootstrap.ps1 — do not edit by hand.') | Out-Null
    $newLines.Add('# Remove with: scripts/bootstrap.ps1 -Graduate') | Out-Null
    foreach ($r in $rels) { $newLines.Add($r) | Out-Null }
    $newLines.Add($ExcludeEnd) | Out-Null

    Set-Content -LiteralPath $excl -Value $newLines -Encoding UTF8

    Write-Host ''
    Write-Host ("Trial mode active. {0} path(s) added to .git/info/exclude." -f $rels.Count)
    if ($skippedTracked.Count -gt 0) {
        Write-Host ''
        Write-Host ("NOTE: {0} path(s) already tracked by git — left visible:" -f $skippedTracked.Count)
        foreach ($t in $skippedTracked) { Write-Host "  $t" }
        Write-Host ''
        Write-Host "If you want trial-mode behavior on those too, run (per path):"
        Write-Host "  git rm --cached <path>"
        Write-Host "Then re-run: scripts\bootstrap.ps1 -Trial"
    }
    Write-Host ''
    Write-Host "To expose these files to your team's git later:"
    Write-Host "  scripts\bootstrap.ps1 -Graduate"
}

function Strip-ExcludeBlock {
    $excl = Get-ExcludeFilePath
    if (-not $excl -or -not (Test-Path -LiteralPath $excl)) {
        Write-Host "No .git/info/exclude found — nothing to do."
        return
    }
    $existing = Get-Content -LiteralPath $excl
    $kept = New-Object System.Collections.Generic.List[string]
    $skip = $false
    $removed = $false
    foreach ($line in $existing) {
        if ($line -eq $ExcludeBegin) { $skip = $true; $removed = $true; continue }
        if ($skip -and $line -eq $ExcludeEnd) { $skip = $false; continue }
        if (-not $skip) { $kept.Add($line) | Out-Null }
    }
    Set-Content -LiteralPath $excl -Value $kept -Encoding UTF8
    if ($removed) {
        Write-Host "Removed Assert.IQ managed block from $excl"
    } else {
        Write-Host "No Assert.IQ managed block found in $excl — nothing to remove."
    }
}

# =============================================================================
# -Graduate short-circuit
# =============================================================================

if ($doGraduate) {
    Write-Host '=== Assert.IQ graduate: trial -> committed ==='
    Strip-ExcludeBlock
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $m.mode = 'committed'
            $m | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
            Write-Host "Updated $manifestPath: mode -> committed"
        } catch {
            Write-Warning "Could not update manifest mode: $_"
        }
    }
    Write-Host ''
    Write-Host 'Pack files are now visible to git. Suggested next steps:'
    Write-Host '  git status                       # confirm pack files are untracked'
    Write-Host '  git add .assert-iq .claude .github CLAUDE.md AGENTS.md'
    Write-Host '  git commit -m "chore: adopt Assert.IQ agent pack"'
    exit 0
}

# =============================================================================
# Mode resolution
# =============================================================================

function Resolve-Mode {
    if ($Mode -eq 'trial' -or $Mode -eq 'committed') { return }
    if ($Mode -eq '' -or $Mode -eq 'ask') {
        $isInteractive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
        if ($isInteractive) {
            Write-Host ''
            Write-Host 'Choose install mode:'
            Write-Host '  [t] Trial    — files added but ignored by .git/info/exclude'
            Write-Host '                 (codebase .gitignore untouched; team will not see them)'
            Write-Host '  [c] Committed — files visible to git (you commit when ready)'
            Write-Host ''
            while ($true) {
                $ans = Read-Host 'Mode [t/c] (default c)'
                if (-not $ans) { $ans = 'c' }
                switch -Regex ($ans) {
                    '^[tT]'      { $script:Mode = 'trial'; return }
                    '^[cC]'      { $script:Mode = 'committed'; return }
                    'trial'      { $script:Mode = 'trial'; return }
                    'committed'  { $script:Mode = 'committed'; return }
                }
            }
        } else {
            $script:Mode = 'committed'
        }
        return
    }
    throw "Invalid -Mode value '$Mode' (expected: trial, committed, ask)"
}

Resolve-Mode

# =============================================================================
# Apply preset defaults
# =============================================================================

switch ($Preset) {
    'solo' {
        if (-not $AssertIq)        { $AssertIq        = 'workspace' }
        if (-not $Instructions)    { $Instructions    = 'user' }
        if (-not $Claude)          { $Claude          = 'user' }
        if (-not $Copilot)         { $Copilot         = 'workspace' }
        if (-not $Agents)          { $Agents          = 'workspace' }
        if (-not $VSCode)          { $VSCode          = 'workspace' }
        if (-not $Hooks)           { $Hooks           = 'workspace' }
        if (-not $ClaudeSettings)  { $ClaudeSettings  = 'workspace' }
    }
    default {
        # pod (and unset)
        if (-not $AssertIq)        { $AssertIq        = 'workspace' }
        if (-not $Instructions)    { $Instructions    = 'workspace' }
        if (-not $Claude)          { $Claude          = 'workspace' }
        if (-not $Copilot)         { $Copilot         = 'workspace' }
        if (-not $Agents)          { $Agents          = 'workspace' }
        if (-not $VSCode)          { $VSCode          = 'workspace' }
        if (-not $Hooks)           { $Hooks           = 'workspace' }
        if (-not $ClaudeSettings)  { $ClaudeSettings  = 'workspace' }
    }
}

# =============================================================================
# Result tracking + copy primitives
# =============================================================================

$results = New-Object System.Collections.Generic.List[object]

function Record($label, $result, $dst) {
    $results.Add([pscustomobject]@{
        Surface     = $label
        Result      = $result
        Destination = $dst
    }) | Out-Null
}

function Resolve-Conflict {
    param([string]$Src, [string]$Dst, [string]$Label)
    switch ($script:ConflictBulkChoice) {
        'K' { return 'keep' }
        'O' { return 'overwrite' }
        'S' { return 'sidecar' }
    }
    $isInteractive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if (-not $isInteractive) { return 'keep' }
    Write-Host ''
    Write-Host "Conflict: $Label"
    Write-Host "  existing: $Dst"
    Write-Host "  pack:     $Src"
    while ($true) {
        $ans = Read-Host '  [k]eep / [o]verwrite / [s]idecar (.assert-iq-new) / [d]iff / [K/O/S]all / [a]bort'
        switch ($ans) {
            'k' { return 'keep' }
            'o' { return 'overwrite' }
            's' { return 'sidecar' }
            'K' { $script:ConflictBulkChoice = 'K'; return 'keep' }
            'O' { $script:ConflictBulkChoice = 'O'; return 'overwrite' }
            'S' { $script:ConflictBulkChoice = 'S'; return 'sidecar' }
            'd' {
                try {
                    $left  = Get-Content -LiteralPath $Dst -ErrorAction Stop
                    $right = Get-Content -LiteralPath $Src -ErrorAction Stop
                    Compare-Object $left $right | Format-Table -AutoSize | Out-Host
                } catch {
                    Write-Host '  (diff not available)'
                }
            }
            'a' { Write-Host 'Aborted by user.'; exit 1 }
            default { Write-Host '  (please type one of k, o, s, d, K, O, S, a)' }
        }
    }
}

function Copy-FileScoped {
    param([string]$Label, [string]$Src, [string]$Dst, [string]$Scope)

    if (-not (Test-Path -LiteralPath $Src)) {
        Record $Label 'missing-source' $Src
        return
    }
    if (-not (Test-Path -LiteralPath $Dst)) {
        $parent = Split-Path -Parent $Dst
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        Copy-Item -LiteralPath $Src -Destination $Dst -Force:$false
        Manifest-Add 'created' $Dst $Scope
        Record $Label 'copied' $Dst
        return
    }

    $shSrc = Get-Sha256 $Src
    $shDst = Get-Sha256 $Dst
    if ($shSrc -and ($shSrc -eq $shDst)) {
        Manifest-Add 'unchanged_owned' $Dst $Scope
        Record $Label 'unchanged (pack-owned)' $Dst
        return
    }

    $choice = Resolve-Conflict -Src $Src -Dst $Dst -Label $Label
    switch ($choice) {
        'keep' {
            Record $Label 'skipped (user kept existing)' $Dst
        }
        'overwrite' {
            Copy-Item -LiteralPath $Src -Destination $Dst -Force
            Manifest-Add 'overwritten' $Dst $Scope
            Record $Label 'overwritten' $Dst
        }
        'sidecar' {
            $side = "$Dst.assert-iq-new"
            Copy-Item -LiteralPath $Src -Destination $side -Force
            Manifest-Add 'sidecar' $side $Scope
            Record $Label 'sidecar -> .assert-iq-new' $side
        }
    }
}

function Copy-TreeScoped {
    param([string]$Label, [string]$SrcDir, [string]$DstDir, [string]$Scope)

    if (-not (Test-Path -LiteralPath $SrcDir -PathType Container)) {
        Record $Label 'missing-source' $SrcDir
        return
    }
    Get-ChildItem -LiteralPath $SrcDir -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($SrcDir.Length).TrimStart('\','/')
        $relUx = $rel -replace '\\','/'
        Copy-FileScoped -Label "$Label/$relUx" -Src $_.FullName -Dst (Join-Path $DstDir $rel) -Scope $Scope
    }
}

function Merge-Hashtables {
    param($Pack, $User)
    # Deep merge two PSCustomObjects/hashtables. User wins on scalar conflicts.
    # Object keys present on both sides recurse. Arrays: user wins (whole-array).
    if ($null -eq $User) { return $Pack }
    if ($null -eq $Pack) { return $User }
    # Coerce both to ordered hashtables for predictable merge.
    $userIsObj = ($User -is [pscustomobject]) -or ($User -is [hashtable])
    $packIsObj = ($Pack -is [pscustomobject]) -or ($Pack -is [hashtable])
    if (-not ($userIsObj -and $packIsObj)) {
        # Scalar or array conflict — user wins.
        return $User
    }
    $result = [ordered]@{}
    # Start with all pack keys.
    foreach ($prop in $Pack.PSObject.Properties) {
        $result[$prop.Name] = $prop.Value
    }
    # Layer user keys on top (recursing on objects).
    foreach ($prop in $User.PSObject.Properties) {
        if ($result.Contains($prop.Name)) {
            $result[$prop.Name] = Merge-Hashtables -Pack $result[$prop.Name] -User $prop.Value
        } else {
            $result[$prop.Name] = $prop.Value
        }
    }
    return [pscustomobject]$result
}

function Merge-JsonFile {
    param([string]$Label, [string]$Src, [string]$Dst, [string]$Scope)

    if (-not (Test-Path -LiteralPath $Src)) {
        Record $Label 'missing-source' $Src
        return
    }
    if (-not (Test-Path -LiteralPath $Dst)) {
        Copy-FileScoped -Label $Label -Src $Src -Dst $Dst -Scope $Scope
        return
    }
    $shSrc = Get-Sha256 $Src
    $shDst = Get-Sha256 $Dst
    if ($shSrc -and ($shSrc -eq $shDst)) {
        Manifest-Add 'unchanged_owned' $Dst $Scope
        Record $Label 'unchanged (pack-owned)' $Dst
        return
    }
    try {
        $packJson = Get-Content -LiteralPath $Src -Raw | ConvertFrom-Json
        $userJson = Get-Content -LiteralPath $Dst -Raw | ConvertFrom-Json
        $merged   = Merge-Hashtables -Pack $packJson -User $userJson
        $merged | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $Dst -Encoding UTF8
        Manifest-Add 'merged_settings' $Dst $Scope
        Record $Label 'merged (additive, yours wins)' $Dst
    } catch {
        # Parse or write failed — sidecar.
        $side = "$Dst.assert-iq-new"
        Copy-Item -LiteralPath $Src -Destination $side -Force
        Manifest-Add 'sidecar' $side $Scope
        Record $Label 'sidecar (merge failed) -> .assert-iq-new' $side
    }
}

function Render-HooksJson {
    param([string]$PackRoot)
    $template = Join-Path $Source 'hooks\hooks.template.json'
    if (-not (Test-Path -LiteralPath $template)) { return '' }
    $tmp = [System.IO.Path]::GetTempFileName()
    # __PACK_ROOT__ in the template is used both as a POSIX path (bash side)
    # and a Windows path (PowerShell side, single-quoted). Substitute both.
    $content = Get-Content -LiteralPath $template -Raw
    # __PACK_ROOT__ appears inside JSON strings; escape JSON-sensitive chars
    # so Windows paths like C:\repo remain valid JSON.
    $packRootJson = $PackRoot.Replace('\', '\\').Replace('"', '\"')
    $content = $content.Replace('__PACK_ROOT__', $packRootJson)
    Set-Content -LiteralPath $tmp -Value $content -Encoding UTF8 -NoNewline
    return $tmp
}

# =============================================================================
# Per-surface handlers
# =============================================================================

function Process-AssertIq {
    switch ($AssertIq) {
        'workspace' { Copy-TreeScoped '.assert-iq' (Join-Path $Source '.assert-iq') (Join-Path $Workspace '.assert-iq') 'workspace' }
        'user'      { Copy-TreeScoped '.assert-iq' (Join-Path $Source '.assert-iq') $userAssertIq 'user' }
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
            Get-ChildItem -LiteralPath $src -Filter '*.instructions.md' | ForEach-Object {
                Copy-FileScoped "instructions/$($_.Name)" $_.FullName (Join-Path $dest $_.Name) 'workspace'
            }
        }
        'user' {
            Get-ChildItem -LiteralPath $src -Filter '*.instructions.md' | ForEach-Object {
                Copy-FileScoped "instructions/$($_.Name)" $_.FullName (Join-Path $userPrompts $_.Name) 'user'
            }
        }
        'skip' { Record 'instructions' 'skipped (user choice)' '-' }
        default { throw "Invalid -Instructions: '$Instructions'" }
    }
}

function Process-Claude {
    $src = Join-Path $Source 'CLAUDE.md'
    switch ($Claude) {
        'workspace' { Copy-FileScoped 'CLAUDE.md' $src (Join-Path $Workspace 'CLAUDE.md') 'workspace' }
        'user'      { Copy-FileScoped 'CLAUDE.md' $src $userClaudeMd 'user' }
        'skip'      { Record 'CLAUDE.md' 'skipped (user choice)' '-' }
        default     { throw "Invalid -Claude: '$Claude'" }
    }
}

function Process-Copilot {
    $src = Join-Path $Source '.github\copilot-instructions.md'
    switch ($Copilot) {
        'workspace' {
            Copy-FileScoped 'copilot-instructions.md' $src (Join-Path $Workspace '.github\copilot-instructions.md') 'workspace'
        }
        'user' {
            Write-Warning 'copilot-instructions.md has no native user-global slot. Skipping.'
            Record 'copilot-instructions.md' 'skipped (no user-global slot)' '-'
        }
        'skip' { Record 'copilot-instructions.md' 'skipped (user choice)' '-' }
        default { throw "Invalid -Copilot: '$Copilot'" }
    }
}

function Process-Agents {
    $src = Join-Path $Source 'AGENTS.md'
    switch ($Agents) {
        'workspace' { Copy-FileScoped 'AGENTS.md' $src (Join-Path $Workspace 'AGENTS.md') 'workspace' }
        'user' {
            Write-Warning 'AGENTS.md has no native user-global slot. Skipping.'
            Record 'AGENTS.md' 'skipped (no user-global slot)' '-'
        }
        'skip' { Record 'AGENTS.md' 'skipped (user choice)' '-' }
        default { throw "Invalid -Agents: '$Agents'" }
    }
}

function Process-VSCode {
    # Wires VS Code Copilot to read instructions/prompts/hooks from the workspace.
    switch ($VSCode) {
        'workspace' {
            Merge-JsonFile '.vscode/settings.json' `
                (Join-Path $Source '.vscode\settings.json') `
                (Join-Path $Workspace '.vscode\settings.json') `
                'workspace'
            $mcpSrc = Join-Path $Source '.vscode\mcp.json'
            $mcpDst = Join-Path $Workspace '.vscode\mcp.json'
            if (Test-Path -LiteralPath $mcpDst) {
                Merge-JsonFile '.vscode/mcp.json' $mcpSrc $mcpDst 'workspace'
            } else {
                Copy-FileScoped '.vscode/mcp.json' $mcpSrc $mcpDst 'workspace'
            }
        }
        'user' {
            Write-Warning '.vscode/ has no native user-global slot. Skipping.'
            Record '.vscode/' 'skipped (no user-global slot)' '-'
        }
        'skip' { Record '.vscode/' 'skipped (user choice)' '-' }
        default { throw "Invalid -VSCode: '$VSCode'" }
    }
}

function Process-Hooks {
    # Workspace-root hooks/ is what .vscode/settings.json's chat.hookFilesLocations
    # points at ("./hooks/hooks.json"). Renders hooks.json with __PACK_ROOT__ =
    # $Workspace so scripts resolve to the workspace copies.
    switch ($Hooks) {
        'workspace' {
            $hooksSrcDir = Join-Path $Source 'hooks'
            if (-not (Test-Path -LiteralPath $hooksSrcDir -PathType Container)) {
                Record 'hooks/' 'missing-source' $hooksSrcDir
                return
            }
            $scriptsSrc = Join-Path $hooksSrcDir 'scripts'
            if (Test-Path -LiteralPath $scriptsSrc) {
                Copy-TreeScoped 'hooks/scripts' $scriptsSrc (Join-Path $Workspace 'hooks\scripts') 'workspace'
            }
            $libSrc = Join-Path $hooksSrcDir 'lib'
            if (Test-Path -LiteralPath $libSrc) {
                Copy-TreeScoped 'hooks/lib' $libSrc (Join-Path $Workspace 'hooks\lib') 'workspace'
            }
            $cfgSrc = Join-Path $hooksSrcDir 'config'
            if (Test-Path -LiteralPath $cfgSrc) {
                Copy-TreeScoped 'hooks/config' $cfgSrc (Join-Path $Workspace 'hooks\config') 'workspace'
            }
            # Runtime dirs: state/ + logs/ ship seed JSON and append-only logs
            # the scripts read/write. sessions/ is created empty; per-session
            # subdirs are written at SessionStart.
            $stateSrc = Join-Path $hooksSrcDir 'state'
            if (Test-Path -LiteralPath $stateSrc) {
                Copy-TreeScoped 'hooks/state' $stateSrc (Join-Path $Workspace 'hooks\state') 'workspace'
            }
            $logsSrc = Join-Path $hooksSrcDir 'logs'
            if (Test-Path -LiteralPath $logsSrc) {
                Copy-TreeScoped 'hooks/logs' $logsSrc (Join-Path $Workspace 'hooks\logs') 'workspace'
            }
            $sessionsDst = Join-Path $Workspace 'hooks\sessions'
            New-Item -ItemType Directory -Path $sessionsDst -Force | Out-Null
            Manifest-Add 'created' $sessionsDst 'workspace'
            Record 'hooks/sessions/' 'created' $sessionsDst
            $rendered = Render-HooksJson -PackRoot $Workspace
            if (-not $rendered) {
                Record 'hooks/hooks.json' 'missing-template' (Join-Path $hooksSrcDir 'hooks.template.json')
            } else {
                Copy-FileScoped 'hooks/hooks.json' $rendered (Join-Path $Workspace 'hooks\hooks.json') 'workspace'
                Remove-Item -LiteralPath $rendered -Force -ErrorAction SilentlyContinue
            }
        }
        'skip' { Record 'hooks/' 'skipped (user choice)' '-' }
        default { throw "Invalid -Hooks: '$Hooks'" }
    }
}

function Process-ClaudeSettings {
    # Merge only the .hooks key into .claude/settings.json; preserve everything
    # else. Copilot side disables this file via chat.hookFilesLocations to
    # avoid double-fire.
    switch ($ClaudeSettings) {
        'workspace' {
            $rendered = Render-HooksJson -PackRoot $Workspace
            if (-not $rendered) {
                Record '.claude/settings.json' 'missing-template' (Join-Path $Source 'hooks\hooks.template.json')
                return
            }
            $dst = Join-Path $Workspace '.claude\settings.json'
            $parent = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Force -Path $parent | Out-Null
            }
            if (-not (Test-Path -LiteralPath $dst)) {
                Copy-Item -LiteralPath $rendered -Destination $dst -Force
                Manifest-Add 'created' $dst 'workspace'
                Record '.claude/settings.json' 'copied' $dst
            } else {
                try {
                    $existing = Get-Content -LiteralPath $dst -Raw | ConvertFrom-Json
                    $new      = Get-Content -LiteralPath $rendered -Raw | ConvertFrom-Json
                    # Replace only the .hooks key.
                    $out = [ordered]@{}
                    foreach ($prop in $existing.PSObject.Properties) {
                        if ($prop.Name -ne 'hooks') { $out[$prop.Name] = $prop.Value }
                    }
                    $out['hooks'] = $new.hooks
                    [pscustomobject]$out | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $dst -Encoding UTF8
                    Manifest-Add 'merged_hooks_key' $dst 'workspace'
                    Record '.claude/settings.json' 'merged hooks key' $dst
                } catch {
                    $side = "$dst.assert-iq-new"
                    Copy-Item -LiteralPath $rendered -Destination $side -Force
                    Manifest-Add 'sidecar' $side 'workspace'
                    Record '.claude/settings.json' 'sidecar (merge failed)' $side
                }
            }
            Remove-Item -LiteralPath $rendered -Force -ErrorAction SilentlyContinue
        }
        'skip' { Record '.claude/settings.json' 'skipped (user choice)' '-' }
        default { throw "Invalid -ClaudeSettings: '$ClaudeSettings'" }
    }
}

Process-AssertIq
Process-Instructions
Process-Claude
Process-Copilot
Process-Agents
Process-VSCode
Process-Hooks
Process-ClaudeSettings

# =============================================================================
# Finalize: manifest + git-exclude wiring (trial mode only)
# =============================================================================

Manifest-Write

if ($Mode -eq 'trial') {
    Write-ExcludeBlock
}

# =============================================================================
# Summary
# =============================================================================

Write-Host ''
Write-Host '=== Assert.IQ bootstrap summary ==='
Write-Host "Source:    $Source"
Write-Host "Workspace: $Workspace"
$presetLabel = if ($Preset) { $Preset } else { '(none)' }
Write-Host "Preset:    $presetLabel"
Write-Host "Mode:      $Mode"
Write-Host "Manifest:  $manifestPath"
Write-Host ''
$results | Format-Table -AutoSize Surface, Result, Destination

$sidecarCount = ($results | Where-Object { $_.Result -eq 'sidecar -> .assert-iq-new' }).Count
$keptCount    = ($results | Where-Object { $_.Result -eq 'skipped (user kept existing)' }).Count
if ($sidecarCount -gt 0) {
    Write-Host "NOTE: $sidecarCount file(s) written as .assert-iq-new sidecars."
    Write-Host "      Diff them against your existing files when ready, then delete the sidecar."
}
if ($keptCount -gt 0) {
    Write-Host "NOTE: $keptCount existing file(s) kept untouched (you chose 'keep')."
}

Write-Host ''
Write-Host 'Reload your editor window so the new instructions and config are picked up:'
Write-Host '  - VS Code:     Ctrl+Shift+P -> "Developer: Reload Window"'
Write-Host '  - Claude Code: restart the session'
