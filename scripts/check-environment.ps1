# Assert.IQ environment check (Windows / PowerShell).
#
# Run this BEFORE installing. It reports every requirement the pack needs, what
# it found, and the exact fix when something is missing -- so a bad environment
# surfaces here instead of as a confusing failure mid-install.
#
#   powershell -File scripts\check-environment.ps1     # Windows PowerShell 5.1
#   pwsh -File scripts/check-environment.ps1           # PowerShell 7+, any OS
#
# Exit codes: 0 = ready to install, 1 = at least one hard requirement missing.
# Warnings never fail the run: they mark reduced functionality, not a blocker.
#
# ASCII-ONLY BY POLICY. Windows PowerShell 5.1 reads a BOM-less file as cp1252,
# so a single em dash here could stop this script from parsing on the very host
# it exists to diagnose. Enforced by unit-script-portability.py.
[CmdletBinding()]
param([switch]$Quiet)

$hardFail = 0
$warn = 0

function Line($status, $label, $detail) {
    $color = switch ($status) { 'PASS' { 'Green' } 'WARN' { 'Yellow' } default { 'Red' } }
    Write-Host ("  [{0}] " -f $status) -ForegroundColor $color -NoNewline
    Write-Host ("{0,-26} {1}" -f $label, $detail)
}
function Pass($label, $detail) { Line 'PASS' $label $detail }
function Warn($label, $detail, $fix) {
    $script:warn++
    Line 'WARN' $label $detail
    if ($fix) { Write-Host ("         fix: " + $fix) -ForegroundColor DarkGray }
}
function Fail($label, $detail, $fix) {
    $script:hardFail++
    Line 'FAIL' $label $detail
    if ($fix) { Write-Host ("         fix: " + $fix) -ForegroundColor DarkGray }
}

# Resolve the pack root from this script's location.
$pack = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Write-Host ""
Write-Host "Assert.IQ environment check"
Write-Host ("pack: " + $pack)
Write-Host ""

# ---- 1. Host -------------------------------------------------------------
$psv = $PSVersionTable.PSVersion
$isWin = $IsWindows -or ($env:OS -eq 'Windows_NT')
$osLabel = if ($isWin) { 'Windows' } elseif ($IsMacOS) { 'macOS' } else { 'Linux/other' }
if ($psv.Major -ge 7) {
    Pass 'PowerShell' ("{0} on {1} -- the recommended host" -f $psv, $osLabel)
} elseif ($psv.Major -eq 5 -and $psv.Minor -ge 1) {
    # Supported, not merely tolerated: the full e2e matrix passes on 5.1. But
    # 7 is the better default -- it can usually create the .claude\skills
    # symlink where 5.1 falls back to a copy.
    Pass 'PowerShell' ("{0} on {1} -- supported and tested" -f $psv, $osLabel)
    Write-Host "         note: PowerShell 7 is recommended (live .claude\skills symlink instead of a copy): winget install Microsoft.PowerShell" -ForegroundColor DarkGray
} else {
    Fail 'PowerShell' ("{0} is too old" -f $psv) 'install PowerShell 7 (winget install Microsoft.PowerShell), or use the built-in Windows PowerShell 5.1'
}

# ---- 2. git --------------------------------------------------------------
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    $gv = (& git --version) -replace 'git version ',''
    Pass 'git' $gv
    # Trial mode writes to .git\info\exclude, so the target must be a work tree.
    & git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -eq 0) {
        Pass 'git work tree' 'current directory is inside a repo'
    } else {
        Warn 'git work tree' 'not inside a git repo' 'cd into the repo you want the pack installed in before running bootstrap (--mode=trial needs .git\info\exclude)'
    }
} else {
    Fail 'git' 'not found on PATH' 'winget install Git.Git'
}

# ---- 3. Python 3 ---------------------------------------------------------
# `python3` is NOT a reliable name on Windows: the Microsoft Store ships a
# python3 STUB that resolves on PATH, prints an install hint and exits non-zero,
# while the python.org installer provides python.exe with NO python3.exe. The
# only honest probe is to EXECUTE each candidate.
$pyFound = $null
foreach ($cand in @('python3', 'python')) {
    if (-not (Get-Command $cand -ErrorAction SilentlyContinue)) { continue }
    $v = & $cand -c "import sys; print('%d.%d.%d' % sys.version_info[:3])" 2>$null
    if ($LASTEXITCODE -eq 0 -and $v) { $pyFound = @{ Cmd = $cand; Version = $v }; break }
}
if (-not $pyFound -and (Get-Command py -ErrorAction SilentlyContinue)) {
    $v = & py -3 -c "import sys; print('%d.%d.%d' % sys.version_info[:3])" 2>$null
    if ($LASTEXITCODE -eq 0 -and $v) { $pyFound = @{ Cmd = 'py -3'; Version = $v } }
}
if ($pyFound) {
    Pass 'Python 3' ("{0} via '{1}'" -f $pyFound.Version, $pyFound.Cmd)
    if ($pyFound.Cmd -ne 'python3') {
        Write-Host "         note: 'python3' is absent or a stub here; the pack resolves python/py -3 automatically" -ForegroundColor DarkGray
    }
} else {
    Warn 'Python 3' 'no working interpreter (tried python3, python, py -3)' 'winget install Python.Python.3.12 -- needed for calibration, memory sanity checks and verdict recording; install/bootstrap and Dreaming hooks work without it'
}

