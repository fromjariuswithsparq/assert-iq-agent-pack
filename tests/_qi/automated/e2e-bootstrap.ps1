<#
.SYNOPSIS
Assert.IQ bootstrap E2E test driver (PowerShell).
#>
param(
    [switch]$Keep,
    [string]$Pattern = ""
)
# $AiqPwsh (the PowerShell host used to spawn child processes) comes from
# aiq-e2e-lib.ps1, dot-sourced below.

$PackDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
. "$PSScriptRoot/aiq-e2e-lib.ps1"

# Always report the host. Windows PowerShell 5.1 and PowerShell 7 are DIFFERENT
# runtimes with different failure modes -- 5.1 is .NET Framework (no
# ProcessStartInfo.ArgumentList) and turns native stderr into terminating errors
# -- and both are supported hosts for this pack. A green run under 7 says
# nothing about 5.1, and the trial-mode exclude bug proved that the hard way.
# Run this suite under BOTH on Windows.
Write-Host ""
Write-Host ("Host: {0} {1} ({2})" -f `
    $(if ($PSVersionTable.PSVersion.Major -ge 6) { 'PowerShell' } else { 'Windows PowerShell' }), `
    $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)

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
        & $AiqPwsh -NoProfile -File "$copy\install.ps1" *>&1 | Out-Null
        Assert-FileExists 22 "$copy\.claude\settings.json"
        & $AiqPwsh -NoProfile -File "$copy\install.ps1" *>&1 | Out-Null
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
        & $AiqPwsh -NoProfile -File "$copy\install.ps1" *>&1 | Out-Null
        Assert-Contains 23 "$copy\.claude\settings.json" "preserve-me"
        & $AiqPwsh -NoProfile -File "$copy\install.ps1" -Uninstall *>&1 | Out-Null
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

