# Assert.IQ Agent Pack — workspace bootstrap (Windows / PowerShell)
#
# Copies workspace-loaded surfaces (instructions, .assert-iq/, CLAUDE.md,
# copilot-instructions.md, AGENTS.md) from the cloned pack into the
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
# Skills scope (where the 24 QI skills land):
#   -SkillsScope workspace   (default) workspace .github/skills + .claude/skills symlink
#   -SkillsScope user        only ~/.agents/skills + ~/.claude/skills (every workspace gets them)
#   -SkillsScope both        workspace AND user-global
#
# Presets:
#   -Preset pod        (default) team install — everything in workspace
#   -Preset solo       solo dev — instructions + CLAUDE.md user-global
#   -Preset portable   skills user-global, minimal workspace footprint
#                      (chat agents + manifest still live in the repo)
#
# Other switches:
#   -Graduate / -Untrial   Reverse trial mode: remove pack entries from
#                          .git/info/exclude. Files stay on disk.
#
# See .github\skills\assert-iq-bootstrap\SKILL.md for full docs.

[CmdletBinding()]
param(
    [ValidateSet('solo', 'pod', 'portable', '')]
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

    [ValidateSet('workspace', 'user', 'skip', '')]
    [Alias('Hooks')]
    [string]$Dreaming = '',

    [ValidateSet('workspace', 'skip', '')]
    [string]$ClaudeSettings = '',

    [ValidateSet('workspace', 'user', 'both', '')]
    [string]$SkillsScope = '',

    [string]$Workspace = (Get-Location).Path,

    [string]$Source = '',

    [ValidateSet('trial', 'committed', 'ask', '')]
    [string]$Mode = '',

    [switch]$Trial,
    [switch]$Committed,
    [switch]$Graduate,
    [switch]$Untrial,
    [switch]$Upgrade,
    [switch]$Uninstall,
    [switch]$User,
    [Alias('y')]
    [switch]$Yes,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Resolve mode shorthand switches.
if ($Trial)     { $Mode = 'trial' }
if ($Committed) { $Mode = 'committed' }
$doGraduate  = $Graduate -or $Untrial
$doUninstall = [bool]$Uninstall
$doUpgrade   = [bool]$Upgrade

# Upgrade state (populated by Invoke-UpgradePrepare).
$script:OldManifest      = $null
$script:InstalledVersion = ''

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
    $userHome    = $env:USERPROFILE
    $userPrompts = Join-Path $env:APPDATA 'Code\User\prompts'
} elseif ($IsMacOS) {
    $userHome    = $HOME
    $userPrompts = Join-Path $HOME 'Library/Application Support/Code/User/prompts'
} else {
    $userHome    = $HOME
    $userPrompts = Join-Path $HOME '.config/Code/User/prompts'
}

$userAssertIq     = Join-Path $userHome '.assert-iq'
$userClaudeDir    = Join-Path $userHome '.claude'
$userAgentsDir    = Join-Path $userHome '.agents'
$userClaudeMd     = Join-Path $userClaudeDir 'CLAUDE.md'
$userVscodeSkills = Join-Path $userAgentsDir 'skills'
$userClaudeSkills = Join-Path $userClaudeDir 'skills'

$manifestPath = Join-Path $Workspace '.assert-iq\.install-manifest.json'

# =============================================================================
# Manifest, sha256, git-exclude helpers
# =============================================================================

$script:ManifestEntries = New-Object System.Collections.Generic.List[object]
$script:ConflictBulkChoice = if ($env:CONFLICT_BULK_CHOICE -in @('K','O','M','S')) { $env:CONFLICT_BULK_CHOICE } else { '' }

function Get-Sha256($path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
}

# -----------------------------------------------------------------------------
# Install-time base cache: pristine pack content snapshotted under
# .assert-iq/.base/ (keyed by a hash of the absolute dst path). On a later
# -Upgrade this is the preferred three-way merge baseline, so upgrades preserve
# user edits even when the source repo has no matching version tag (or no git
# history). The three markdown-allowlist files keep their marker-block merge
# and are intentionally excluded.
# -----------------------------------------------------------------------------
$script:BaseCacheDir = Join-Path $Workspace '.assert-iq\.base'

function Test-BaseCacheable([string]$dst) {
    return ((Split-Path -Leaf $dst) -notin @('copilot-instructions.md','CLAUDE.md','AGENTS.md'))
}

function Get-BaseCacheFile([string]$dst) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($dst)
    $hash  = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    $key   = ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
    return (Join-Path $script:BaseCacheDir $key)
}

function Save-Base([string]$Content, [string]$Dst) {
    if (-not (Test-Path -LiteralPath $Content -PathType Leaf)) { return }
    if (-not (Test-BaseCacheable $Dst)) { return }
    if (-not (Test-Path -LiteralPath $script:BaseCacheDir)) {
        New-Item -ItemType Directory -Force -Path $script:BaseCacheDir | Out-Null
    }
    Copy-Item -LiteralPath $Content -Destination (Get-BaseCacheFile $Dst) -Force -ErrorAction SilentlyContinue
}

function Get-Base([string]$Dst) {
    if (-not (Test-BaseCacheable $Dst)) { return '' }
    $bf = Get-BaseCacheFile $Dst
    if (Test-Path -LiteralPath $bf -PathType Leaf) { return $bf }
    return ''
}

# Manifest action sets — kept here so adding a new action only touches one
# place. RemovableActions are deleted on uninstall; ExcludableActions are
# emitted into .git/info/exclude in trial mode.
$script:RemovableActions  = @('created','unchanged_owned','overwritten','rendered','sidecar')
$script:ExcludableActions = @('created','unchanged_owned','overwritten','merged_hooks_key','merged_settings','merged_markdown','rendered','sidecar')
$script:MergedActions     = @('merged_settings','merged_hooks_key','merged_markdown')
# Vocabulary of actions allowed in the manifest. Validation in
# Add-ManifestEntry turns silent typos into immediate errors.
$script:KnownActions      = @('created','unchanged_owned','overwritten','rendered','sidecar','merged_settings','merged_hooks_key','merged_markdown','pre_install_backup')

function Add-ManifestEntry($action, $path, $scope) {
    if ($action -notin $script:KnownActions) {
        throw "Add-ManifestEntry: unknown action '$action' (typo? add it to `$script:KnownActions)"
    }
    $script:ManifestEntries.Add([pscustomobject]@{
        action = $action
        path   = $path
        scope  = $scope
    }) | Out-Null
}

function Backup-IfUserOwned {
    # Snapshot a pre-existing user file before we modify or overwrite it,
    # so -Uninstall can restore the original. No-op if the destination does
    # not exist yet, or if a backup already exists (idempotent across re-runs).
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Scope
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $backup = "$Path.assert-iq.pre-install"
    if (Test-Path -LiteralPath $backup) { return }
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    Add-ManifestEntry 'pre_install_backup' $backup $Scope
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
    catch { return '' }
}

function Save-MergeResultSha {
    # Records the post-install SHA of a file produced by a merge action so
    # uninstall can tell whether the user edited the file after install.
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $sha = Get-FileSha256 -Path $Path
    if (-not $sha) { return }
    $sidecar = Join-Path $Workspace '.assert-iq/.merge-result-shas'
    $sidecarDir = Split-Path -Parent $sidecar
    if (-not (Test-Path -LiteralPath $sidecarDir)) {
        New-Item -ItemType Directory -Force -Path $sidecarDir | Out-Null
    }
    $existing = @()
    if (Test-Path -LiteralPath $sidecar) {
        $existing = Get-Content -LiteralPath $sidecar -ErrorAction SilentlyContinue |
            Where-Object { $_ -and -not $_.StartsWith("$Path`t") }
    }
    $existing += "$Path`t$sha"
    Set-Content -LiteralPath $sidecar -Value $existing -Encoding UTF8
}

function Get-MergeResultSha {
    param([Parameter(Mandatory)][string] $Path)
    $sidecar = Join-Path $Workspace '.assert-iq/.merge-result-shas'
    if (-not (Test-Path -LiteralPath $sidecar)) { return '' }
    foreach ($line in Get-Content -LiteralPath $sidecar -ErrorAction SilentlyContinue) {
        $parts = $line -split "`t", 2
        if ($parts.Length -eq 2 -and $parts[0] -eq $Path) { return $parts[1] }
    }
    return ''
}

# Stage-then-commit a merged JSON string. If the staged content is
# byte-identical to the existing dst, records unchanged_owned; otherwise
# backs up (if user-owned) and atomically writes dst, recording
# $ChangedAction. Centralizes the no-op short-circuit used by JSON merges.
function Write-OrSkipIfUnchanged {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $MergedContent,
        [Parameter(Mandatory)] [string] $Dst,
        [Parameter(Mandatory)] [string] $Scope,
        [Parameter(Mandatory)] [string] $ChangedAction,
        [Parameter(Mandatory)] [string] $ChangedMessage
    )
    $existingContent = Get-Content -LiteralPath $Dst -Raw -ErrorAction SilentlyContinue
    if ($null -ne $existingContent -and $existingContent -eq $MergedContent) {
        Add-ManifestEntry 'unchanged_owned' $Dst $Scope
        Record $Label 'unchanged (merge no-op)' $Dst
        return
    }
    Backup-IfUserOwned -Path $Dst -Scope $Scope
    Write-AtomicFile -Path $Dst -Content $MergedContent
    Add-ManifestEntry $ChangedAction $Dst $Scope
    Save-MergeResultSha -Path $Dst
    Record $Label $ChangedMessage $Dst
}