# ---- 4. Symlink capability for .claude\skills ---------------------------
if ($isWin) {
    $probe = Join-Path ([System.IO.Path]::GetTempPath()) ("aiq-symlink-" + [guid]::NewGuid().ToString('N'))
    $target = Join-Path ([System.IO.Path]::GetTempPath()) ("aiq-target-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    $canLink = $false
    try {
        New-Item -ItemType SymbolicLink -Path $probe -Target $target -ErrorAction Stop | Out-Null
        $canLink = $true
    } catch { }
    Remove-Item -LiteralPath $probe -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $target -Force -Recurse -ErrorAction SilentlyContinue
    if ($canLink) {
        Pass 'symlinks' '.claude\skills and .kiro\skills will be live symlinks to .github\skills'
    } else {
        # Host-dependent, not just OS-dependent: PowerShell 7 can create an
        # unprivileged symlink when Developer Mode is on, Windows PowerShell 5.1
        # generally still wants SeCreateSymbolicLink. Either way the installer
        # falls back to a copy, so this is never a blocker.
        $why = if ($psv.Major -lt 6) {
            'cannot create symlinks from Windows PowerShell 5.1 (PowerShell 7 often can)'
        } else {
            'cannot create symlinks'
        }
        # Two symlinks now, not one. A stale COPY is worse than it sounds: the
        # skill tree keeps working, it just silently serves the version from
        # install time. Hit for real -- three skills were edited, the copies
        # were not refreshed, and Kiro kept rejecting the pre-edit files.
        Warn 'symlinks' $why 'enable Settings > System > For developers > Developer Mode, and/or run the installer under pwsh 7. Without symlinks .github\skills is COPIED to .claude\skills AND .kiro\skills, so re-run the installer after editing any skill or those copies go stale.'
    }
}

# ---- 4b. Kiro (third harness) -------------------------------------------
# Advisory only. Kiro is optional, so its absence is not a warning -- but when
# it IS present the tester needs to know about workspace trust, because Kiro
# disables hook execution in an untrusted folder SILENTLY. Dreaming then looks
# broken with nothing in any log the user would think to read.
$kiroHome = Join-Path $env:USERPROFILE '.kiro'
if ((Get-Command kiro -ErrorAction SilentlyContinue) -or (Test-Path $kiroHome)) {
    Pass 'kiro' 'Kiro detected - .kiro\steering, agents, skills and hooks will install'
    Write-Host '         note: after installing, TRUST the workspace in Kiro. It disables hook' -ForegroundColor DarkGray
    Write-Host '               execution in untrusted folders SILENTLY, so Dreaming looks dead.' -ForegroundColor DarkGray
}

# ---- 5. Shell installers vs Git Bash ------------------------------------
if ($isWin) {
    if (Get-Command bash -ErrorAction SilentlyContinue) {
        Warn 'bash installers' 'Git Bash is present, but do NOT use install.sh / bootstrap.sh on Windows' 'use install.ps1 / bootstrap.ps1. MSYS process creation makes the bash installers take 9+ minutes per install (they copy and hash ~1000 files one process at a time); the PowerShell versions do the same work in about a minute.'
    } else {
        Pass 'bash installers' 'not applicable on Windows (use the .ps1 installers)'
    }
}

# ---- 6. jq (bash path only) ---------------------------------------------
if (-not $isWin) {
    if (Get-Command jq -ErrorAction SilentlyContinue) {
        Pass 'jq' ((& jq --version) -join '')
    } else {
        Warn 'jq' 'not found' 'optional for install, but bootstrap.sh --upgrade REQUIRES it: brew install jq (macOS) / apt install jq (Linux)'
    }
}

# ---- 7. Line endings this checkout will hand bash ------------------------
# Only meaningful where bash actually runs the scripts.
if (-not $isWin -and $git) {
    Push-Location $pack
    $crlf = @(& git ls-files --eol -- '*.sh' 2>$null | Where-Object { $_ -match 'w/crlf' })
    Pop-Location
    if ($crlf.Count -gt 0) {
        Fail 'shell line endings' ("{0} .sh file(s) are CRLF in this checkout; bash will refuse them" -f $crlf.Count) 'git add --renormalize . ; git checkout -- .'
    } else {
        Pass 'shell line endings' 'shell scripts are LF'
    }
}

# ---- 8. Installed-pack sanity (only if already installed) ---------------
$manifest = Join-Path $pack '.assert-iq\.install-manifest.json'
$settings = Join-Path $pack '.claude\settings.json'
if (Test-Path -LiteralPath $settings) {
    try {
        $j = Get-Content -Raw -LiteralPath $settings | ConvertFrom-Json
        $ss = $j.hooks.SessionStart
        if (-not $ss) {
            Warn 'Claude hooks' 'settings.json has no SessionStart hook' 're-run the installer to wire Dreaming'
        } elseif ($null -eq $ss[0].hooks) {
            Fail 'Claude hooks' 'handlers sit directly in the event array (Copilot shape)' 'Claude Code silently ignores a flat handler. Re-run install.ps1 / bootstrap.ps1 to render the matcher-group shape.'
        } else {
            Pass 'Claude hooks' ("matcher-group shape, shell=" + $ss[0].hooks[0].shell)
        }
    } catch {
        Fail 'Claude hooks' '.claude\settings.json is not valid JSON' 'fix or delete the file, then re-run the installer'
    }
} elseif (Test-Path -LiteralPath $manifest) {
    Warn 'Claude hooks' 'pack installed but .claude\settings.json is absent' 're-run the installer'
} else {
    Pass 'install state' 'pack not installed here yet (expected before first install)'
}

Write-Host ""
if ($hardFail -gt 0) {
    Write-Host ("Not ready: {0} blocking issue(s), {1} warning(s)." -f $hardFail, $warn) -ForegroundColor Red
    exit 1
}
if ($warn -gt 0) {
    Write-Host ("Ready to install, with {0} warning(s) above (reduced functionality only)." -f $warn) -ForegroundColor Yellow
} else {
    Write-Host "Ready to install." -ForegroundColor Green
}
exit 0
