<#
.SYNOPSIS
Assert.IQ bootstrap E2E test driver (PowerShell).
#>
param(
    [switch]$Keep,
    [string]$Pattern = ""
)

$PackDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
. "$PSScriptRoot/aiq-e2e-lib.ps1"

Run-Case "01 pod committed install" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    Assert-FileExists 01 "$ws\.assert-iq\.install-manifest.json"
    Assert-DirExists  01 "$ws\.github\skills"
    Assert-DirExists  01 "$ws\.github\agents"
    Assert-DirExists  01 "$ws\.claude\agents"
    Assert-FileExists 01 "$ws\CLAUDE.md"
    Assert-FileExists 01 "$ws\AGENTS.md"
    Assert-FileExists 01 "$ws\.github\copilot-instructions.md"
    Assert-DirExists  01 "$ws\.github\instructions"
    if (-not (Test-Path "$ws\.claude\skills" -PathType Container)) { Assert-FileExists 01 "$ws\.claude\skills" } # file copy fallback check
    Assert-FileExists 01 "$ws\.claude\settings.json"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "02 pod committed uninstall" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    Invoke-RunBoot $pair @("--uninstall", "--yes") | Out-Null
    Assert-FileMissing 02 "$ws\.assert-iq\.install-manifest.json"
    Assert-DirMissing  02 "$ws\.github\skills"
    Assert-FileMissing 02 "$ws\CLAUDE.md"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "03 pod trial install" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=trial", "--yes") | Out-Null
    Assert-FileExists 03 "$ws\.git\info\exclude"
    Assert-Contains   03 "$ws\.git\info\exclude" "assert-iq trial mode"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "04 trial -> graduate" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=trial", "--yes") | Out-Null
    Invoke-RunBoot $pair @("--graduate") | Out-Null
    Assert-DirExists  04 "$ws\.github\skills"
    # Per-path trial entries should be gone; backup-glob block must remain.
    Assert-NotContains 04 "$ws\.git\info\exclude" ".github/skills"
    Assert-Contains    04 "$ws\.git\info\exclude" "*.assert-iq.pre-install"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "05 trial uninstall (no graduate)" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=trial", "--yes") | Out-Null
    Invoke-RunBoot $pair @("--uninstall", "--yes") | Out-Null
    Assert-DirMissing  05 "$ws\.github\skills"
    Assert-NotContains 05 "$ws\.git\info\exclude" "assert-iq trial mode"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "06 solo install" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws; $homeDir = $pair.home
    Invoke-RunBoot $pair @("--preset=solo", "--mode=committed", "--yes") | Out-Null
    Assert-DirExists  06 "$ws\.github\skills"
    Assert-FileExists 06 "$homeDir\.claude\CLAUDE.md"
    Assert-FileMissing 06 "$ws\CLAUDE.md"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "07 solo uninstall --user" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws; $homeDir = $pair.home
    Invoke-RunBoot $pair @("--preset=solo", "--mode=committed", "--yes") | Out-Null
    Invoke-RunBoot $pair @("--uninstall", "--user", "--yes") | Out-Null
    Assert-FileMissing 07 "$homeDir\.claude\CLAUDE.md"
    Assert-DirMissing  07 "$ws\.github\skills"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "08 solo uninstall (no --user)" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws; $homeDir = $pair.home
    Invoke-RunBoot $pair @("--preset=solo", "--mode=committed", "--yes") | Out-Null
    Invoke-RunBoot $pair @("--uninstall", "--yes") | Out-Null
    Assert-DirMissing  08 "$ws\.github\skills"
    Assert-FileExists  08 "$homeDir\.claude\CLAUDE.md"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "09 portable install" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws; $homeDir = $pair.home
    Invoke-RunBoot $pair @("--preset=portable", "--mode=committed", "--yes") | Out-Null
    Assert-DirExists  09 "$homeDir\.agents\skills"
    Assert-DirMissing 09 "$ws\.github\skills"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "10 portable uninstall --user" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws; $homeDir = $pair.home
    Invoke-RunBoot $pair @("--preset=portable", "--mode=committed", "--yes") | Out-Null
    Invoke-RunBoot $pair @("--uninstall", "--user", "--yes") | Out-Null
    Assert-DirMissing  10 "$homeDir\.agents\skills"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "11 skills-scope=both install" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws; $homeDir = $pair.home
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--skills-scope=both", "--yes") | Out-Null
    Assert-DirExists 11 "$ws\.github\skills"
    Assert-DirExists 11 "$homeDir\.agents\skills"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "12 skills-scope=both uninstall --user" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws; $homeDir = $pair.home
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--skills-scope=both", "--yes") | Out-Null
    Invoke-RunBoot $pair @("--uninstall", "--user", "--yes") | Out-Null
    Assert-DirMissing 12 "$ws\.github\skills"
    Assert-DirMissing 12 "$homeDir\.agents\skills"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "13 skills-scope=user install" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws; $homeDir = $pair.home
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--skills-scope=user", "--yes") | Out-Null
    Assert-DirExists  13 "$homeDir\.agents\skills"
    Assert-DirMissing 13 "$ws\.github\skills"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "14 skills-scope=user uninstall --user" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws; $homeDir = $pair.home
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--skills-scope=user", "--yes") | Out-Null
    Invoke-RunBoot $pair @("--uninstall", "--user", "--yes") | Out-Null
    Assert-DirMissing 14 "$homeDir\.agents\skills"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "15 dry-run uninstall" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    Invoke-RunBoot $pair @("--uninstall", "--dry-run", "--yes") | Out-Null
    Assert-FileExists 15 "$ws\.assert-iq\.install-manifest.json"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "16 ask-mode no-TTY -> committed" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=ask", "--yes") | Out-Null
    Assert-FileExists 16 "$ws\.assert-iq\.install-manifest.json"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "17 invalid preset rejected" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    $rc = Invoke-RunBoot $pair @("--preset=bogus", "--yes")
    if ($rc -eq 0) { Fail 17 "expected non-zero exit; got 0" }
    Assert-FileMissing 17 "$ws\.assert-iq\.install-manifest.json"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "18 invalid skills-scope rejected" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    $rc = Invoke-RunBoot $pair @("--preset=pod", "--skills-scope=bogus", "--yes")
    if ($rc -eq 0) { Fail 18 "expected non-zero exit; got 0" }
    Assert-FileMissing 18 "$ws\.assert-iq\.install-manifest.json"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "19 idempotent reinstall" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    Assert-FileExists 19 "$ws\.assert-iq\.install-manifest.json"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "20 conflict creates pre-install backup" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Set-Content -Path "$ws\CLAUDE.md" -Value "user content 123"
    $env:CONFLICT_BULK_CHOICE = "O"
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    $env:CONFLICT_BULK_CHOICE = $null
    Assert-FileExists 20 "$ws\CLAUDE.md.assert-iq.pre-install"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "21 uninstall restores backup" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Set-Content -Path "$ws\CLAUDE.md" -Value "user content 456"
    $env:CONFLICT_BULK_CHOICE = "O"
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    $env:CONFLICT_BULK_CHOICE = $null
    Invoke-RunBoot $pair @("--uninstall", "--yes") | Out-Null
    Assert-Contains 21 "$ws\CLAUDE.md" "user content 456"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "22 install.ps1 install + reinstall" $Pattern {
    $pair = Invoke-MkPackCopy
    $copy = $pair.copy; $homeDir = $pair.home
    $origHome = $env:HOME; $origProfile = $env:USERPROFILE
    $env:HOME = $homeDir; $env:USERPROFILE = $homeDir
    try {
        & pwsh -NoProfile -File "$copy\install.ps1" *>&1 | Out-Null
        Assert-FileExists 22 "$copy\.claude\settings.json"
        & pwsh -NoProfile -File "$copy\install.ps1" *>&1 | Out-Null
    } finally {
        $env:HOME = $origHome; $env:USERPROFILE = $origProfile
    }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "23 install.ps1 preserves user keys" $Pattern {
    $pair = Invoke-MkPackCopy
    $copy = $pair.copy; $homeDir = $pair.home
    $origHome = $env:HOME; $origProfile = $env:USERPROFILE
    $env:HOME = $homeDir; $env:USERPROFILE = $homeDir
    try {
        New-Item -ItemType Directory -Path "$copy\.claude" -Force | Out-Null
        Set-Content -Path "$copy\.claude\settings.json" -Value '{ "userKey": "preserve-me" }'
        & pwsh -NoProfile -File "$copy\install.ps1" *>&1 | Out-Null
        Assert-Contains 23 "$copy\.claude\settings.json" "preserve-me"
        & pwsh -NoProfile -File "$copy\install.ps1" -Uninstall *>&1 | Out-Null
        Assert-Contains 23 "$copy\.claude\settings.json" "preserve-me"
    } finally {
        $env:HOME = $origHome; $env:USERPROFILE = $origProfile
    }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "24 markdown merge fresh" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    New-Item -ItemType Directory -Path "$ws\.github" -Force | Out-Null
    Set-Content -Path "$ws\.github\copilot-instructions.md" -Value "# Team rules`n- 4-space indent"
    $env:CONFLICT_BULK_CHOICE = "M"
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    $env:CONFLICT_BULK_CHOICE = $null
    Assert-FileExists 24 "$ws\.github\copilot-instructions.md"
    Assert-Contains   24 "$ws\.github\copilot-instructions.md" "<!-- assert-iq:begin"
    Assert-Contains   24 "$ws\.github\copilot-instructions.md" "<!-- assert-iq:end -->"
    Assert-Contains   24 "$ws\.github\copilot-instructions.md" "# Team rules"
    Assert-Contains   24 "$ws\.github\copilot-instructions.md" "4-space indent"
    Assert-FileExists 24 "$ws\.github\copilot-instructions.md.assert-iq.pre-install"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "25 markdown merge idempotent" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    New-Item -ItemType Directory -Path "$ws\.github" -Force | Out-Null
    Set-Content -Path "$ws\.github\copilot-instructions.md" -Value "# Team rules`n- 4-space indent"
    $env:CONFLICT_BULK_CHOICE = "M"
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    $first = (Get-FileHash "$ws\.github\copilot-instructions.md" -Algorithm SHA256).Hash
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    $env:CONFLICT_BULK_CHOICE = $null
    $second = (Get-FileHash "$ws\.github\copilot-instructions.md" -Algorithm SHA256).Hash
    if ($first -ne $second) { Fail 25 "merge not idempotent ($first vs $second)" }
    $matches = Select-String -Path "$ws\.github\copilot-instructions.md" -Pattern '<!-- assert-iq:begin' -AllMatches
    $count = if ($matches) { @($matches).Count } else { 0 }
    if ($count -ne 1) { Fail 25 "expected 1 begin marker, found $count" }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "26 markdown merge uninstall round-trip" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    New-Item -ItemType Directory -Path "$ws\.github" -Force | Out-Null
    Set-Content -Path "$ws\.github\copilot-instructions.md" -Value "# Team rules`n- 4-space indent"
    $userSha = (Get-FileHash "$ws\.github\copilot-instructions.md" -Algorithm SHA256).Hash
    $env:CONFLICT_BULK_CHOICE = "M"
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    $env:CONFLICT_BULK_CHOICE = $null
    Invoke-RunBoot $pair @("--uninstall", "--yes") | Out-Null
    Assert-FileExists 26 "$ws\.github\copilot-instructions.md"
    $restoredSha = (Get-FileHash "$ws\.github\copilot-instructions.md" -Algorithm SHA256).Hash
    if ($restoredSha -ne $userSha) { Fail 26 "round-trip sha mismatch ($restoredSha vs $userSha)" }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "27 merge allowlist isolation (JSON)" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    New-Item -ItemType Directory -Path "$ws\.claude" -Force | Out-Null
    Set-Content -Path "$ws\.claude\settings.json" -Value '{ "userKeyZ": "keep-me" }'
    $env:CONFLICT_BULK_CHOICE = "M"
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    $env:CONFLICT_BULK_CHOICE = $null
    Assert-FileExists    27 "$ws\.claude\settings.json"
    Assert-Contains      27 "$ws\.claude\settings.json" "keep-me"
    Assert-NotContains   27 "$ws\.claude\settings.json" "<!-- assert-iq:begin"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "28 committed excludes backup-globs" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    New-Item -ItemType Directory -Path "$ws\.github" -Force | Out-Null
    Set-Content -Path "$ws\.github\copilot-instructions.md" -Value "# Team rules`n"
    $env:CONFLICT_BULK_CHOICE = "M"
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    $env:CONFLICT_BULK_CHOICE = $null
    Assert-FileExists 28 "$ws\.git\info\exclude"
    Assert-Contains   28 "$ws\.git\info\exclude" "*.assert-iq.pre-install"
    Assert-Contains   28 "$ws\.git\info\exclude" "*.assert-iq.uninstall-saved"
    Assert-FileExists 28 "$ws\.github\copilot-instructions.md.assert-iq.pre-install"
    Push-Location $ws
    try {
        git check-ignore --no-index --quiet ".github/copilot-instructions.md.assert-iq.pre-install"
        if ($LASTEXITCODE -ne 0) { Fail 28 "backup file not git-ignored despite exclude entry" }
    } finally { Pop-Location }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "29 trial skip-worktree on tracked merge" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    New-Item -ItemType Directory -Path "$ws\.github" -Force | Out-Null
    Set-Content -Path "$ws\.github\copilot-instructions.md" -Value "# Team rules`n"
    Push-Location $ws
    try {
        git add .github/copilot-instructions.md | Out-Null
        git commit -q -m seed | Out-Null
    } finally { Pop-Location }
    $env:CONFLICT_BULK_CHOICE = "M"
    Invoke-RunBoot $pair @("--preset=pod", "--mode=trial", "--yes") | Out-Null
    $env:CONFLICT_BULK_CHOICE = $null
    Assert-Contains 29 "$ws\.github\copilot-instructions.md" "<!-- assert-iq:begin"
    Push-Location $ws
    try {
        $porcelain = git status --porcelain -- .github/copilot-instructions.md
        if ($porcelain) { Fail 29 "git status not silent for skip-worktree path: $porcelain" }
        $idx = git ls-files -v -- .github/copilot-instructions.md
        if (-not ($idx -match '^S ')) { Fail 29 "expected --skip-worktree flag (S) on tracked merge target" }
    } finally { Pop-Location }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "30 uninstall clears skip-worktree+backups" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    New-Item -ItemType Directory -Path "$ws\.github" -Force | Out-Null
    Set-Content -Path "$ws\.github\copilot-instructions.md" -Value "# Team rules`n"
    $seedSha = (Get-FileHash "$ws\.github\copilot-instructions.md" -Algorithm SHA256).Hash
    Push-Location $ws
    try {
        git add .github/copilot-instructions.md | Out-Null
        git commit -q -m seed | Out-Null
    } finally { Pop-Location }
    $env:CONFLICT_BULK_CHOICE = "M"
    Invoke-RunBoot $pair @("--preset=pod", "--mode=trial", "--yes") | Out-Null
    $env:CONFLICT_BULK_CHOICE = $null
    Invoke-RunBoot $pair @("--uninstall", "--yes") | Out-Null
    Assert-FileExists 30 "$ws\.github\copilot-instructions.md"
    $restoredSha = (Get-FileHash "$ws\.github\copilot-instructions.md" -Algorithm SHA256).Hash
    if ($restoredSha -ne $seedSha) { Fail 30 "restored sha differs from seed" }
    Assert-FileMissing 30 "$ws\.github\copilot-instructions.md.assert-iq.pre-install"
    Push-Location $ws
    try {
        $flagged = git ls-files -v 2>$null | Where-Object { $_ -match '^S ' }
        if ($flagged) { Fail 30 "leftover --skip-worktree flag after uninstall" }
        $porcelain = git status --porcelain
        if ($porcelain) { Fail 30 "git status not clean after uninstall: $porcelain" }
    } finally { Pop-Location }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "31 preserves unrelated skip-worktree" $Pattern {
    # Regression: uninstall must NOT clear --skip-worktree flags the user set
    # on unrelated paths before the bootstrap ever ran.
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Set-Content -Path "$ws\tasks.json" -Value '{}'
    Push-Location $ws
    try {
        git add tasks.json | Out-Null
        git commit -q -m seed-tasks | Out-Null
        git update-index --skip-worktree -- tasks.json | Out-Null
        $idx = git ls-files -v -- tasks.json
        if (-not ($idx -match '^S ')) { Fail 31 "test setup: failed to set pre-existing --skip-worktree on tasks.json" }
    } finally { Pop-Location }
    $seedSha = (Get-FileHash "$ws\tasks.json" -Algorithm SHA256).Hash
    Invoke-RunBoot $pair @("--preset=pod", "--mode=trial", "--yes") | Out-Null
    Invoke-RunBoot $pair @("--uninstall", "--yes") | Out-Null
    Push-Location $ws
    try {
        $idx = git ls-files -v -- tasks.json
        if (-not ($idx -match '^S ')) { Fail 31 "uninstall cleared user's pre-existing --skip-worktree on tasks.json" }
    } finally { Pop-Location }
    $finalSha = (Get-FileHash "$ws\tasks.json" -Algorithm SHA256).Hash
    if ($finalSha -ne $seedSha) { Fail 31 "tasks.json content changed during install/uninstall" }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "32 install respects existing skip-worktree" $Pattern {
    # Regression: install must NOT re-mark a path that was already
    # --skip-worktree before the bootstrap ran. Uninstall must not
    # clear that pre-existing flag either.
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    New-Item -ItemType Directory -Path "$ws\.github" -Force | Out-Null
    Set-Content -Path "$ws\.github\copilot-instructions.md" -Value "# Team rules`n"
    Push-Location $ws
    try {
        git add .github/copilot-instructions.md | Out-Null
        git commit -q -m seed | Out-Null
        git update-index --skip-worktree -- .github/copilot-instructions.md | Out-Null
    } finally { Pop-Location }
    $env:CONFLICT_BULK_CHOICE = "M"
    Invoke-RunBoot $pair @("--preset=pod", "--mode=trial", "--yes") | Out-Null
    $env:CONFLICT_BULK_CHOICE = $null
    $sidecar = "$ws\.assert-iq\.skip-worktree-paths"
    if (Test-Path -LiteralPath $sidecar) {
        $rels = Get-Content -LiteralPath $sidecar -ErrorAction SilentlyContinue
        if ($rels -contains ".github/copilot-instructions.md") {
            Fail 32 "install claimed pre-existing user flag in sidecar"
        }
    }
    Invoke-RunBoot $pair @("--uninstall", "--yes") | Out-Null
    Push-Location $ws
    try {
        $idx = git ls-files -v -- .github/copilot-instructions.md
        if (-not ($idx -match '^S ')) { Fail 32 "uninstall cleared pre-existing user --skip-worktree on tracked merge target" }
    } finally { Pop-Location }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "33 json merge clean roundtrip no .uninstall-saved" $Pattern {
    # Regression: when a JSON additive merge target is unedited between
    # install and uninstall, no .uninstall-saved artifact is left behind.
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    New-Item -ItemType Directory -Path "$ws\.claude" -Force | Out-Null
    Set-Content -Path "$ws\.claude\settings.json" -Value '{ "userKey": "preserve-me" }'
    $env:CONFLICT_BULK_CHOICE = "M"
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    $env:CONFLICT_BULK_CHOICE = $null
    Assert-Contains 33 "$ws\.claude\settings.json" '"hooks"'
    Assert-FileExists 33 "$ws\.assert-iq\.merge-result-shas"
    $shaSidecar = Get-Content -LiteralPath "$ws\.assert-iq\.merge-result-shas" -Raw
    if ($shaSidecar -notmatch '\.claude[\\/]settings\.json') {
        Fail 33 "merge-result-shas sidecar missing entry for .claude/settings.json"
    }
    Invoke-RunBoot $pair @("--uninstall", "--yes") | Out-Null
    Assert-FileExists  33 "$ws\.claude\settings.json"
    Assert-FileMissing 33 "$ws\.claude\settings.json.assert-iq.uninstall-saved"
    Assert-Contains    33 "$ws\.claude\settings.json" '"userKey"'
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "34 install state sidecars hidden from git" $Pattern {
    # Always-on contract: the .assert-iq install-state sidecars
    # (.skip-worktree-paths, .merge-result-shas) are local install
    # bookkeeping and must never appear in git status, in any mode.
    # --- trial mode ---
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    New-Item -ItemType Directory -Path "$ws\.github" -Force | Out-Null
    Set-Content -Path "$ws\.github\copilot-instructions.md" -Value "# Team rules`n"
    Push-Location $ws
    try {
        git add .github/copilot-instructions.md | Out-Null
        git commit -q -m seed | Out-Null
    } finally { Pop-Location }
    $env:CONFLICT_BULK_CHOICE = "M"
    Invoke-RunBoot $pair @("--preset=pod", "--mode=trial", "--yes") | Out-Null
    $env:CONFLICT_BULK_CHOICE = $null
    Assert-FileExists 34 "$ws\.assert-iq\.merge-result-shas"
    Push-Location $ws
    try {
        git check-ignore --no-index --quiet ".assert-iq/.merge-result-shas"
        if ($LASTEXITCODE -ne 0) { Fail 34 "trial: .assert-iq/.merge-result-shas not git-ignored" }
        if (Test-Path -LiteralPath "$ws\.assert-iq\.skip-worktree-paths") {
            git check-ignore --no-index --quiet ".assert-iq/.skip-worktree-paths"
            if ($LASTEXITCODE -ne 0) { Fail 34 "trial: .assert-iq/.skip-worktree-paths not git-ignored" }
        }
        $porcelain = git status --porcelain
        if ($porcelain -match '\.assert-iq[\\/]\.skip-worktree-paths') { Fail 34 "trial: .skip-worktree-paths leaked into git status" }
        if ($porcelain -match '\.assert-iq[\\/]\.merge-result-shas')   { Fail 34 "trial: .merge-result-shas leaked into git status" }
    } finally { Pop-Location }
    Invoke-CleanupFixture $pair $Keep
    # --- committed mode ---
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    New-Item -ItemType Directory -Path "$ws\.claude" -Force | Out-Null
    Set-Content -Path "$ws\.claude\settings.json" -Value '{ "userKey": "preserve-me" }'
    $env:CONFLICT_BULK_CHOICE = "M"
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    $env:CONFLICT_BULK_CHOICE = $null
    Assert-FileExists 34 "$ws\.assert-iq\.merge-result-shas"
    Push-Location $ws
    try {
        git check-ignore --no-index --quiet ".assert-iq/.merge-result-shas"
        if ($LASTEXITCODE -ne 0) { Fail 34 "committed: .assert-iq/.merge-result-shas not git-ignored" }
        $porcelain = git status --porcelain
        if ($porcelain -match '\.assert-iq[\\/]\.skip-worktree-paths') { Fail 34 "committed: .skip-worktree-paths leaked into git status" }
        if ($porcelain -match '\.assert-iq[\\/]\.merge-result-shas')   { Fail 34 "committed: .merge-result-shas leaked into git status" }
    } finally { Pop-Location }
    Invoke-CleanupFixture $pair $Keep
}

echo "`nSummary: $($global:CASES_PASS) pass, $($global:CASES_FAIL) fail"
if ($global:CASES_FAIL -gt 0) {
    echo "Failures:"
    $global:FAIL_LOG | ForEach-Object { Write-Red $_ }
    exit 1
}