# Atomically write $Content to $Path: stage to a sibling temp file, validate
# non-empty, then Move-Item -Force. Prevents truncation of user files on
# interrupt or partial-write.
function Write-AtomicFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Content,
        [string] $Encoding = 'UTF8'
    )
    if ([string]::IsNullOrWhiteSpace($Content)) {
        throw "Write-AtomicFile: refusing to write empty content to $Path"
    }
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $tmp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        Set-Content -LiteralPath $tmp -Value $Content -Encoding $Encoding
        # Use FileInfo for the size check: Get-Item skips hidden/dotfiles
        # without -Force, and the staged tmp basename can begin with '.'.
        $info = New-Object System.IO.FileInfo($tmp)
        if (-not $info.Exists -or $info.Length -eq 0) {
            throw "Write-AtomicFile: staged file is empty: $tmp"
        }
        Move-Item -LiteralPath $tmp -Destination $Path -Force
        $tmp = $null
    } finally {
        if ($tmp -and (Test-Path -LiteralPath $tmp)) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-Manifest {
    $outDir = Split-Path -Parent $manifestPath
    if (-not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }

    $packVersion = 'unknown'
    $versionFile = Join-Path $Source 'VERSION'
    if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
        try {
            $pv = (Get-Content -LiteralPath $versionFile -TotalCount 1).Trim()
            if ($pv) { $packVersion = $pv }
        } catch {
            Write-Verbose "bootstrap: could not read VERSION: $_"
        }
    }
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Merge with existing manifest if present (preserve older paths not touched this run).
    # Each fresh entry records the post-install sha so an upgrade can detect
    # files the user never edited and refresh them outright.
    $newPaths = $script:ManifestEntries | ForEach-Object {
        [pscustomobject]@{
            action = $_.action
            path   = $_.path
            scope  = $_.scope
            sha    = (Get-Sha256 $_.path)
        }
    }
    $allPaths = @($newPaths)
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $existing = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            if ($existing.paths) {
                $newPathSet = $newPaths | ForEach-Object { $_.path }
                $preserved = $existing.paths | Where-Object { $newPathSet -notcontains $_.path }
                $allPaths = @($preserved) + @($newPaths)
            }
        } catch {
            Write-Verbose "bootstrap: could not merge existing manifest: $_"
        }
    }

    $manifest = [pscustomobject]@{
        version      = $packVersion
        installed_at = $now
        mode         = $Mode
        paths        = $allPaths
    }
    Write-AtomicFile -Path $manifestPath -Content ($manifest | ConvertTo-Json -Depth 10)
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

function ConvertTo-WorkspaceRelative([string]$absPath) {
    # Windows paths are case-insensitive; .NET String.StartsWith defaults to
    # ordinal/case-sensitive. Use OrdinalIgnoreCase so a manifest entry written
    # via different casing still relativizes correctly.
    if ($absPath.StartsWith($Workspace, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $absPath.Substring($Workspace.Length).TrimStart('\','/')
    }
    return $absPath
}

function Test-Tracked($absPath) {
    $rel = ConvertTo-WorkspaceRelative $absPath
    git -C $Workspace ls-files --error-unmatch -- $rel 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Strip a managed begin..end block from an array of lines. Returns the
# kept lines; sets $script:_StripRemoved = $true if any block was found.
function Remove-ManagedBlockLines([string[]]$Lines) {
    $script:_StripRemoved = $false
    $kept = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($line in $Lines) {
        if ($line -eq $ExcludeBegin) { $skip = $true; $script:_StripRemoved = $true; continue }
        if ($skip -and $line -eq $ExcludeEnd) { $skip = $false; continue }
        if (-not $skip) { $kept.Add($line) | Out-Null }
    }
    return ,$kept.ToArray()
}

function Write-ExcludeBlock {
    # Always-on writer for .git/info/exclude managed block. Two layers:
    #   1) backup-globs (`*.assert-iq.pre-install`, `*.assert-iq.pre-tailor`,
    #      `*.assert-iq.uninstall-saved`) written in every mode — tool
    #      artifacts that must never be committed. `pre-tailor` snapshots come
    #      from the /assert-iq-tailor skill, excluded here so they never leak.
    #   2) per-path entries for workspace-scoped pack files — only when
    #      $Mode -eq 'trial' so committed-mode adoption stays visible to git.
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
    if ($Mode -eq 'trial') {
        foreach ($e in $script:ManifestEntries) {
            if ($e.scope -ne 'workspace') { continue }
            if ($script:ExcludableActions -notcontains $e.action) { continue }
            $rel = (ConvertTo-WorkspaceRelative $e.path) -replace '\\','/'
            if (Test-Tracked $e.path) {
                $skippedTracked.Add($rel) | Out-Null
            } else {
                $rels.Add($rel) | Out-Null
            }
        }
        # Always exclude the manifest itself.
        $manifestRel = (ConvertTo-WorkspaceRelative $manifestPath) -replace '\\','/'
        if (-not (Test-Tracked $manifestPath)) {
            $rels.Add($manifestRel) | Out-Null
        }
    }

    # Read current exclude, strip any prior managed block, then append fresh block.
    $existing = Get-Content -LiteralPath $excl -ErrorAction SilentlyContinue
    if ($null -eq $existing) { $existing = @() }
    $kept = Remove-ManagedBlockLines $existing

    $newLines = New-Object System.Collections.Generic.List[string]
    foreach ($l in $kept) { $newLines.Add($l) | Out-Null }
    $newLines.Add($ExcludeBegin) | Out-Null
    $newLines.Add('# Managed by scripts/bootstrap.ps1 — do not edit by hand.') | Out-Null
    $newLines.Add('# Remove with: scripts/bootstrap.ps1 -Uninstall (or -Graduate to keep files but expose to git)') | Out-Null
    # Layer 1: always-on backup-glob exclusions.
    $newLines.Add('# Tool artifacts — never commit:') | Out-Null
    $newLines.Add('*.assert-iq.pre-install') | Out-Null
    $newLines.Add('*.assert-iq.pre-tailor') | Out-Null
    $newLines.Add('*.assert-iq.uninstall-saved') | Out-Null
    $newLines.Add('.assert-iq/.skip-worktree-paths') | Out-Null
    $newLines.Add('.assert-iq/.merge-result-shas') | Out-Null
    $newLines.Add('.assert-iq/.base/') | Out-Null
    # Dreaming per-machine artifacts — never commit in any mode:
    $newLines.Add('.assert-iq/dreaming/session-events.json') | Out-Null
    $newLines.Add('.assert-iq/memory/.dream/state.lock') | Out-Null
    $newLines.Add('.assert-iq/memory/.dream/dream.lock') | Out-Null
    $newLines.Add('transcripts/') | Out-Null
    # Layer 2: per-path entries (trial only).
    if ($Mode -eq 'trial' -and $rels.Count -gt 0) {
        $newLines.Add('# Trial-mode pack paths:') | Out-Null
        foreach ($r in $rels) { $newLines.Add($r) | Out-Null }
    }
    # Trial-mode: keep the entire Dreaming memory store local-only — dreams
    # update it autonomously without ever appearing in git. Committed mode
    # leaves it visible on purpose (every dream cycle is a reviewable diff).
    if ($Mode -eq 'trial') {
        $newLines.Add('# Trial-mode Dreaming memory (local-only, hidden from git):') | Out-Null
        $newLines.Add('.assert-iq/memory/') | Out-Null
    }
    $newLines.Add($ExcludeEnd) | Out-Null

    Set-Content -LiteralPath $excl -Value $newLines -Encoding UTF8

    Write-Host ''
    if ($Mode -eq 'trial') {
        Write-Host ("Trial mode active. {0} path(s) added to .git/info/exclude (plus backup-glob exclusions)." -f $rels.Count)
        if ($skippedTracked.Count -gt 0) {
            Write-Host ''
            Write-Host ("NOTE: {0} path(s) already tracked by git — using --skip-worktree to hide local changes:" -f $skippedTracked.Count)
            foreach ($t in $skippedTracked) { Write-Host "  $t" }
        }
        Write-Host ''
        Write-Host "To expose these files to your team's git later:"
        Write-Host "  scripts\bootstrap.ps1 -Graduate"
    } else {
        Write-Host "Wrote backup-glob exclusions to .git/info/exclude."
    }
}

function Invoke-SkipWorktree {
    # Trial-mode helper: for each workspace-scoped manifest path with an
    # action in ExcludableActions, if the file is tracked by git AND not
    # already --skip-worktree (set by the user), mark it --skip-worktree
    # and remember the rel-path in a sidecar so uninstall only clears
    # flags we actually set. Pre-existing user flags are left untouched.
    $gd = Get-GitDir
    if (-not $gd) { return }
    $alreadySkipped = @{}
    $rawFlagged = git -C $Workspace ls-files -v 2>$null
    if ($rawFlagged) {
        foreach ($line in $rawFlagged) {
            if ($line -match '^S (.+)$') { $alreadySkipped[$matches[1]] = $true }
        }
    }
    $sidecar = Join-Path $Workspace '.assert-iq/.skip-worktree-paths'
    $sidecarDir = Split-Path -Parent $sidecar
    if (-not (Test-Path -LiteralPath $sidecarDir)) {
        New-Item -ItemType Directory -Force -Path $sidecarDir | Out-Null
    }
    Set-Content -LiteralPath $sidecar -Value @() -Encoding UTF8
    $marked = 0
    $preexisting = 0
    $marks = New-Object System.Collections.Generic.List[string]
    foreach ($e in $script:ManifestEntries) {
        if ($e.scope -ne 'workspace') { continue }
        if ($script:ExcludableActions -notcontains $e.action) { continue }
        if (-not (Test-Tracked $e.path)) { continue }
        $rel = (ConvertTo-WorkspaceRelative $e.path) -replace '\\','/'
        if ($alreadySkipped.ContainsKey($rel)) {
            $preexisting++
            continue
        }
        git -C $Workspace update-index --skip-worktree -- $rel 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $marks.Add($rel) | Out-Null
            $marked++
        }
    }
    if ($marks.Count -gt 0) {
        Set-Content -LiteralPath $sidecar -Value $marks -Encoding UTF8
    }
    if ($marked -gt 0) {
        Write-Host ("Marked {0} tracked path(s) --skip-worktree (local edits hidden from git status)." -f $marked)
    }
    if ($preexisting -gt 0) {
        Write-Host ("Left {0} pre-existing --skip-worktree flag(s) untouched." -f $preexisting)
    }
}

function Clear-SkipWorktree {
    # Reverse of Invoke-SkipWorktree. Clears ONLY flags we set ourselves,
    # tracked via the .assert-iq/.skip-worktree-paths sidecar. Falls back
    # to the manifest walk for installs that pre-date the sidecar. Never
    # scans the index globally — that would clobber pre-existing flags the
    # user set themselves on unrelated files.
    $gd = Get-GitDir
    if (-not $gd) { return }
    $cleared = 0
    $sidecar = Join-Path $Workspace '.assert-iq/.skip-worktree-paths'
    if (Test-Path -LiteralPath $sidecar) {
        $rels = Get-Content -LiteralPath $sidecar -ErrorAction SilentlyContinue
        foreach ($rel in $rels) {
            if (-not $rel) { continue }
            git -C $Workspace update-index --no-skip-worktree -- $rel 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $cleared++ }
        }
        Remove-Item -LiteralPath $sidecar -Force -ErrorAction SilentlyContinue
    } elseif (Test-Path -LiteralPath $manifestPath) {
        # Legacy fallback: pre-sidecar installs. Walk the manifest's
        # excludable actions only.
        try {
            $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $exclSet = @($script:ExcludableActions + $script:MergedActions)
            foreach ($e in $m.paths) {
                if ($e.scope -ne 'workspace') { continue }
                if ($exclSet -notcontains $e.action) { continue }
                $rel = (ConvertTo-WorkspaceRelative $e.path) -replace '\\','/'
                git -C $Workspace update-index --no-skip-worktree -- $rel 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { $cleared++ }
            }
        } catch { }
    }
    if ($cleared -gt 0) {
        Write-Host ("Cleared --skip-worktree on {0} path(s)." -f $cleared)
    }
}

function Remove-ExcludeBlock {
    $excl = Get-ExcludeFilePath
    if (-not $excl -or -not (Test-Path -LiteralPath $excl)) {
        Write-Host "No .git/info/exclude found — nothing to do."
        return
    }
    $existing = Get-Content -LiteralPath $excl
    $kept = Remove-ManagedBlockLines $existing
    Set-Content -LiteralPath $excl -Value $kept -Encoding UTF8
    if ($script:_StripRemoved) {
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
    Clear-SkipWorktree
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $m.mode = 'committed'
            Write-AtomicFile -Path $manifestPath -Content ($m | ConvertTo-Json -Depth 10)
            Write-Host "Updated ${manifestPath}: mode -> committed"
            # Repopulate ManifestEntries from disk so Write-ExcludeBlock sees them.
            $script:ManifestEntries = New-Object System.Collections.Generic.List[object]
            foreach ($p in $m.paths) { $script:ManifestEntries.Add($p) | Out-Null }
        } catch {
            Write-Warning "Could not update manifest mode: $_"
        }
    }
    # Re-write the managed block in committed mode so the always-on backup-glob
    # exclusions remain — only the per-path entries are dropped.
    $Mode = 'committed'
    Write-ExcludeBlock
    Write-Host ''
    Write-Host 'Pack files are now visible to git. Suggested next steps:'
    Write-Host '  git status                       # confirm pack files are untracked'
    Write-Host '  git add .assert-iq .claude .github CLAUDE.md AGENTS.md'
    Write-Host '  git commit -m "chore: adopt Assert.IQ agent pack"'
    exit 0
}

