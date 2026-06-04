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

    [ValidateSet('workspace', 'skip', '')]
    [string]$Hooks = '',

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
$script:ConflictBulkChoice = ''   # 'K', 'O', 'S', or ''

function Get-Sha256($path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
}

# Manifest action sets — kept here so adding a new action only touches one
# place. RemovableActions are deleted on uninstall; ExcludableActions are
# emitted into .git/info/exclude in trial mode.
$script:RemovableActions  = @('created','unchanged_owned','overwritten','rendered','sidecar')
$script:ExcludableActions = @('created','unchanged_owned','overwritten','merged_hooks_key','merged_settings','rendered','sidecar')
$script:MergedActions     = @('merged_settings','merged_hooks_key')
# Vocabulary of actions allowed in the manifest. Validation in
# Add-ManifestEntry turns silent typos into immediate errors.
$script:KnownActions      = @('created','unchanged_owned','overwritten','rendered','sidecar','merged_settings','merged_hooks_key','pre_install_backup')

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

    # Read current exclude, strip any prior managed block, then append fresh block.
    $existing = Get-Content -LiteralPath $excl -ErrorAction SilentlyContinue
    if ($null -eq $existing) { $existing = @() }
    $kept = Remove-ManagedBlockLines $existing

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
    Remove-ExcludeBlock
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $m.mode = 'committed'
            Write-AtomicFile -Path $manifestPath -Content ($m | ConvertTo-Json -Depth 10)
            Write-Host "Updated ${manifestPath}: mode -> committed"
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
            Write-Host '  - strip the trial-mode block from .git/info/exclude (if any)'
            Write-Host '  - clear hooks/state, hooks/logs, hooks/sessions runtime data'
            if ($User) {
                Write-Host '  - also remove user-scope copies in ~/.assert-iq, ~/.claude, and the user prompts dir'
            }
            Write-Host "  - delete $manifestPath"
            Write-Host ''
            $ans = Read-Host 'Proceed? [y/N]'
            if ($ans -notmatch '^[yY]') { Write-Host 'Aborted.'; exit 1 }
        }
    }

    Remove-ExcludeBlock | Out-Null
    Write-Host ''

    $script:UninstallStats = [pscustomobject]@{
        Removed = 0; Restored = 0; Preserved = 0; Skipped = 0
    }

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
            Copy-Item -LiteralPath $original -Destination "$original.assert-iq.uninstall-saved" -Force -ErrorAction SilentlyContinue
        }
        Copy-Item -LiteralPath $backup -Destination $original -Force
        Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
        $script:UninstallStats.Restored++
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $entries  = @($manifest.paths)

    function Invoke-Entry($e) {
        if ($e.scope -eq 'user' -and -not $User) {
            $script:UninstallStats.Preserved++
            return
        }
        switch ($e.action) {
            'pre_install_backup' { Restore-Backup $e.path }
            { $script:RemovableActions -contains $_ } {
                Remove-PathOrDir $e.path
            }
            { $script:MergedActions -contains $_ } {
                if (Test-Path -LiteralPath ($e.path + '.assert-iq.pre-install') -PathType Leaf) {
                    # Will be restored by the corresponding pre_install_backup entry.
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

    foreach ($d in @(
            (Join-Path $Workspace 'hooks\state'),
            (Join-Path $Workspace 'hooks\logs'),
            (Join-Path $Workspace 'hooks\sessions'))) {
        if (Test-Path -LiteralPath $d) { Remove-PathOrDir $d }
    }
    if ($User) {
        $userHooksRuntime = Join-Path $env:USERPROFILE '.agents\hooks'
        foreach ($d in @(
                (Join-Path $userHooksRuntime 'state'),
                (Join-Path $userHooksRuntime 'logs'),
                (Join-Path $userHooksRuntime 'sessions'))) {
            if (Test-Path -LiteralPath $d) { Remove-PathOrDir $d }
        }
    }

    if (-not $DryRun) {
        # First, clean nested empty subdirectories left by tree-style copies
        # (.github/skills/<skill>/, eval-optimizer/references/, etc.).
        $treeRoots = @(
            (Join-Path $Workspace '.github\skills'),
            (Join-Path $Workspace '.github\agents'),
            (Join-Path $Workspace '.claude\agents'),
            (Join-Path $Workspace 'hooks'))
        if ($User) {
            $treeRoots += @($userVscodeSkills, $userClaudeSkills, $userAssertIq, (Join-Path $env:USERPROFILE '.agents\hooks'))
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
            (Join-Path $Workspace 'hooks'),
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
        $mDir = Split-Path -Parent $manifestPath
        if ((Test-Path -LiteralPath $mDir) -and `
            -not (Get-ChildItem -LiteralPath $mDir -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $mDir -Force -ErrorAction SilentlyContinue
        }
    }

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
        if (-not $Hooks)           { $Hooks           = 'skip' }
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
        if (-not $Hooks)           { $Hooks           = 'workspace' }
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
        Add-ManifestEntry 'created' $Dst $Scope
        Record $Label 'copied' $Dst
        return
    }

    $shSrc = Get-Sha256 $Src
    $shDst = Get-Sha256 $Dst
    if ($shSrc -and ($shSrc -eq $shDst)) {
        Add-ManifestEntry 'unchanged_owned' $Dst $Scope
        Record $Label 'unchanged (pack-owned)' $Dst
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
            Record $Label 'overwritten' $Dst
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
    param([string]$Label, [string]$SrcDir, [string]$DstDir, [string]$Scope)

    if (-not (Test-Path -LiteralPath $SrcDir -PathType Container)) {
        Record $Label 'missing-source' $SrcDir
        return
    }
    Get-ChildItem -LiteralPath $SrcDir -Recurse -File | ForEach-Object {
        # Skip OS/editor cruft.
        if ($_.Name -in @('.DS_Store','Thumbs.db','desktop.ini')) { return }
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

function Get-RenderedHooksJson {
    param([string]$PackRoot)
    $template = Join-Path $Source 'hooks\hooks.template.json'
    if (-not (Test-Path -LiteralPath $template)) { return '' }
    $lib = Join-Path $Source 'hooks\scripts\lib\render-hooks.ps1'
    if (-not (Test-Path -LiteralPath $lib)) { return '' }
    . $lib
    $tmp = [System.IO.Path]::GetTempFileName()
    Render-HooksTemplate -Template $template -Out $tmp -PackRoot $PackRoot
    return $tmp
}

# =============================================================================
# Per-surface handlers
# =============================================================================

function Step-AssertIq {
    switch ($AssertIq) {
        'workspace' { Copy-TreeScoped '.assert-iq' (Join-Path $Source '.assert-iq') (Join-Path $Workspace '.assert-iq') 'workspace' }
        'user'      { Copy-TreeScoped '.assert-iq' (Join-Path $Source '.assert-iq') $userAssertIq 'user' }
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

function Step-Hooks {
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
            Add-ManifestEntry 'created' $sessionsDst 'workspace'
            Record 'hooks/sessions/' 'created' $sessionsDst
            $rendered = Get-RenderedHooksJson -PackRoot $Workspace
            if (-not $rendered) {
                Record 'hooks/hooks.json' 'missing-template' (Join-Path $hooksSrcDir 'hooks.template.json')
            } else {
                Copy-FileScoped 'hooks/hooks.json' $rendered (Join-Path $Workspace 'hooks\hooks.json') 'workspace'
                Remove-Item -LiteralPath $rendered -Force -ErrorAction SilentlyContinue
            }
        }
        'user' {
            # User-global install: pack at $env:USERPROFILE\.agents\hooks\.
            # Hooks fire across every VS Code workspace once registered in
            # USER settings.json (instructions printed at end of run).
            $hooksSrcDir = Join-Path $Source 'hooks'
            if (-not (Test-Path -LiteralPath $hooksSrcDir -PathType Container)) {
                Record 'hooks/ (user)' 'missing-source' $hooksSrcDir
                return
            }
            $userHooksRoot = Join-Path $env:USERPROFILE '.agents\hooks'
            $scriptsSrc = Join-Path $hooksSrcDir 'scripts'
            if (Test-Path -LiteralPath $scriptsSrc) {
                Copy-TreeScoped 'hooks/scripts' $scriptsSrc (Join-Path $userHooksRoot 'scripts') 'user'
            }
            $libSrc = Join-Path $hooksSrcDir 'lib'
            if (Test-Path -LiteralPath $libSrc) {
                Copy-TreeScoped 'hooks/lib' $libSrc (Join-Path $userHooksRoot 'lib') 'user'
            }
            $cfgSrc = Join-Path $hooksSrcDir 'config'
            if (Test-Path -LiteralPath $cfgSrc) {
                Copy-TreeScoped 'hooks/config' $cfgSrc (Join-Path $userHooksRoot 'config') 'user'
            }
            $stateSrc = Join-Path $hooksSrcDir 'state'
            if (Test-Path -LiteralPath $stateSrc) {
                Copy-TreeScoped 'hooks/state' $stateSrc (Join-Path $userHooksRoot 'state') 'user'
            }
            $logsSrc = Join-Path $hooksSrcDir 'logs'
            if (Test-Path -LiteralPath $logsSrc) {
                Copy-TreeScoped 'hooks/logs' $logsSrc (Join-Path $userHooksRoot 'logs') 'user'
            }
            $sessionsDst = Join-Path $userHooksRoot 'sessions'
            New-Item -ItemType Directory -Path $sessionsDst -Force | Out-Null
            Add-ManifestEntry 'created' $sessionsDst 'user'
            Record 'hooks/sessions/ (user)' 'created' $sessionsDst
            # Render hooks.json with __PACK_ROOT__ = $env:USERPROFILE\.agents
            $userPackRoot = Join-Path $env:USERPROFILE '.agents'
            $rendered = Get-RenderedHooksJson -PackRoot $userPackRoot
            if (-not $rendered) {
                Record 'hooks/hooks.json (user)' 'missing-template' (Join-Path $hooksSrcDir 'hooks.template.json')
            } else {
                Copy-FileScoped 'hooks/hooks.json' $rendered (Join-Path $userHooksRoot 'hooks.json') 'user'
                Remove-Item -LiteralPath $rendered -Force -ErrorAction SilentlyContinue
            }
            $Script:UserHooksInstalled = $true
        }
        'skip' { Record 'hooks/' 'skipped (user choice)' '-' }
        default { throw "Invalid -Hooks: '$Hooks' (workspace|user|skip)" }
    }
}

function Step-ClaudeSettings {
    # Merge only the .hooks key into .claude/settings.json; preserve everything
    # else. Copilot side disables this file via chat.hookFilesLocations to
    # avoid double-fire.
    switch ($ClaudeSettings) {
        'workspace' {
            $rendered = Get-RenderedHooksJson -PackRoot $Workspace
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
Step-Hooks
Step-ClaudeSettings
Step-GithubSkills
Step-GithubAgents
Step-ClaudeAgents
Step-ClaudeSkillsLink

# =============================================================================
# Finalize: manifest + git-exclude wiring (trial mode only)
# =============================================================================

Write-Manifest

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

if ($Script:UserHooksInstalled) {
    Write-Host ''
    Write-Host '─── USER-GLOBAL HOOKS INSTALLED ───'
    Write-Host 'Hooks are at ~/.agents/hooks/ and will fire across every VS Code workspace'
    Write-Host 'once you register them in your VS Code USER settings.json.'
    Write-Host ''
    Write-Host '  1. Ctrl+Shift+P -> "Preferences: Open User Settings (JSON)"'
    Write-Host '  2. Add or merge this block:'
    Write-Host ''
    Write-Host '    "chat.hookFilesLocations": {'
    Write-Host '      "~/.agents/hooks/hooks.json": true'
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
