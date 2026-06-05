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
    Assert-NotContains 04 "$ws\.git\info\exclude" "assert-iq trial mode"
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

echo "`nSummary: $($global:CASES_PASS) pass, $($global:CASES_FAIL) fail"
if ($global:CASES_FAIL -gt 0) {
    echo "Failures:"
    $global:FAIL_LOG | ForEach-Object { Write-Red $_ }
    exit 1
}