# =============================================================================
# -Uninstall short-circuit
# =============================================================================

function Invoke-Uninstall {
    $prefix = if ($DryRun) { '[dry-run] ' } else { '' }

    Write-Host '=== Assert.IQ uninstall ==='
    Write-Host "Workspace: $Workspace"
    Write-Host "Manifest:  $manifestPath"
    if ($User) {
        Write-Host 'Scope:     workspace + user-global slots'
    } else {
        Write-Host 'Scope:     workspace only (use -User to also remove user-global copies)'
    }
    if ($DryRun) { Write-Host 'Mode:      DRY RUN (no files will be changed)' }
    Write-Host ''

    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Host "No manifest found at $manifestPath."
        Write-Host 'Nothing to uninstall (or this workspace was not bootstrapped).'
        return
    }

    if (-not $DryRun -and -not $Yes) {
        $isInteractive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
        if ($isInteractive) {
            Write-Host 'This will:'
            Write-Host '  - delete files the bootstrap created in this workspace'
            Write-Host '  - restore originals where the bootstrap modified your files (from .assert-iq.pre-install backups)'
            Write-Host '  - remove any /assert-iq-tailor snapshots (.assert-iq.pre-tailor)'
            Write-Host '  - strip the trial-mode block from .git/info/exclude (if any)'
            Write-Host '  - remove the rendered .assert-iq/dreaming/session-events.json (the memory store is preserved)'
            if ($User) {
                Write-Host '  - also remove user-scope copies in ~/.assert-iq, ~/.claude, and the user prompts dir'
            }
            Write-Host "  - delete $manifestPath"
            Write-Host ''
            $ans = Read-Host 'Proceed? [y/N]'
            if ($ans -notmatch '^[yY]') { Write-Host 'Aborted.'; exit 1 }
        }
    }

    $script:UninstallStats = [pscustomobject]@{
        Removed = 0; Restored = 0; Preserved = 0; Skipped = 0
    }

    # Clear --skip-worktree BEFORE restoring backups, otherwise the file write
    # appears as a phantom modification to git after the flag is finally cleared.
    Clear-SkipWorktree

    function Remove-PathOrDir([string]$p) {
        if (-not (Test-Path -LiteralPath $p)) {
            $script:UninstallStats.Skipped++
            return
        }
        if ($DryRun) {
            Write-Host "${prefix}rm: $p"
            $script:UninstallStats.Removed++
            return
        }
        $item = Get-Item -LiteralPath $p -Force
        # Symlinks (including directory symlinks) must be unlinked, never recursed.
        if ($item.LinkType -in @('SymbolicLink','Junction')) {
            try {
                if ($item.PSIsContainer) {
                    [System.IO.Directory]::Delete($p)
                } else {
                    [System.IO.File]::Delete($p)
                }
            } catch {
                Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
            }
        } elseif ($item.PSIsContainer) {
            Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        }
        $script:UninstallStats.Removed++
    }

    function Restore-Backup([string]$backup) {
        $original = $backup -replace '\.assert-iq\.pre-install$',''
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
            Write-Warning "${prefix}backup not found, skipping restore: $backup"
            $script:UninstallStats.Skipped++
            return
        }
        if ($DryRun) {
            Write-Host "${prefix}restore: $original  (from $backup)"
            $script:UninstallStats.Restored++
            return
        }
        if (Test-Path -LiteralPath $original -PathType Leaf) {
            # Smart-save: only emit .uninstall-saved when the user genuinely
            # edited the original between install and uninstall. Compare
            # current SHA to the recorded post-install SHA when available
            # (works for both JSON and markdown merges); fall back to
            # markdown-marker strip-and-compare for installs that pre-date
            # SHA recording.
            $shouldSave = $true
            $recordedSha = Get-MergeResultSha -Path $original
            if ($recordedSha) {
                $currentSha = Get-FileSha256 -Path $original
                if ($currentSha -and $currentSha -eq $recordedSha) {
                    $shouldSave = $false
                }
            } else {
                try {
                    $rawCurrent = [System.IO.File]::ReadAllText($original)
                    if ($rawCurrent -match '<!-- assert-iq:begin') {
                        $stripped = [regex]::Replace($rawCurrent, '(?s)<!-- assert-iq:begin[^\n]*-->.*?<!-- assert-iq:end -->(\r?\n)?(\r?\n)?', '')
                        $rawBackup = [System.IO.File]::ReadAllText($backup)
                        if ($stripped -eq $rawBackup) { $shouldSave = $false }
                    }
                } catch { }
            }
            if ($shouldSave) {
                Copy-Item -LiteralPath $original -Destination "$original.assert-iq.uninstall-saved" -Force -ErrorAction SilentlyContinue
            }
        }
        Copy-Item -LiteralPath $backup -Destination $original -Force
        Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
        $script:UninstallStats.Restored++
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $entries  = @($manifest.paths)

    # Originals that were backed up (and will be restored from a backup) must
    # not be removed by a later 'overwritten' / 'merged_*' entry.
    $script:RestoredOriginals = @{}
    foreach ($be in $entries | Where-Object { $_.action -eq 'pre_install_backup' }) {
        $orig = $be.path -replace '\.assert-iq\.pre-install$',''
        $script:RestoredOriginals[$orig] = $true
    }

    function Invoke-Entry($e) {
        if ($e.scope -eq 'user' -and -not $User) {
            $script:UninstallStats.Preserved++
            return
        }
        # The Dreaming memory store is the user's data — never removed on uninstall.
        if ($e.action -ne 'pre_install_backup' -and (($e.path -replace '\\','/') -like '*/.assert-iq/memory/*')) {
            $script:UninstallStats.Preserved++
            return
        }
        switch ($e.action) {
            'pre_install_backup' { Restore-Backup $e.path }
            { $script:RemovableActions -contains $_ } {
                if ($script:RestoredOriginals.ContainsKey($e.path)) {
                    # Backup was restored at this path; leave the user's file in place.
                    $script:UninstallStats.Preserved++
                } else {
                    Remove-PathOrDir $e.path
                }
            }
            { $script:MergedActions -contains $_ } {
                if ($script:RestoredOriginals.ContainsKey($e.path)) {
                    # Will be restored by the corresponding pre_install_backup entry.
                } elseif ($e.action -eq 'merged_markdown' -and (Test-Path -LiteralPath $e.path -PathType Leaf)) {
                    # Fallback when the backup is gone: snip the assert-iq
                    # marker block (and one trailing blank line if present).
                    $content = Get-Content -LiteralPath $e.path -Raw -ErrorAction SilentlyContinue
                    if ($content -and $content -match '<!-- assert-iq:begin') {
                        if ($DryRun) {
                            Write-Host "${prefix}snip marker block: $($e.path)"
                            $script:UninstallStats.Restored++
                        } else {
                            $pattern = "(?s)<!-- assert-iq:begin[^\n]*-->.*?<!-- assert-iq:end -->(\r?\n)?(\r?\n)?"
                            $cleaned = [regex]::Replace($content, $pattern, '')
                            if ([string]::IsNullOrEmpty($cleaned)) {
                                Remove-Item -LiteralPath $e.path -Force -ErrorAction SilentlyContinue
                            } else {
                                Write-AtomicFile -Path $e.path -Content $cleaned
                            }
                            $script:UninstallStats.Restored++
                        }
                    } else {
                        Write-Host "preserved (no pre-install backup): $($e.path)"
                        $script:UninstallStats.Preserved++
                    }
                } else {
                    Write-Host "preserved (no pre-install backup): $($e.path)"
                    $script:UninstallStats.Preserved++
                }
            }
            default {
                Write-Warning "unknown manifest action '$($e.action)' for $($e.path) — skipping (manifest may be from a newer pack version)"
                $script:UninstallStats.Skipped++
            }
        }
    }

    # Restore backups first so the original files exist before we try to clean up modified copies.
    foreach ($e in $entries | Where-Object { $_.action -eq 'pre_install_backup' }) {
        Invoke-Entry $e
    }
    foreach ($e in $entries | Where-Object { $_.action -ne 'pre_install_backup' }) {
        Invoke-Entry $e
    }

    # Rendered session-events.json — per-machine, regenerated on next install.
    # The memory store (.assert-iq/memory/) is deliberately NOT cleared here.
    foreach ($d in @(
            (Join-Path $Workspace '.assert-iq\dreaming\session-events.json'),
            (Join-Path $Workspace '.assert-iq\memory\.dream\state.lock'))) {
        if (Test-Path -LiteralPath $d) { Remove-PathOrDir $d }
    }
    if ($User) {
        $userEventsJson = Join-Path $env:USERPROFILE '.agents\.assert-iq\dreaming\session-events.json'
        if (Test-Path -LiteralPath $userEventsJson) { Remove-PathOrDir $userEventsJson }
    }

    # The memory store is the user's data — preserved when it holds real dream
    # content, but a pristine never-dreamed seed is just install scaffolding, so
    # remove it for a clean uninstall.
    function Remove-SeedMemory([string]$mem) {
        if (-not (Test-Path -LiteralPath $mem -PathType Container)) { return }
        $hasTopics = @(Get-ChildItem -LiteralPath (Join-Path $mem 'topics') -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue).Count -gt 0
        $hasLogs   = @(Get-ChildItem -LiteralPath (Join-Path $mem 'logs') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.gitkeep' }).Count -gt 0
        $memIndex  = Join-Path $mem 'MEMORY.md'
        $dreamt = $false
        if (Test-Path -LiteralPath $memIndex -PathType Leaf) {
            $raw = Get-Content -LiteralPath $memIndex -Raw -ErrorAction SilentlyContinue
            if ($raw -and ($raw -notmatch 'Last consolidated: never')) { $dreamt = $true }
        }
        if ($hasTopics -or $hasLogs -or $dreamt) {
            Write-Host "Preserved your Dreaming memory store (has consolidated content): $mem"
            return
        }
        if ($DryRun) { Write-Host "${prefix}rm: $mem (pristine seed)" }
        else { Remove-Item -LiteralPath $mem -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Remove-SeedMemory (Join-Path $Workspace '.assert-iq\memory')
    if ($User) {
        Remove-SeedMemory (Join-Path $env:USERPROFILE '.agents\.assert-iq\memory')
    }

    # Sweep orphaned /assert-iq-tailor snapshots. These *.assert-iq.pre-tailor
    # files are created by the tailor skill (not this script, so they aren't in
    # the manifest). The pack files they snapshot are being removed above, so
    # the snapshots are now meaningless — clean them up rather than leave litter.
    # Confined to the dirs the tailor skill writes to, and the suffix is unique
    # to our tooling, so this can't touch unrelated user files.
    foreach ($d in @(
            (Join-Path $Workspace '.assert-iq'),
            (Join-Path $Workspace '.github\instructions'),
            (Join-Path $Workspace '.vscode'))) {
        if (Test-Path -LiteralPath $d -PathType Container) {
            foreach ($snap in (Get-ChildItem -LiteralPath $d -Recurse -File -Filter '*.assert-iq.pre-tailor' -ErrorAction SilentlyContinue)) {
                Remove-PathOrDir $snap.FullName
            }
        }
    }

    if (-not $DryRun) {
        # First, clean nested empty subdirectories left by tree-style copies
        # (.github/skills/<skill>/, eval-optimizer/references/, etc.).
        $treeRoots = @(
            (Join-Path $Workspace '.github\skills'),
            (Join-Path $Workspace '.github\agents'),
            (Join-Path $Workspace '.claude\agents'),
            (Join-Path $Workspace '.assert-iq\dreaming'))
        if ($User) {
            $treeRoots += @($userVscodeSkills, $userClaudeSkills, $userAssertIq, (Join-Path $env:USERPROFILE '.agents\.assert-iq\dreaming'))
        }
        foreach ($tree in $treeRoots) {
            if ((Test-Path -LiteralPath $tree -PathType Container) -and `
                ((Get-Item -LiteralPath $tree -Force).LinkType -notin @('SymbolicLink','Junction'))) {
                Get-ChildItem -LiteralPath $tree -Recurse -Force -Directory -ErrorAction SilentlyContinue |
                    Sort-Object -Property FullName -Descending |
                    ForEach-Object {
                        if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)) {
                            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                        }
                    }
            }
        }
        $emptyDirs = @(
            (Join-Path $Workspace '.assert-iq\dreaming'),
            (Join-Path $Workspace '.vscode'),
            (Join-Path $Workspace '.claude\agents'),
            (Join-Path $Workspace '.claude\skills'),
            (Join-Path $Workspace '.claude'),
            (Join-Path $Workspace '.github\instructions'),
            (Join-Path $Workspace '.github\agents'),
            (Join-Path $Workspace '.github\skills'),
            (Join-Path $Workspace '.github'),
            (Join-Path $Workspace '.assert-iq'))
        if ($User) {
            $emptyDirs += @(
                $userVscodeSkills,
                $userAgentsDir,
                $userClaudeSkills,
                $userClaudeDir,
                $userAssertIq)
        }
        foreach ($d in $emptyDirs) {
            if ((Test-Path -LiteralPath $d -PathType Container) -and `
                ((Get-Item -LiteralPath $d -Force).LinkType -notin @('SymbolicLink','Junction')) -and `
                -not (Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $d -Force -ErrorAction SilentlyContinue
            }
        }

        # Manifest-derived safety net: rmdir every ancestor dir of paths we
        # just removed (deepest-first, scope-gated, symlink-safe). Future
        # additions don't have to update the hardcoded lists above — if the
        # path went into the manifest, its empty parent dirs get reaped here.
        $ancestorSet = @{}
        foreach ($e in $entries) {
            if ($e.scope -eq 'user' -and -not $User) { continue }
            $stop = if ($e.scope -eq 'user') { $userHome } else { $Workspace }
            $cur  = Split-Path -Parent $e.path
            while ($cur -and $cur -ne $stop -and $cur.Length -gt 1) {
                $ancestorSet[$cur] = $true
                $next = Split-Path -Parent $cur
                if ($next -eq $cur) { break }
                $cur = $next
            }
        }
        # Sort by path-segment depth, not string length — a deeper sibling
        # may have a shorter total path than a shallow one with a long name.
        foreach ($d in ($ancestorSet.Keys | Sort-Object -Property @{Expression={($_ -split '[\\/]').Length}; Descending=$true})) {
            if ((Test-Path -LiteralPath $d -PathType Container) -and `
                ((Get-Item -LiteralPath $d -Force).LinkType -notin @('SymbolicLink','Junction')) -and `
                -not (Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $d -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if ($DryRun) {
        Write-Host "${prefix}rm: $manifestPath"
    } else {
        Remove-Item -LiteralPath $manifestPath -Force -ErrorAction SilentlyContinue
        $shaSidecar = Join-Path $Workspace '.assert-iq/.merge-result-shas'
        $swSidecar  = Join-Path $Workspace '.assert-iq/.skip-worktree-paths'
        $baseDir    = Join-Path $Workspace '.assert-iq/.base'
        Remove-Item -LiteralPath $shaSidecar -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $swSidecar  -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $baseDir -Recurse -Force -ErrorAction SilentlyContinue
        $mDir = Split-Path -Parent $manifestPath
        if ((Test-Path -LiteralPath $mDir) -and `
            -not (Get-ChildItem -LiteralPath $mDir -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $mDir -Force -ErrorAction SilentlyContinue
        }
    }

    # Strip the managed exclude block last, after the manifest is gone.
    Remove-ExcludeBlock | Out-Null

    Write-Host ''
    Write-Host ("Summary: {0} removed, {1} restored from backup, {2} preserved, {3} skipped." -f `
        $script:UninstallStats.Removed, $script:UninstallStats.Restored, `
        $script:UninstallStats.Preserved, $script:UninstallStats.Skipped)

    if (-not $User) {
        $userCount = @($entries | Where-Object { $_.scope -eq 'user' }).Count
        if ($userCount -gt 0) {
            Write-Host ''
            Write-Host "Note: $userCount user-scope path(s) were preserved."
            Write-Host '      Re-run with -User to also remove user-global copies.'
        }
    }
    Write-Host ''
    if ($DryRun) {
        Write-Host 'Dry run complete. Re-run without -DryRun to apply.'
    } else {
        Write-Host 'Uninstall complete.'
    }
}

if ($doUninstall) {
    Invoke-Uninstall
    exit 0
}

# =============================================================================
# Mode resolution
# =============================================================================

function Resolve-Mode {
    if ($Mode -eq 'trial' -or $Mode -eq 'committed') { return }
    if ($Mode -eq '' -or $Mode -eq 'ask') {
        # A prior install pins the mode — never silently flip trial<->committed
        # on a plain re-run.
        if (Test-Path -LiteralPath $manifestPath) {
            try {
                $priorMode = (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).mode
                if ($priorMode -eq 'trial' -or $priorMode -eq 'committed') { $script:Mode = $priorMode; return }
            } catch { }
        }
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

# =============================================================================
# Upgrade engine (three-way merge) + clean-slate memory seed
# =============================================================================

function Get-UpgradeRecordedSha([string]$absPath) {
    if (-not $script:OldManifest) { return '' }
    foreach ($p in $script:OldManifest.paths) {
        if ($p.path -eq $absPath) {
            if ($p.PSObject.Properties['sha']) { return $p.sha }
            return ''
        }
    }
    return ''
}

function Get-UpgradeScope([string]$relPrefix, [string]$userAbs = '') {
    # Derive a surface's install scope from the old manifest: workspace|user|skip.
    $wsAbs = ((Join-Path $Workspace $relPrefix) -replace '\\','/')
    foreach ($p in $script:OldManifest.paths) {
        if ($p.scope -eq 'workspace' -and (($p.path -replace '\\','/').StartsWith($wsAbs, [System.StringComparison]::OrdinalIgnoreCase))) { return 'workspace' }
    }
    if ($userAbs) {
        $uAbs = ($userAbs -replace '\\','/')
        foreach ($p in $script:OldManifest.paths) {
            if ($p.scope -eq 'user' -and (($p.path -replace '\\','/').StartsWith($uAbs, [System.StringComparison]::OrdinalIgnoreCase))) { return 'user' }
        }
    }
    return 'skip'
}

function Invoke-UpgradePrepare {
    # Validate an existing install, pin its mode, and derive which surfaces to
    # refresh from the recorded manifest so upgrade respects the original
    # selection instead of re-prompting presets.
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Error "no install manifest at $manifestPath. This workspace was not installed via bootstrap. For a pack-as-workspace install, upgrade with: git pull; ./install.ps1. For a fresh codebase install, run bootstrap without -Upgrade."
        exit 2
    }
    try {
        $script:OldManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    } catch {
        Write-Error "install manifest is not valid JSON: $manifestPath"
        exit 2
    }
    $script:InstalledVersion = if ($script:OldManifest.version) { $script:OldManifest.version } else { 'unknown' }
    $instMode = if ($script:OldManifest.mode) { $script:OldManifest.mode } else { 'committed' }
    if ($instMode -ne 'trial' -and $instMode -ne 'committed') { $instMode = 'committed' }
    # Pin mode to what was installed — never flip trial<->committed on upgrade.
    $script:Mode = $instMode

    $script:AssertIq       = Get-UpgradeScope '.assert-iq/config.yaml' (Join-Path $userAssertIq 'config.yaml')
    $script:Instructions   = Get-UpgradeScope '.github/instructions/' ($userPrompts + '/')
    $script:Claude         = Get-UpgradeScope 'CLAUDE.md' $userClaudeMd
    $script:Copilot        = Get-UpgradeScope '.github/copilot-instructions.md'
    $script:Agents         = Get-UpgradeScope 'AGENTS.md'
    $script:VSCode         = Get-UpgradeScope '.vscode/settings.json'
    $script:ClaudeSettings = Get-UpgradeScope '.claude/settings.json'
    # Dreaming rides with the session-events wiring; also bridges an upgrade
    # from a pre-Dreaming (hooks) install where .claude/settings.json existed.
    $script:Dreaming = $script:ClaudeSettings
    if ($script:Dreaming -eq 'skip' -and (Get-UpgradeScope 'hooks/') -eq 'workspace') { $script:Dreaming = 'workspace' }

    $sw = Get-UpgradeScope '.github/skills/'
    $su = 'skip'
    $uSkills = ($userVscodeSkills -replace '\\','/') + '/'
    foreach ($p in $script:OldManifest.paths) {
        if ($p.scope -eq 'user' -and (($p.path -replace '\\','/').StartsWith($uSkills, [System.StringComparison]::OrdinalIgnoreCase))) { $su = 'user'; break }
    }
    if ($sw -eq 'workspace' -and $su -eq 'user') { $script:SkillsScope = 'both' }
    elseif ($sw -eq 'workspace') { $script:SkillsScope = 'workspace' }
    elseif ($su -eq 'user') { $script:SkillsScope = 'user' }
    else { $script:SkillsScope = 'workspace' }

    $newVer = 'unknown'
    $vf = Join-Path $Source 'VERSION'
    if (Test-Path -LiteralPath $vf -PathType Leaf) { try { $newVer = (Get-Content -LiteralPath $vf -TotalCount 1).Trim() } catch { } }
    Write-Host "=== Assert.IQ upgrade: v$($script:InstalledVersion) -> v$newVer (mode: $($script:Mode)) ==="
    Write-Host 'Refreshing installed surfaces; your edits are preserved via three-way merge.'
    Write-Host ''
}

function Invoke-UpgradeThreeWay {
    # Reconstruct the installed baseline from the pack's git history at the
    # installed version, then merge the new pack version onto the user's current
    # file so their edits AND the pack's updates both land.
    param([string]$Label, [string]$Src, [string]$Dst, [string]$Scope)
    $relUnix = (ConvertTo-WorkspaceRelative $Dst) -replace '\\','/'
    $recSha = Get-UpgradeRecordedSha $Dst
    $dstSha = Get-Sha256 $Dst

    # Unedited since install -> take the new version outright.
    if ($recSha -and ($recSha -eq $dstSha)) {
        Backup-IfUserOwned -Path $Dst -Scope $Scope
        Copy-Item -LiteralPath $Src -Destination $Dst -Force
        Add-ManifestEntry 'overwritten' $Dst $Scope
        Save-Base -Content $Src -Dst $Dst
        Record $Label 'updated (pack change, unedited)' $Dst
        return
    }

    $baseTmp   = [System.IO.Path]::GetTempFileName()
    $mergedTmp = [System.IO.Path]::GetTempFileName()
    # Base resolution: prefer the install-time snapshot (works offline and with
    # no version tags), then fall back to reconstructing from the pack's git
    # history at the installed version.
    $baseFile = Get-Base $Dst
    if (-not $baseFile -and $script:InstalledVersion -ne 'unknown') {
        & git -C $Source cat-file -e "v$($script:InstalledVersion):$relUnix" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $blob = & git -C $Source show "v$($script:InstalledVersion):$relUnix" 2>$null
            if ($LASTEXITCODE -eq 0) {
                [System.IO.File]::WriteAllText($baseTmp, (($blob -join "`n") + "`n"))
                $baseFile = $baseTmp
            }
        }
    }

    $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if ($baseFile) {
        Copy-Item -LiteralPath $Dst -Destination $mergedTmp -Force
        & git merge-file -- $mergedTmp $baseFile $Src 2>$null | Out-Null
        $mergeRc = $LASTEXITCODE
        if ($mergeRc -eq 0) {
            # Clean three-way merge — non-destructive by definition.
            if ($Yes -or -not $interactive) {
                Backup-IfUserOwned -Path $Dst -Scope $Scope
                Copy-Item -LiteralPath $mergedTmp -Destination $Dst -Force
                Add-ManifestEntry 'overwritten' $Dst $Scope
                Save-MergeResultSha -Path $Dst
                Save-Base -Content $Src -Dst $Dst
                Record $Label 'merged (clean, auto)' $Dst
            } else {
                Write-Host ''
                Write-Host "Upgrade merge (clean): $Label"
                Write-Host '  Your edits and the pack update both apply cleanly.'
                $ans = Read-Host '  Apply merged result? [Y]es / [k]eep mine / [s]idecar'
                switch -Regex ($ans) {
                    '^[kK]' { Save-Base -Content $baseFile -Dst $Dst; Record $Label 'skipped (kept yours)' $Dst }
                    '^[sS]' { $side = "$Dst.assert-iq-new"; Copy-Item -LiteralPath $mergedTmp -Destination $side -Force; Add-ManifestEntry 'sidecar' $side $Scope; Save-Base -Content $baseFile -Dst $Dst; Record $Label 'sidecar (merged) -> .assert-iq-new' $side }
                    default { Backup-IfUserOwned -Path $Dst -Scope $Scope; Copy-Item -LiteralPath $mergedTmp -Destination $Dst -Force; Add-ManifestEntry 'overwritten' $Dst $Scope; Save-MergeResultSha -Path $Dst; Save-Base -Content $Src -Dst $Dst; Record $Label 'merged (clean)' $Dst }
                }
            }
        } else {
            # Conflict — you and the pack changed overlapping lines.
            if ($Yes -or -not $interactive) {
                $side = "$Dst.assert-iq-new"
                Copy-Item -LiteralPath $Src -Destination $side -Force
                Add-ManifestEntry 'sidecar' $side $Scope
                Save-Base -Content $baseFile -Dst $Dst
                Record $Label 'conflict -> sidecar (.assert-iq-new)' $side
            } else {
                Write-Host ''
                Write-Host "Upgrade merge CONFLICT: $Label"
                Write-Host '  You and the pack changed overlapping lines.'
                $ans = Read-Host '  [m]arkers into your file / [o]verwrite w/ pack / [k]eep mine / [s]idecar'
                switch -Regex ($ans) {
                    '^[mM]' { Backup-IfUserOwned -Path $Dst -Scope $Scope; Copy-Item -LiteralPath $mergedTmp -Destination $Dst -Force; Add-ManifestEntry 'overwritten' $Dst $Scope; Save-MergeResultSha -Path $Dst; Save-Base -Content $Src -Dst $Dst; Record $Label 'merged (conflict markers written)' $Dst }
                    '^[oO]' { Backup-IfUserOwned -Path $Dst -Scope $Scope; Copy-Item -LiteralPath $Src -Destination $Dst -Force; Add-ManifestEntry 'overwritten' $Dst $Scope; Save-Base -Content $Src -Dst $Dst; Record $Label 'overwritten (pack)' $Dst }
                    '^[sS]' { $side = "$Dst.assert-iq-new"; Copy-Item -LiteralPath $Src -Destination $side -Force; Add-ManifestEntry 'sidecar' $side $Scope; Save-Base -Content $baseFile -Dst $Dst; Record $Label 'sidecar -> .assert-iq-new' $side }
                    default { Save-Base -Content $baseFile -Dst $Dst; Record $Label 'skipped (kept yours)' $Dst }
                }
            }
        }
    } else {
        # No reconstructable baseline -> conservative 2-way resolver (never clobbers).
        $choice = Resolve-Conflict -Src $Src -Dst $Dst -Label "$Label (no base — merge unavailable)"
        switch ($choice) {
            'keep'      { Record $Label 'skipped (kept yours)' $Dst }
            'overwrite' { Backup-IfUserOwned -Path $Dst -Scope $Scope; Copy-Item -LiteralPath $Src -Destination $Dst -Force; Add-ManifestEntry 'overwritten' $Dst $Scope; Save-Base -Content $Src -Dst $Dst; Record $Label 'overwritten' $Dst }
            'merge'     { Merge-MarkdownFile -Label $Label -Src $Src -Dst $Dst -Scope $Scope }
            'sidecar'   { $side = "$Dst.assert-iq-new"; Copy-Item -LiteralPath $Src -Destination $side -Force; Add-ManifestEntry 'sidecar' $side $Scope; Record $Label 'sidecar -> .assert-iq-new' $side }
        }
    }
    Remove-Item -LiteralPath $baseTmp -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $mergedTmp -Force -ErrorAction SilentlyContinue
}

function Invoke-UpgradeOrphans {
    # Remove files the OLD install placed that the new pack no longer ships.
    # Prompt each; never touch the memory store; report-only when non-interactive.
    if (-not $script:OldManifest) { return }
    $thisRun = @{}
    foreach ($e in $script:ManifestEntries) { $thisRun[$e.path] = $true }
    $removable = @('created','unchanged_owned','overwritten','rendered','sidecar','merged_settings','merged_hooks_key','merged_markdown')
    $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    $bulk = ''
    foreach ($p in $script:OldManifest.paths) {
        if ($p.scope -ne 'workspace') { continue }
        if ($removable -notcontains $p.action) { continue }
        $abs = $p.path
        $relUnix = (ConvertTo-WorkspaceRelative $abs) -replace '\\','/'
        if ($relUnix -like '.assert-iq/memory/*') { continue }
        if ($relUnix -like '*.assert-iq.pre-install' -or $relUnix -like '*.assert-iq-new' -or $relUnix -like '*.assert-iq.uninstall-saved' -or $relUnix -like '*.assert-iq.pre-tailor') { continue }
        if ($thisRun.ContainsKey($abs)) { continue }
        if (Test-Path -LiteralPath (Join-Path $Source $relUnix)) { continue }
        if (-not (Test-Path -LiteralPath $abs)) { continue }

        $decision = $bulk
        if (-not $decision) {
            if ($Yes -or -not $interactive) {
                Write-Host "  orphan from a previous version (kept; re-run interactively to remove): $relUnix"
                continue
            }
            $decision = Read-Host "Orphan from a previous version: $relUnix — [r]emove / [k]eep / [R]emove-all / [K]eep-all"
        }
        if ($decision -eq 'R') { $bulk = 'R'; $decision = 'r' }
        elseif ($decision -eq 'K') { $bulk = 'K'; $decision = 'k' }
        if ($decision -eq 'r') {
            Remove-Item -LiteralPath $abs -Force -ErrorAction SilentlyContinue
            try {
                $mf = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                $mf.paths = @($mf.paths | Where-Object { $_.path -ne $abs })
                Write-AtomicFile -Path $manifestPath -Content ($mf | ConvertTo-Json -Depth 10)
            } catch { }
            Write-Host "  removed: $relUnix"
        } else {
            Write-Host "  kept: $relUnix"
        }
    }
}

function Seed-MemoryIndex {
    # Write a clean MEMORY.md template ONLY if one is not already present, so
    # an upgrade never overwrites the user's dreamed index.
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return }
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $content = @'
# MEMORY.md — Project Memory Index

_Last consolidated: never — run `/dream` to populate_

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
    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Seed-MemoryStore {
    # Clean-slate seed for the Dreaming memory. NEVER copies the pack's own
    # accumulated dream data (topics/*.md, logs) so every install/upgrade starts
    # fresh. Only creates what's missing, so an upgrade preserves user content.
    param([string]$MemDir)
    New-Item -ItemType Directory -Path (Join-Path $MemDir 'topics') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $MemDir 'logs') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $MemDir '.dream') -Force | Out-Null
    $statePath = Join-Path $MemDir '.dream\state.json'
    if (-not (Test-Path -LiteralPath $statePath)) {
        Set-Content -LiteralPath $statePath -Value "{`n  `"last_dream_utc`": null,`n  `"sessions_since_dream`": 0`n}" -Encoding UTF8
    }
    $topicKeep = Join-Path $MemDir 'topics\.gitkeep'
    if (-not (Test-Path -LiteralPath $topicKeep)) { New-Item -ItemType File -Force -Path $topicKeep | Out-Null }
    $logKeep = Join-Path $MemDir 'logs\.gitkeep'
    if (-not (Test-Path -LiteralPath $logKeep)) { New-Item -ItemType File -Force -Path $logKeep | Out-Null }
    # README is static docs (not dream data) — seed it if the pack ships one.
    $srcReadme = Join-Path $Source '.assert-iq\memory\README.md'
    $dstReadme = Join-Path $MemDir 'README.md'
    if ((Test-Path -LiteralPath $srcReadme -PathType Leaf) -and -not (Test-Path -LiteralPath $dstReadme)) {
        Copy-Item -LiteralPath $srcReadme -Destination $dstReadme -Force
    }
    Seed-MemoryIndex -Path (Join-Path $MemDir 'MEMORY.md')
}

if ($doUpgrade) { Invoke-UpgradePrepare }
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
        if (-not $Dreaming)        { $Dreaming        = 'workspace' }
        if (-not $ClaudeSettings)  { $ClaudeSettings  = 'workspace' }
        if (-not $SkillsScope)     { $SkillsScope     = 'workspace' }
    }
    'portable' {
        # Skills live user-globally so every workspace can use them. The
        # workspace still receives the Assert-IQ chat agent files
        # (.github/agents/, .claude/agents/) and the install manifest so
        # uninstall stays clean; instructions, hooks, settings, MCP
        # config, and CLAUDE.md stay out. Ideal for "I want skills
        # available in every repo I open without committing the full pack".
        if (-not $AssertIq)        { $AssertIq        = 'user' }
        if (-not $Instructions)    { $Instructions    = 'user' }
        if (-not $Claude)          { $Claude          = 'user' }
        if (-not $Copilot)         { $Copilot         = 'skip' }
        if (-not $Agents)          { $Agents          = 'skip' }
        if (-not $VSCode)          { $VSCode          = 'skip' }
        if (-not $Dreaming)        { $Dreaming        = 'skip' }
        if (-not $ClaudeSettings)  { $ClaudeSettings  = 'skip' }
        if (-not $SkillsScope)     { $SkillsScope     = 'user' }
    }
    default {
        # pod (and unset)
        if (-not $AssertIq)        { $AssertIq        = 'workspace' }
        if (-not $Instructions)    { $Instructions    = 'workspace' }
        if (-not $Claude)          { $Claude          = 'workspace' }
        if (-not $Copilot)         { $Copilot         = 'workspace' }
        if (-not $Agents)          { $Agents          = 'workspace' }
        if (-not $VSCode)          { $VSCode          = 'workspace' }
        if (-not $Dreaming)        { $Dreaming        = 'workspace' }
        if (-not $ClaudeSettings)  { $ClaudeSettings  = 'workspace' }
        if (-not $SkillsScope)     { $SkillsScope     = 'workspace' }
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
    # Allowlist: only these markdown files support the merge mode.
    $base = Split-Path -Leaf $Dst
    $mergeEligible = $base -in @('copilot-instructions.md','CLAUDE.md','AGENTS.md')
    switch ($script:ConflictBulkChoice) {
        'K' { return 'keep' }
        'O' { return 'overwrite' }
        'M' {
            if ($mergeEligible) { return 'merge' } else { return 'keep' }
        }
        'S' { return 'sidecar' }
    }
    $isInteractive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if (-not $isInteractive) { return 'keep' }
    Write-Host ''
    Write-Host "Conflict: $Label"
    Write-Host "  existing: $Dst"
    Write-Host "  pack:     $Src"
    if ($mergeEligible) {
        $prompt = '  [k]eep / [o]verwrite / [m]erge (recommended) / [s]idecar (.assert-iq-new) / [d]iff / [K/O/M/S]all / [a]bort'
    } else {
        $prompt = '  [k]eep / [o]verwrite / [s]idecar (.assert-iq-new) / [d]iff / [K/O/S]all / [a]bort'
    }
    while ($true) {
        $ans = Read-Host $prompt
        switch ($ans) {
            'k' { return 'keep' }
            'o' { return 'overwrite' }
            'm' {
                if ($mergeEligible) { return 'merge' }
                else { Write-Host '  (merge not available for this file)' }
            }
            's' { return 'sidecar' }
            'K' { $script:ConflictBulkChoice = 'K'; return 'keep' }
            'O' { $script:ConflictBulkChoice = 'O'; return 'overwrite' }
            'M' {
                if ($mergeEligible) {
                    $script:ConflictBulkChoice = 'M'; return 'merge'
                } else { Write-Host '  (merge not available for this file)' }
            }
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
            default {
                if ($mergeEligible) {
                    Write-Host '  (please type one of k, o, m, s, d, K, O, M, S, a)'
                } else {
                    Write-Host '  (please type one of k, o, s, d, K, O, S, a)'
                }
            }
        }
    }
}

# Merge $Src markdown into $Dst by managing an idempotent marker block at
# the top of $Dst. First merge prepends pack content wrapped in
# <!-- assert-iq:begin v=... --> ... <!-- assert-iq:end --> followed by a
# blank line and the user's existing content. Re-merge replaces the block
# in place; user content outside the markers is never touched. Used only
# for the markdown allowlist files (copilot-instructions.md, CLAUDE.md,
# AGENTS.md).
function Merge-MarkdownFile {
    param([string]$Label, [string]$Src, [string]$Dst, [string]$Scope)
    $packVersion = 'unknown'
    $versionFile = Join-Path $Source 'VERSION'
    if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
        try {
            $pv = (Get-Content -LiteralPath $versionFile -TotalCount 1).Trim()
            if ($pv) { $packVersion = $pv }
        } catch { }
    }
    $beginMarker = "<!-- assert-iq:begin v=$packVersion -->"
    $endMarker   = '<!-- assert-iq:end -->'
    Backup-IfUserOwned -Path $Dst -Scope $Scope
    $existing = Get-Content -LiteralPath $Dst -Raw -ErrorAction SilentlyContinue
    if ($null -eq $existing) { $existing = '' }
    $packContent = Get-Content -LiteralPath $Src -Raw -ErrorAction Stop
    if ($null -eq $packContent) { $packContent = '' }
    $nl = "`n"
    if ($existing -match '<!-- assert-iq:begin') {
        # Replace existing block in place (regex DOTALL via (?s)). There is
        # only ever one assert-iq block per file, so a global replace is fine.
        $pattern = '(?s)<!-- assert-iq:begin[^\n]*-->.*?<!-- assert-iq:end -->'
        $newBlock = "$beginMarker$nl$($packContent.TrimEnd("`r","`n"))$nl$endMarker"
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $newBlock }
        $merged = [regex]::Replace($existing, $pattern, $evaluator)
    } else {
        $userPart = $existing
        $merged = "$beginMarker$nl$($packContent.TrimEnd("`r","`n"))$nl$endMarker$nl$nl$userPart"
    }
    # Write atomically (Write-AtomicFile rejects empty content; merged is always non-empty).
    Write-AtomicFile -Path $Dst -Content $merged
    Add-ManifestEntry 'merged_markdown' $Dst $Scope
    Save-MergeResultSha -Path $Dst
    Record $Label 'merged (markdown markers)' $Dst
}