Run-Case "35 clean-slate memory seed (no logs)" $Pattern {
    # Fresh install must seed Dreaming memory clean: no bogus conflict, no pack
    # dream data shipped, and session-events.json rendered (no placeholder left).
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    $out = Get-LastBootOutput
    if ($out -match '(?i)conflict') { Fail 35 "fresh install reported a conflict" }
    Assert-FileMissing 35 "$ws\.assert-iq\dreaming\session-events.json.assert-iq-new"
    Assert-FileExists  35 "$ws\.assert-iq\memory\MEMORY.md"
    Assert-Contains    35 "$ws\.assert-iq\memory\MEMORY.md" "Last consolidated: never"
    if (Get-ChildItem -LiteralPath "$ws\.assert-iq\memory\logs" -Recurse -Filter '2*' -ErrorAction SilentlyContinue) {
        Fail 35 "dream logs copied on install"
    }
    if (Get-ChildItem -LiteralPath "$ws\.assert-iq\memory\topics" -Recurse -Filter '*.md' -ErrorAction SilentlyContinue) {
        Fail 35 "topic files copied on install"
    }
    Assert-Contains    35 "$ws\.assert-iq\memory\.dream\state.json" '"sessions_since_dream": 0'
    Assert-FileExists  35 "$ws\.assert-iq\dreaming\session-events.json"
    Assert-NotContains 35 "$ws\.assert-iq\dreaming\session-events.json" "__PACK_ROOT__"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "36 uninstall preserves dreamed memory" $Pattern {
    # Uninstall must never delete the user's dreamed memory -- that is their data.
    #
    # The trigger is CONSOLIDATED KNOWLEDGE, not activity. This case used to
    # seed only a session log under logs/ and assert the store survived, which
    # encoded the wrong rule: logs/ is the waking-loop trail that /dream
    # CONSUMES, so its presence says a session happened, not that anything was
    # learned. Once the session hooks actually started firing that made every
    # install -> chat -> uninstall leave an empty memory store behind (case 43).
    # A real topics/*.md is the signal, and the un-consolidated logs ride along
    # with it -- they are context for the facts.
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    New-Item -ItemType Directory -Force -Path "$ws\.assert-iq\memory\logs\2026\08" | Out-Null
    Set-Content -LiteralPath "$ws\.assert-iq\memory\logs\2026\08\2026-08-01.md" -Value "- session ended"
    Set-Content -LiteralPath "$ws\.assert-iq\memory\topics\architecture.md" `
                -Value "# Architecture`n`n- Payments run through Stripe, 2026-08-01"
    Invoke-RunBoot $pair @("--uninstall", "--yes") | Out-Null
    Assert-FileExists 36 "$ws\.assert-iq\memory\MEMORY.md"
    Assert-FileExists 36 "$ws\.assert-iq\memory\topics\architecture.md"
    Assert-FileExists 36 "$ws\.assert-iq\memory\logs\2026\08\2026-08-01.md"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "37 upgrade merge + conflict + orphan" $Pattern {
    # End-to-end -Upgrade: clean three-way merge (non-overlapping edits both
    # survive), overlapping edit -> sidecar with the user's copy kept, a file
    # removed upstream -> reported as an orphan but NOT deleted under -Yes,
    # memory untouched, manifest version bumped.
    $src = Invoke-MkSource -Tagged
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    try {
        Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes", "--source=$src") | Out-Null

        $skills = @(Get-SkillFiles $ws 3)
        if ($skills.Count -lt 3) { Fail 37 "need 3 SKILL.md files, found $($skills.Count)"; return }
        $target = $skills[0]; $conflict = $skills[1]; $orphan = $skills[2]

        # User edits: non-overlapping (append) on target, overlapping (line 1) on conflict.
        Add-UserEdit "$ws\$target" "<!-- USER-LOCAL-EDIT -->"
        Set-FirstLine "$ws\$conflict" "# WS-EDIT L1"

        # Advance the SOURCE working tree; the v-tag stays the install baseline.
        $newver = "99.0.0"
        Set-Content -LiteralPath "$src\VERSION" -Value $newver
        Add-PackEdit "$src\$target" "<!-- PACK-UPDATE -->"
        Set-FirstLine "$src\$conflict" "# PACK-EDIT L1"
        Remove-Item -LiteralPath "$src\$orphan" -Force

        Invoke-RunBoot $pair @("--upgrade", "--yes", "--source=$src") | Out-Null
        $out = Get-LastBootOutput

        Assert-Contains     37 "$ws\$target" "USER-LOCAL-EDIT"
        Assert-Contains     37 "$ws\$target" "PACK-UPDATE"
        Assert-FileMissing  37 "$ws\$target.assert-iq-new"
        Assert-Contains     37 "$ws\$conflict" "WS-EDIT L1"
        Assert-FileExists   37 "$ws\$conflict.assert-iq-new"
        if ($out -notmatch 'orphan from a previous version') { Fail 37 "orphan not reported" }
        Assert-FileExists   37 "$ws\$orphan"
        Assert-Contains     37 "$ws\.assert-iq\memory\MEMORY.md" "Last consolidated: never"
        if (Get-ChildItem -LiteralPath "$ws\.assert-iq\memory\logs" -Recurse -Filter '2*' -ErrorAction SilentlyContinue) {
            Fail 37 "logs appeared on upgrade"
        }
        Assert-JsonField    37 "$ws\.assert-iq\.install-manifest.json" "version" $newver
    } finally {
        Remove-Item -LiteralPath $src -Recurse -Force -ErrorAction SilentlyContinue
        Invoke-CleanupFixture $pair $Keep
    }
}

Run-Case "38 upgrade base cache (tagless)" $Pattern {
    # The install-time base cache must let an upgrade line-merge even when the
    # source repo has NO version tag to reconstruct a baseline from.
    $src = Invoke-MkSource            # deliberately untagged
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    try {
        Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes", "--source=$src") | Out-Null
        Assert-DirExists 38 "$ws\.assert-iq\.base"
        $skills = @(Get-SkillFiles $ws 1)
        if ($skills.Count -lt 1) { Fail 38 "no SKILL.md found"; return }
        $target = $skills[0]
        Add-UserEdit "$ws\$target" "<!-- USER-LOCAL-EDIT -->"
        Set-Content -LiteralPath "$src\VERSION" -Value "99.0.0"
        Add-PackEdit "$src\$target" "<!-- PACK-UPDATE -->"
        Invoke-RunBoot $pair @("--upgrade", "--yes", "--source=$src") | Out-Null
        Assert-Contains    38 "$ws\$target" "USER-LOCAL-EDIT"
        Assert-Contains    38 "$ws\$target" "PACK-UPDATE"
        Assert-FileMissing 38 "$ws\$target.assert-iq-new"
    } finally {
        Remove-Item -LiteralPath $src -Recurse -Force -ErrorAction SilentlyContinue
        Invoke-CleanupFixture $pair $Keep
    }
}

Run-Case "39 upgrade tag fallback (retroactive)" $Pattern {
    # An older install with NO base cache must still line-merge by rebuilding the
    # baseline from the pack's git tag for the recorded version, and re-seed the
    # cache for next time.
    $src = Invoke-MkSource -Tagged
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    try {
        Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes", "--source=$src") | Out-Null
        Remove-Item -LiteralPath "$ws\.assert-iq\.base" -Recurse -Force -ErrorAction SilentlyContinue
        $skills = @(Get-SkillFiles $ws 1)
        if ($skills.Count -lt 1) { Fail 39 "no SKILL.md found"; return }
        $target = $skills[0]
        Add-UserEdit "$ws\$target" "<!-- USER-LOCAL-EDIT -->"
        Set-Content -LiteralPath "$src\VERSION" -Value "99.0.0"
        Add-PackEdit "$src\$target" "<!-- PACK-UPDATE -->"
        Invoke-RunBoot $pair @("--upgrade", "--yes", "--source=$src") | Out-Null
        Assert-Contains    39 "$ws\$target" "USER-LOCAL-EDIT"
        Assert-Contains    39 "$ws\$target" "PACK-UPDATE"
        Assert-FileMissing 39 "$ws\$target.assert-iq-new"
        Assert-DirExists   39 "$ws\.assert-iq\.base"
    } finally {
        Remove-Item -LiteralPath $src -Recurse -Force -ErrorAction SilentlyContinue
        Invoke-CleanupFixture $pair $Keep
    }
}

Run-Case "40 install.ps1 uninstall round-trip" $Pattern {
    # install.ps1 -Uninstall was never covered: cases 22/23 only exercise
    # install, reinstall and key preservation. Its documented contract is that it
    # reverses the pack's own wiring while preserving (a) any OTHER keys the user
    # has in .claude\settings.json and (b) the .assert-iq\memory\ store, which is
    # the user's dreamed data.
    $pair = Invoke-MkPackCopy
    $copy = $pair.copy; $homeDir = $pair.home
    $origHome = $env:HOME; $origProfile = $env:USERPROFILE
    $env:HOME = $homeDir; $env:USERPROFILE = $homeDir
    try {
        & $AiqPwsh -NoProfile -File "$copy\install.ps1" *>&1 | Out-Null
        Assert-FileExists 40 "$copy\.claude\settings.json"
        Assert-FileExists 40 "$copy\.assert-iq\dreaming\session-events.json"

        # A user key that uninstall must NOT take with it, plus dreamed memory.
        $sp = Join-Path $copy '.claude\settings.json'
        $j = Get-Content -Raw -LiteralPath $sp | ConvertFrom-Json
        $j | Add-Member -NotePropertyName 'permissions' -NotePropertyValue ([pscustomobject]@{ allow = @('Bash(ls)') }) -Force
        Set-Content -LiteralPath $sp -Value ($j | ConvertTo-Json -Depth 32)
        New-Item -ItemType Directory -Force -Path "$copy\.assert-iq\memory\logs\2026\08" | Out-Null
        Set-Content -LiteralPath "$copy\.assert-iq\memory\logs\2026\08\2026-08-01.md" -Value "# dreamt"

        & $AiqPwsh -NoProfile -File "$copy\install.ps1" -Uninstall *>&1 | Out-Null

        # Pack-owned wiring is gone.
        Assert-FileMissing 40 "$copy\.assert-iq\dreaming\session-events.json"
        if (Test-Path -LiteralPath "$copy\.claude\skills") { Fail 40 ".claude\skills survived uninstall" }
        # The user's own settings key survived, and the hooks key did not.
        if (Test-Path -LiteralPath $sp) {
            $after = Get-Content -Raw -LiteralPath $sp | ConvertFrom-Json
            if (-not $after.PSObject.Properties['permissions']) { Fail 40 "uninstall dropped the user's 'permissions' key" }
            if ($after.PSObject.Properties['hooks'])            { Fail 40 "uninstall left the pack's 'hooks' key behind" }
        }
        # Dreamed memory is the user's data and must survive.
        Assert-FileExists 40 "$copy\.assert-iq\memory\logs\2026\08\2026-08-01.md"
    } finally {
        $env:HOME = $origHome; $env:USERPROFILE = $origProfile
    }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "41 uninstall leaves zero orphans" $Pattern {
    # Regression: business-metrics/reports/ and verdicts/archive/ were both
    # left behind after every uninstall. They are created by the seed step as
    # empty runtime sinks, so they never enter the manifest, and the cleanup
    # lists in bootstrap.ps1 had never been updated for them -- the PowerShell
    # lists had also drifted from bootstrap.sh's (missing verdicts, oracles,
    # analysis and tests/_qi/regression).
    #
    # Deliberately generic: assert the workspace is EMPTY apart from .git
    # rather than naming the two known offenders, so the next runtime sink
    # somebody adds is caught here automatically instead of shipping as litter.
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    Assert-DirExists 41 "$ws\.assert-iq\verdicts\archive"
    Assert-DirExists 41 "$ws\.assert-iq\business-metrics\reports"
    Invoke-RunBoot $pair @("--uninstall", "--yes") | Out-Null
    $orphans = @(Get-ChildItem -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -notmatch '\\\.git($|\\)' } |
                 ForEach-Object { $_.FullName.Substring($ws.Length + 1) })
    if ($orphans.Count -gt 0) {
        Fail 41 ("uninstall left " + $orphans.Count + " orphan path(s): " + ($orphans -join ', '))
    }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "42 uninstall preserves runtime sink content" $Pattern {
    # The other half of case 41, and the reason it cannot simply rm -rf the
    # sinks: once they hold real content they are the user's data. The verdict
    # archive is a regulatory audit trail (SOX / ISO 27001 / FedRAMP) whose
    # whole purpose is reproducing a past release decision, so deleting it on
    # uninstall would be worse than leaving an empty directory behind. Same
    # policy the memory store already gets in case 36.
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    New-Item -ItemType Directory -Force -Path "$ws\.assert-iq\verdicts\archive\2026\08" | Out-Null
    Set-Content -LiteralPath "$ws\.assert-iq\verdicts\archive\2026\08\verdicts-26.jsonl" `
                -Value '{"verdict_id":"probe","verdict_band":"green"}'
    Set-Content -LiteralPath "$ws\.assert-iq\business-metrics\reports\2026-Q3.html" `
                -Value '<html>Q3</html>'
    Invoke-RunBoot $pair @("--uninstall", "--yes") | Out-Null
    Assert-FileExists 42 "$ws\.assert-iq\verdicts\archive\2026\08\verdicts-26.jsonl"
    Assert-FileExists 42 "$ws\.assert-iq\business-metrics\reports\2026-Q3.html"
    # And it must say so, rather than preserving them silently.
    $out = Get-LastBootOutput
    if ($out -notmatch 'Preserved your verdict archive') {
        Fail 42 "uninstall preserved the verdict archive without reporting it"
    }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "43 uninstall removes un-consolidated memory" $Pattern {
    # Reported from the field: after the session hooks were fixed, every
    # uninstall left .assert-iq/memory/ behind. The store looked "used" -- a
    # dated session log, and a "_Last consolidated:_" stamp from a /dream that
    # ran -- but it held nothing: topics/ was empty and MEMORY.md read
    # "_(no entries yet)_" under every heading. Preserving it left an orphan
    # directory tree containing none of the user's knowledge.
    #
    # Activity is not knowledge. This asserts the store goes when it holds no
    # consolidated facts, even though a dream ran and logs exist; case 36 is
    # the other side, where one real topics/*.md keeps the whole store.
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes") | Out-Null
    $mem = "$ws\.assert-iq\memory"
    New-Item -ItemType Directory -Force -Path "$mem\logs\2026\08" | Out-Null
    Set-Content -LiteralPath "$mem\logs\2026\08\2026-08-27.md" `
                -Value "# Daily log 2026-08-27`n`n- 2026-08-27T00:33:00Z session abc ended"
    # A dream ran and found nothing: stamp present, index still all placeholders.
    Set-Content -LiteralPath "$mem\.dream\state.json" `
                -Value '{ "last_dream_utc": "2026-08-27T00:37:23Z", "sessions_since_dream": 1 }'
    $idx = Get-Content -Raw -LiteralPath "$mem\MEMORY.md"
    Set-Content -LiteralPath "$mem\MEMORY.md" `
                -Value ($idx -replace 'Last consolidated: never', 'Last consolidated: 2026-08-27')
    Invoke-RunBoot $pair @("--uninstall", "--yes") | Out-Null
    Assert-DirMissing 43 $mem
    # And nothing else may be left either -- same bar as case 41.
    $orphans = @(Get-ChildItem -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -notmatch [regex]::Escape('\.git\') -and
                                $_.Name -ne '.git' } |
                 ForEach-Object { $_.FullName.Substring($ws.Length + 1) })
    if ($orphans.Count -gt 0) {
        Fail 43 ("uninstall left " + $orphans.Count + " orphan path(s): " + ($orphans -join ', '))
    }
    # Discarding an un-consolidated trail must be stated, never silent.
    if ((Get-LastBootOutput) -notmatch 'Removing the Dreaming memory store') {
        Fail 43 "uninstall discarded the session logs without reporting it"
    }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "44 upgrade orphans de-payloaded path" $Pattern {
    # Regression: orphan detection asked "does this still exist in the pack
    # Source?" when the real question is "is this still in the PAYLOAD?".
    # tests/_qi/automated/ is still in the repo but is deliberately no longer
    # installed, so every workspace upgrading past that change kept all 34 pack
    # test files -- never reported, never removed, and (being excluded from
    # Copy-TreeScoped) never updated again either. They sit one directory from
    # tests/_qi/manual/, where the user's OWN QI tests live. The upgrade
    # reported success and bumped the version while leaving the stale tree.
    #
    # Simulates a pre-exclusion install by placing one such file and recording
    # it in the manifest the way the old installer would have, then upgrading.
    # (Twin of case 43 in e2e-bootstrap.sh.)
    $src = Invoke-MkSource -Tagged
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    try {
        Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--yes", "--source=$src") | Out-Null

        # A path that still EXISTS in the source but is no longer payload.
        $legacyRel = '.assert-iq/tests/_qi/automated/run-all.sh'
        $legacySrc = Join-Path $src $legacyRel
        if (-not (Test-Path -LiteralPath $legacySrc)) { Fail 44 "fixture source lacks $legacyRel"; return }
        $legacyDst = Join-Path $ws ($legacyRel -replace '/','\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $legacyDst) | Out-Null
        Copy-Item -LiteralPath $legacySrc -Destination $legacyDst -Force

        $mfPath = Join-Path $ws '.assert-iq\.install-manifest.json'
        $mf = Get-Content -Raw -LiteralPath $mfPath | ConvertFrom-Json
        $mf.paths = @($mf.paths) + @([pscustomobject]@{
            action = 'created'; path = $legacyDst; scope = 'workspace'; sha = 'x' })
        Set-Content -LiteralPath $mfPath -Value ($mf | ConvertTo-Json -Depth 10)

        Set-Content -LiteralPath "$src\VERSION" -Value "99.0.0"
        Invoke-RunBoot $pair @("--upgrade", "--yes", "--source=$src") | Out-Null
        $out = Get-LastBootOutput

        if ($out -notmatch 'orphan from a previous version.*tests/_qi/automated') {
            Fail 44 "de-payloaded path was not reported as an orphan"
        }
        # Negative control: the regression corpus IS still payload. Reporting it
        # would mean the prefix had been widened to .assert-iq/tests/, stranding
        # golden-corpus.jsonl and breaking the post-dream regression gate.
        if ($out -match 'orphan.*tests/_qi/regression') {
            Fail 44 "golden corpus wrongly treated as an orphan"
        }
        Assert-FileExists 44 "$ws\.assert-iq\tests\_qi\regression\golden-corpus.jsonl"
        # Negative control: a still-shipped file must never be reported.
        if ($out -match 'orphan.*config\.yaml') {
            Fail 44 "still-shipped config.yaml reported as an orphan"
        }
    } finally {
        Remove-Item -LiteralPath $src -Recurse -Force -ErrorAction SilentlyContinue
        Invoke-CleanupFixture $pair $Keep
    }
}

Run-Case "45 upgrade preserves trial mode" $Pattern {
    # -Upgrade must never flip trial <-> committed, and every file it ADDS must
    # be hidden from git too. Otherwise the first upgrade after a trial install
    # starts leaking pack files into the user's git status -- the one thing
    # trial mode exists to prevent. All three shipped upgrade cases (37/38/39)
    # install with --mode=committed, so nothing covered the trial path.
    # (Twin of case 44 in e2e-bootstrap.sh.)
    $src = Invoke-MkSource -Tagged
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    try {
        Invoke-RunBoot $pair @("--preset=pod", "--mode=trial", "--yes", "--source=$src") | Out-Null
        Assert-JsonField 45 "$ws\.assert-iq\.install-manifest.json" "mode" "trial"
        Assert-Contains  45 "$ws\.git\info\exclude" "assert-iq trial mode"

        # A surface the upgraded pack adds that the old one did not have.
        $newRel = '.github/skills/aiq-e2e-probe/SKILL.md'
        $newSrc = Join-Path $src ($newRel -replace '/','\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $newSrc) | Out-Null
        Set-Content -LiteralPath $newSrc -Value "---`nname: aiq-e2e-probe`ndescription: probe`n---`nprobe"
        Set-Content -LiteralPath "$src\VERSION" -Value "99.0.0"

        Invoke-RunBoot $pair @("--upgrade", "--yes", "--source=$src") | Out-Null

        Assert-FileExists 45 (Join-Path $ws ($newRel -replace '/','\'))
        Assert-JsonField  45 "$ws\.assert-iq\.install-manifest.json" "mode" "trial"
        Assert-Contains   45 "$ws\.git\info\exclude" "assert-iq trial mode"
        Assert-Contains   45 "$ws\.git\info\exclude" $newRel
        # Belt and braces: ask git itself, not just the exclude file.
        Push-Location $ws
        try {
            $st = (git status --porcelain -- $newRel 2>$null)
            if ($st) { Fail 45 "upgrade-added file is visible to git in trial mode" }
        } finally { Pop-Location }
    } finally {
        Remove-Item -LiteralPath $src -Recurse -Force -ErrorAction SilentlyContinue
        Invoke-CleanupFixture $pair $Keep
    }
}

echo "`nSummary: $($global:CASES_PASS) pass, $($global:CASES_FAIL) fail"
if ($global:CASES_FAIL -gt 0) {
    echo "Failures:"
    $global:FAIL_LOG | ForEach-Object { Write-Red $_ }
    exit 1
}