function Copy-FileScoped {
    param([string]$Label, [string]$Src, [string]$Dst, [string]$Scope)

    # Never touch the user's Dreaming memory on upgrade — it's their data.
    if ($doUpgrade -and (($Dst -replace '\\','/') -like '*/.assert-iq/memory/*')) {
        Record $Label 'skipped (memory preserved)' $Dst
        return
    }
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
        Add-ManifestEntry 'created' $Dst $Scope
        Save-Base -Content $Src -Dst $Dst
        Record $Label 'copied' $Dst
        return
    }

    $shSrc = Get-Sha256 $Src
    $shDst = Get-Sha256 $Dst
    if ($shSrc -and ($shSrc -eq $shDst)) {
        Add-ManifestEntry 'unchanged_owned' $Dst $Scope
        Save-Base -Content $Src -Dst $Dst
        Record $Label 'unchanged (pack-owned)' $Dst
        return
    }

    # On upgrade, three-way merge to preserve user edits.
    if ($doUpgrade) {
        Invoke-UpgradeThreeWay -Label $Label -Src $Src -Dst $Dst -Scope $Scope
        return
    }

    $choice = Resolve-Conflict -Src $Src -Dst $Dst -Label $Label
    switch ($choice) {
        'keep' {
            Record $Label 'skipped (user kept existing)' $Dst
        }
        'overwrite' {
            Backup-IfUserOwned -Path $Dst -Scope $Scope
            Copy-Item -LiteralPath $Src -Destination $Dst -Force
            Add-ManifestEntry 'overwritten' $Dst $Scope
            Save-Base -Content $Src -Dst $Dst
            Record $Label 'overwritten' $Dst
        }
        'merge' {
            Merge-MarkdownFile -Label $Label -Src $Src -Dst $Dst -Scope $Scope
        }
        'sidecar' {
            $side = "$Dst.assert-iq-new"
            Copy-Item -LiteralPath $Src -Destination $side -Force
            Add-ManifestEntry 'sidecar' $side $Scope
            Record $Label 'sidecar -> .assert-iq-new' $side
        }
    }
}

function Copy-TreeScoped {
    param([string]$Label, [string]$SrcDir, [string]$DstDir, [string]$Scope, [string[]]$Exclude = @())

    if (-not (Test-Path -LiteralPath $SrcDir -PathType Container)) {
        Record $Label 'missing-source' $SrcDir
        return
    }
    Get-ChildItem -LiteralPath $SrcDir -Recurse -File | ForEach-Object {
        # Skip OS/editor cruft.
        if ($_.Name -in @('.DS_Store','Thumbs.db','desktop.ini')) { return }
        $rel = $_.FullName.Substring($SrcDir.Length).TrimStart('\','/')
        $relUx = $rel -replace '\\','/'
        # Skip excluded relative-path prefixes.
        $skip = $false
        foreach ($pre in $Exclude) { if ($relUx -like "$pre*") { $skip = $true; break } }
        if ($skip) { return }
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
        Add-ManifestEntry 'unchanged_owned' $Dst $Scope
        Record $Label 'unchanged (pack-owned)' $Dst
        return
    }
    try {
        $packJson = Get-Content -LiteralPath $Src -Raw | ConvertFrom-Json
        $userJson = Get-Content -LiteralPath $Dst -Raw | ConvertFrom-Json
        $merged   = Merge-Hashtables -Pack $packJson -User $userJson
        $mergedContent = $merged | ConvertTo-Json -Depth 32
        Write-OrSkipIfUnchanged -Label $Label -MergedContent $mergedContent `
            -Dst $Dst -Scope $Scope `
            -ChangedAction 'merged_settings' `
            -ChangedMessage 'merged (additive, yours wins)'
    } catch {
        # Parse or write failed — sidecar.
        $side = "$Dst.assert-iq-new"
        Copy-Item -LiteralPath $Src -Destination $side -Force
        Add-ManifestEntry 'sidecar' $side $Scope
        Record $Label 'sidecar (merge failed) -> .assert-iq-new' $side
    }
}

function Get-RenderedEventsJson {
    param([string]$PackRoot)
    $template = Join-Path $Source '.assert-iq\dreaming\session-events.template.json'
    if (-not (Test-Path -LiteralPath $template)) { return '' }
    $lib = Join-Path $Source '.assert-iq\dreaming\scripts\lib\render-events.ps1'
    if (-not (Test-Path -LiteralPath $lib)) { return '' }
    . $lib
    $tmp = [System.IO.Path]::GetTempFileName()
    Render-EventsTemplate -Template $template -Out $tmp -PackRoot $PackRoot
    return $tmp
}

# =============================================================================
# Per-surface handlers
# =============================================================================

function Step-AssertIq {
    # dreaming/ and memory/ are owned by Step-Dreaming (clean-slate seed +
    # rendered session-events.json); per-workspace tracking files are
    # gitignored. Exclude them here so nothing is double-handled.
    $aiqExclude = @('dreaming/','memory/','.install-manifest.json','.merge-result-shas','.skip-worktree-paths','.base/')
    switch ($AssertIq) {
        'workspace' { Copy-TreeScoped '.assert-iq' (Join-Path $Source '.assert-iq') (Join-Path $Workspace '.assert-iq') 'workspace' -Exclude $aiqExclude }
        'user'      { Copy-TreeScoped '.assert-iq' (Join-Path $Source '.assert-iq') $userAssertIq 'user' -Exclude $aiqExclude }
        'skip'      { Record '.assert-iq' 'skipped (user choice)' '-' }
        default     { throw "Invalid -AssertIq: '$AssertIq'" }
    }
}

function Step-Instructions {
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

function Step-Claude {
    $src = Join-Path $Source 'CLAUDE.md'
    switch ($Claude) {
        'workspace' { Copy-FileScoped 'CLAUDE.md' $src (Join-Path $Workspace 'CLAUDE.md') 'workspace' }
        'user'      { Copy-FileScoped 'CLAUDE.md' $src $userClaudeMd 'user' }
        'skip'      { Record 'CLAUDE.md' 'skipped (user choice)' '-' }
        default     { throw "Invalid -Claude: '$Claude'" }
    }
}

function Step-Copilot {
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

function Step-Agents {
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

function Step-VSCode {
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

function Step-Dreaming {
    # Installs the Dreaming machinery (.assert-iq/dreaming/), scaffolds the
    # memory store (.assert-iq/memory/), and renders session-events.json, which
    # .vscode/settings.json's chat.hookFilesLocations points at. Rendered with
    # __PACK_ROOT__ = pack root so the scripts resolve even when
    # CLAUDE_PLUGIN_ROOT is unset.
    switch ($Dreaming) {
        'workspace' {
            $dreamSrcDir = Join-Path $Source '.assert-iq\dreaming'
            if (-not (Test-Path -LiteralPath $dreamSrcDir -PathType Container)) {
                Record '.assert-iq/dreaming/' 'missing-source' $dreamSrcDir
                return
            }
            Copy-TreeScoped '.assert-iq/dreaming' $dreamSrcDir (Join-Path $Workspace '.assert-iq\dreaming') 'workspace' -Exclude @('session-events.json')
            # Seed the memory store clean — never ships the pack's own dream data.
            $memDir = Join-Path $Workspace '.assert-iq\memory'
            Seed-MemoryStore -MemDir $memDir
            Record '.assert-iq/memory/' 'seeded (clean slate)' $memDir
            $rendered = Get-RenderedEventsJson -PackRoot $Workspace
            if (-not $rendered) {
                Record '.assert-iq/dreaming/session-events.json' 'missing-template' (Join-Path $dreamSrcDir 'session-events.template.json')
            } else {
                Copy-FileScoped '.assert-iq/dreaming/session-events.json' $rendered (Join-Path $Workspace '.assert-iq\dreaming\session-events.json') 'workspace'
                Remove-Item -LiteralPath $rendered -Force -ErrorAction SilentlyContinue
            }
        }
        'user' {
            # User-global install: machinery + memory under
            # $env:USERPROFILE\.agents\.assert-iq so the rendered template's
            # "$R/.assert-iq/dreaming/..." resolves with __PACK_ROOT__ =
            # $env:USERPROFILE\.agents.
            $dreamSrcDir = Join-Path $Source '.assert-iq\dreaming'
            if (-not (Test-Path -LiteralPath $dreamSrcDir -PathType Container)) {
                Record '.assert-iq/dreaming/ (user)' 'missing-source' $dreamSrcDir
                return
            }
            $userBase = Join-Path $env:USERPROFILE '.agents\.assert-iq'
            Copy-TreeScoped '.assert-iq/dreaming' $dreamSrcDir (Join-Path $userBase 'dreaming') 'user' -Exclude @('session-events.json')
            $memDir = Join-Path $userBase 'memory'
            Seed-MemoryStore -MemDir $memDir
            Record '.assert-iq/memory/ (user)' 'seeded (clean slate)' $memDir
            $userPackRoot = Join-Path $env:USERPROFILE '.agents'
            $rendered = Get-RenderedEventsJson -PackRoot $userPackRoot
            if (-not $rendered) {
                Record '.assert-iq/dreaming/session-events.json (user)' 'missing-template' (Join-Path $dreamSrcDir 'session-events.template.json')
            } else {
                Copy-FileScoped '.assert-iq/dreaming/session-events.json' $rendered (Join-Path $userBase 'dreaming\session-events.json') 'user'
                Remove-Item -LiteralPath $rendered -Force -ErrorAction SilentlyContinue
            }
            $Script:UserDreamingInstalled = $true
        }
        'skip' { Record '.assert-iq/dreaming/' 'skipped (user choice)' '-' }
        default { throw "Invalid -Dreaming: '$Dreaming' (workspace|user|skip)" }
    }
}

function Step-ClaudeSettings {
    # Merge only the .hooks key into .claude/settings.json; preserve everything
    # else. Copilot side disables this file via chat.hookFilesLocations to
    # avoid double-fire.
    switch ($ClaudeSettings) {
        'workspace' {
            $rendered = Get-RenderedEventsJson -PackRoot $Workspace
            if (-not $rendered) {
                Record '.claude/settings.json' 'missing-template' (Join-Path $Source '.assert-iq\dreaming\session-events.template.json')
                return
            }
            $dst = Join-Path $Workspace '.claude\settings.json'
            $parent = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Force -Path $parent | Out-Null
            }
            if (-not (Test-Path -LiteralPath $dst)) {
                Copy-Item -LiteralPath $rendered -Destination $dst -Force
                Add-ManifestEntry 'created' $dst 'workspace'
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
                    $mergedContent = [pscustomobject]$out | ConvertTo-Json -Depth 32
                    Write-OrSkipIfUnchanged -Label '.claude/settings.json' `
                        -MergedContent $mergedContent -Dst $dst -Scope 'workspace' `
                        -ChangedAction 'merged_hooks_key' `
                        -ChangedMessage 'merged hooks key'
                } catch {
                    $side = "$dst.assert-iq-new"
                    Copy-Item -LiteralPath $rendered -Destination $side -Force
                    Add-ManifestEntry 'sidecar' $side 'workspace'
                    Record '.claude/settings.json' 'sidecar (merge failed)' $side
                }
            }
            Remove-Item -LiteralPath $rendered -Force -ErrorAction SilentlyContinue
        }
        'skip' { Record '.claude/settings.json' 'skipped (user choice)' '-' }
        default { throw "Invalid -ClaudeSettings: '$ClaudeSettings'" }
    }
}

function Step-GithubSkills {
    # Skills can live in the workspace (.github/skills) so they ship with the
    # repo, OR user-globally in ~/.agents/skills (VS Code Copilot Chat) so
    # they work in every workspace. SkillsScope selects which, or 'both'.
    if ($SkillsScope -in @('workspace','both')) {
        Copy-TreeScoped -Label '.github/skills' `
            -SrcDir (Join-Path $Source '.github\skills') `
            -DstDir (Join-Path $Workspace '.github\skills') `
            -Scope 'workspace'
    }
    if ($SkillsScope -in @('user','both')) {
        # Label is display-only; the real destination is $userVscodeSkills.
        Copy-TreeScoped -Label '~/.agents/skills' `
            -SrcDir (Join-Path $Source '.github\skills') `
            -DstDir $userVscodeSkills `
            -Scope 'user'
    }
}

function Step-GithubAgents {
    # Custom chat modes (e.g. Assert-IQ.agent.md) read from .github/agents.
    $src = Join-Path $Source '.github\agents'
    if (Test-Path -LiteralPath $src -PathType Container) {
        Copy-TreeScoped -Label '.github/agents' `
            -SrcDir $src `
            -DstDir (Join-Path $Workspace '.github\agents') `
            -Scope 'workspace'
    }
}

function Step-ClaudeAgents {
    # Claude Code subagents must live in .claude/agents within the workspace.
    $src = Join-Path $Source '.claude\agents'
    if (Test-Path -LiteralPath $src -PathType Container) {
        Copy-TreeScoped -Label '.claude/agents' `
            -SrcDir $src `
            -DstDir (Join-Path $Workspace '.claude\agents') `
            -Scope 'workspace'
    }
}

function Step-ClaudeSkillsLink {
    # Mirror install.ps1: create .claude/skills as a symlink to ../.github/skills
    # so Claude Code auto-discovers the same skills Copilot uses. On Windows
    # without Developer Mode (or filesystems that reject symlinks) fall back to
    # a recursive copy.
    #
    # SkillsScope controls placement:
    #   workspace -> only the workspace symlink (today's behavior)
    #   user      -> only ~/.claude/skills (no workspace symlink at all)
    #   both      -> workspace symlink AND ~/.claude/skills
    if ($SkillsScope -in @('user','both')) {
        # Label is display-only; the real destination is $userClaudeSkills.
        Copy-TreeScoped -Label '~/.claude/skills' `
            -SrcDir (Join-Path $Source '.github\skills') `
            -DstDir $userClaudeSkills `
            -Scope 'user'
    }
    if ($SkillsScope -eq 'user') {
        return
    }
    $dst       = Join-Path $Workspace '.claude\skills'
    $targetRel = '..\.github\skills'
    $targetAbs = Join-Path $Workspace '.github\skills'

    if (Test-Path -LiteralPath $dst) {
        $existing = Get-Item -LiteralPath $dst -Force
        # PS 7+ exposes Target as string[] (length-1 for symlinks). Coerce
        # to an array and use -contains so we get a real bool either way.
        $targets = @($existing.Target)
        $matchTargets = @($targetRel, ($targetRel -replace '\\','/'))
        $isPackOwned = ($existing.LinkType -in @('SymbolicLink','Junction')) -and
                       (@($targets | Where-Object { $matchTargets -contains $_ }).Count -gt 0)
        if ($isPackOwned) {
            Add-ManifestEntry 'unchanged_owned' $dst 'workspace'
            Record '.claude/skills' 'unchanged (pack-owned symlink)' $dst
            return
        }
        # Anything else — sidecar.
        $side = "$dst.assert-iq-new"
        if (Test-Path -LiteralPath $side) {
            Remove-Item -LiteralPath $side -Recurse -Force -ErrorAction SilentlyContinue
        }
        try {
            New-Item -ItemType SymbolicLink -Path $side -Target $targetRel -Force | Out-Null
        } catch {
            if (Test-Path -LiteralPath $targetAbs -PathType Container) {
                Copy-Item -LiteralPath $targetAbs -Destination $side -Recurse -Force
            }
        }
        Add-ManifestEntry 'sidecar' $side 'workspace'
        Record '.claude/skills' 'sidecar -> .assert-iq-new' $side
        return
    }

    $parent = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    try {
        New-Item -ItemType SymbolicLink -Path $dst -Target $targetRel -Force -ErrorAction Stop | Out-Null
        Add-ManifestEntry 'created' $dst 'workspace'
        Record '.claude/skills' "linked -> $targetRel" $dst
    } catch {
        if (Test-Path -LiteralPath $targetAbs -PathType Container) {
            Copy-Item -LiteralPath $targetAbs -Destination $dst -Recurse -Force
            Add-ManifestEntry 'created' $dst 'workspace'
            Record '.claude/skills' 'copied (symlink unavailable; enable Developer Mode then re-run)' $dst
        } else {
            Record '.claude/skills' 'missing-source' $targetAbs
        }
    }
}

Step-AssertIq
Step-Instructions
Step-Claude
Step-Copilot
Step-Agents
Step-VSCode
Step-Dreaming
Step-ClaudeSettings
Step-GithubSkills
Step-GithubAgents
Step-ClaudeAgents
Step-ClaudeSkillsLink

# =============================================================================
# Finalize: manifest + git-exclude wiring (trial mode only)
# =============================================================================

Write-Manifest

# Always write the managed exclude block — Layer 1 (backup-globs) applies in
# every mode; Layer 2 (per-path entries) only fires when $Mode -eq 'trial'.
Write-ExcludeBlock
if ($Mode -eq 'trial') {
    Invoke-SkipWorktree
}
if ($doUpgrade) { Invoke-UpgradeOrphans }

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
Write-Host "Skills:    $SkillsScope"
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

if ($Script:UserDreamingInstalled) {
    Write-Host ''
    Write-Host '─── USER-GLOBAL DREAMING INSTALLED ───'
    Write-Host 'The Dreaming machinery is at ~/.agents/.assert-iq/dreaming/ and the memory'
    Write-Host 'store at ~/.agents/.assert-iq/memory/. Session events fire across every VS'
    Write-Host 'Code workspace once you register them in your VS Code USER settings.json.'
    Write-Host ''
    Write-Host '  1. Ctrl+Shift+P -> "Preferences: Open User Settings (JSON)"'
    Write-Host '  2. Add or merge this block:'
    Write-Host ''
    Write-Host '    "chat.hookFilesLocations": {'
    Write-Host '      "~/.agents/.assert-iq/dreaming/session-events.json": true'
    Write-Host '    }'
    Write-Host ''
    Write-Host '  3. Reload the VS Code window.'
    Write-Host ''
    Write-Host 'This is one-time setup. To uninstall the user-global hooks later, run:'
    Write-Host '  scripts/bootstrap.ps1 -Uninstall -User'
    Write-Host '───'
}

Write-Host ''
Write-Host 'Reload your editor window so the new instructions and config are picked up:'
Write-Host '  - VS Code:     Ctrl+Shift+P -> "Developer: Reload Window"'
Write-Host '  - Claude Code: restart the session'
