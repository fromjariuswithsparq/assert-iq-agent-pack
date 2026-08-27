# Assert.IQ E2E PowerShell Library
$ErrorActionPreference = "Stop"

# The host to spawn child PowerShell processes with. Hard-coding 'pwsh' made the
# suite unrunnable on a stock Windows box: PowerShell 7 is an optional install,
# while Windows PowerShell 5.1 is always present and IS a supported host for the
# pack. Reusing the current host also means the tests exercise whichever
# PowerShell the developer actually invoked them with.
$AiqPwsh = try { [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }
           catch { if ($PSVersionTable.PSVersion.Major -ge 6) { 'pwsh' } else { 'powershell' } }

$PSNativeCommandUseErrorActionPreference = $false

# WINDOWS POWERSHELL 5.1 COMPATIBILITY
#
# With $ErrorActionPreference='Stop' (set above so cmdlet failures surface as
# case failures), Windows PowerShell 5.1 converts ANY unredirected native-command
# stderr into a TERMINATING NativeCommandError. git writes routine notices there
# -- "warning: LF will be replaced by CRLF the next time Git touches it" -- so
# fixture setup aborted midway through `git init` / `git config` / `git commit`
# and the whole suite was PowerShell-7-only. PS7 avoids this via
# $PSNativeCommandUseErrorActionPreference above, which 5.1 does not have.
#
# Shadowing `git` with a function fixes every call site at once (there are ~37)
# without touching them: PowerShell resolves functions before applications. The
# body invokes git.exe explicitly so this cannot recurse, and $LASTEXITCODE is
# still set globally, so callers that check it behave identically.
$script:AiqGitExe = (Get-Command git.exe -ErrorAction SilentlyContinue).Source
if (-not $script:AiqGitExe) { $script:AiqGitExe = 'git' }
function git {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $script:AiqGitExe @args
    } finally {
        $ErrorActionPreference = $prev
    }
}

$global:CASES_PASS = 0
$global:CASES_FAIL = 0
$global:CASES_SKIP = 0
$global:FAIL_LOG = @()

function Write-Red($msg) { Write-Host $msg -ForegroundColor Red }
function Write-Grn($msg) { Write-Host $msg -ForegroundColor Green -NoNewline; Write-Host "" }
function Write-Ylw($msg) { Write-Host $msg -ForegroundColor Yellow -NoNewline; Write-Host "" }

function Invoke-MkFixture {
    $tmp = [System.IO.Path]::GetTempPath()
    $ws = Join-Path $tmp ("aiq-ws." + [Guid]::NewGuid().ToString().Substring(0,8))
    $homeDir = Join-Path $tmp ("aiq-home." + [Guid]::NewGuid().ToString().Substring(0,8))
    New-Item -ItemType Directory -Path $ws -Force | Out-Null
    New-Item -ItemType Directory -Path $homeDir -Force | Out-Null
    
    Push-Location $ws
    try {
        git init -q
        git config user.email "t@t"
        git config user.name "t"
        git commit --allow-empty -q -m "init"
    } catch {} finally {
        Pop-Location
    }
    return @{ ws = $ws; home = $homeDir }
}

function Invoke-CleanupFixture($pair, $Keep) {
    if ($Keep) { Write-Host "  (kept: $($pair.ws))"; return }
    $paths = @($pair.ws, $pair.copy, $pair.home) | Where-Object { $_ }
    foreach ($p in $paths) {
        if (Test-Path $p) { Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue }
    }
}

function Invoke-MkPackCopy {
    $tmp = [System.IO.Path]::GetTempPath()
    $copy = Join-Path $tmp ("aiq-pack." + [Guid]::NewGuid().ToString().Substring(0,8))
    $homeDir = Join-Path $tmp ("aiq-home." + [Guid]::NewGuid().ToString().Substring(0,8))
    New-Item -ItemType Directory -Path $copy -Force | Out-Null
    New-Item -ItemType Directory -Path $homeDir -Force | Out-Null
    Copy-Item "$PackDir/*" -Destination $copy -Recurse -Exclude ".git","node_modules","tests" -Force | Out-Null
    return @{ copy = $copy; home = $homeDir }
}

# Text that the most recent Invoke-RunBoot printed (stdout + stderr).
function Get-LastBootOutput { if ($null -eq $script:LastBootOutput) { '' } else { $script:LastBootOutput } }

function Invoke-MkSource {
    <#
      Builds a disposable copy of the pack to serve as an --upgrade SOURCE.
      -Tagged annotates it with v<VERSION> so bootstrap can reconstruct the
      install baseline via `git show v<VERSION>:<path>`; without the tag the
      upgrade must fall back to the install-time .assert-iq/.base cache. Those
      are the two distinct paths cases 38 and 39 exercise.
    #>
    param([switch]$Tagged)
    $src = Join-Path ([System.IO.Path]::GetTempPath()) ("aiq-src." + [Guid]::NewGuid().ToString().Substring(0,8))
    New-Item -ItemType Directory -Path $src -Force | Out-Null
    # Copy the pack WITHOUT .git: the source needs its own history so the tag we
    # create is the only baseline available.
    Get-ChildItem -LiteralPath $PackDir -Force | Where-Object {
        $_.Name -notin @('.git', 'node_modules')
    } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $src -Recurse -Force -ErrorAction SilentlyContinue
    }
    Push-Location $src
    try {
        git init -q
        git config user.email "t@t"
        git config user.name "t"
        git add -A 2>$null | Out-Null
        git commit -q -m "init" 2>$null | Out-Null
        if ($Tagged) {
            $ver = (Get-Content -LiteralPath (Join-Path $src 'VERSION') -TotalCount 1).Trim()
            git tag -a "v$ver" -m "v$ver" 2>$null | Out-Null
        }
    } finally {
        Pop-Location
    }
    return $src
}

# ---- byte-preserving file edits for the upgrade-merge cases ----------------
# The bash suite edits fixtures with `printf >>` and `{ echo; cat; } >` , which
# touch ONLY the bytes being added. Doing the same in PowerShell with
# Get-Content | Set-Content silently rewrites the WHOLE file -- re-encoding it,
# normalizing line endings, and adding a trailing newline -- so the three-way
# merge saw the entire tail as modified on both sides and produced a spurious
# conflict. These helpers keep every other byte intact and reuse the file's own
# EOL convention, so the merge sees exactly the one-line change intended.
function Get-FileEol([string]$Text) { if ($Text -match "`r`n") { "`r`n" } else { "`n" } }

function Add-UserEdit([string]$Path, [string]$Marker) {
    $raw = [System.IO.File]::ReadAllText($Path)
    $eol = Get-FileEol $raw
    [System.IO.File]::WriteAllText($Path, $raw + $eol + $Marker + $eol)
}

function Add-PackEdit([string]$Path, [string]$Marker) {
    $raw = [System.IO.File]::ReadAllText($Path)
    $eol = Get-FileEol $raw
    [System.IO.File]::WriteAllText($Path, $Marker + $eol + $raw)
}

function Set-FirstLine([string]$Path, [string]$Text) {
    $raw = [System.IO.File]::ReadAllText($Path)
    $eol = Get-FileEol $raw
    $idx = $raw.IndexOf($eol)
    if ($idx -lt 0) {
        [System.IO.File]::WriteAllText($Path, $Text + $eol)
    } else {
        [System.IO.File]::WriteAllText($Path, $Text + $raw.Substring($idx))
    }
}

function Get-SkillFiles($ws, [int]$Count) {
    # First N SKILL.md paths, workspace-relative with forward slashes, in a
    # stable order so the "target / conflict / orphan" roles are reproducible.
    $root = Join-Path $ws '.github\skills'
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $files = Get-ChildItem -LiteralPath $root -Recurse -Filter 'SKILL.md' -File |
             Sort-Object FullName | Select-Object -First $Count
    return @($files | ForEach-Object {
        $_.FullName.Substring($ws.Length).TrimStart('\','/').Replace('\','/')
    })
}

function Invoke-RunBoot($pair, [string[]]$ArgsList) {
    $origHome = $env:HOME
    $origUserProfile = $env:USERPROFILE
    $origAppData = $env:APPDATA
    $origLocalAppData = $env:LOCALAPPDATA
    
    $env:HOME = $pair.home
    $env:USERPROFILE = $pair.home
    $env:APPDATA = Join-Path $pair.home "AppData\Roaming"
    $env:LOCALAPPDATA = Join-Path $pair.home "AppData\Local"
    
    if (-not (Test-Path $env:APPDATA)) { New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null }
    
    try {
        $bootArgs = @("-NoProfile", "-File", (Join-Path $PackDir "scripts/bootstrap.ps1"), "-Workspace", $pair.ws)
        foreach ($a in $ArgsList) {
            if ($a -match "^--(.+)=(.*)$") {
                $bootArgs += "-" + ($matches[1] -replace '-', '')
                $bootArgs += $matches[2]
            } elseif ($a -match "^--(.+)$") {
                $bootArgs += "-" + ($matches[1] -replace '-', '')
            }
        }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $AiqPwsh
        # ProcessStartInfo.ArgumentList exists only on .NET Core 2.1+ (i.e.
        # PowerShell 7). Windows PowerShell 5.1 runs on .NET Framework, where the
        # property is $null -- so .Add() threw "You cannot call a method on a
        # null-valued expression" for EVERY case in this suite. Fall back to the
        # single-string .Arguments with Windows command-line quoting.
        if ($null -ne $psi.ArgumentList) {
            foreach ($a in $bootArgs) { $psi.ArgumentList.Add([string]$a) }
        } else {
            $quoted = foreach ($a in $bootArgs) {
                $s = [string]$a
                if ($s -eq '' -or $s -match '[\s"]') {
                    # Double any trailing backslashes so they do not escape the
                    # closing quote, then escape embedded quotes.
                    '"' + (($s -replace '(\\+)$', '$1$1') -replace '"', '\"') + '"'
                } else {
                    $s
                }
            }
            $psi.Arguments = ($quoted -join ' ')
        }
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.Close()
        # Keep BOTH streams: cases 35 and 37 assert on what bootstrap PRINTED
        # ("conflict", "orphan from a previous version"), which this used to
        # throw away. Read stdout fully before waiting, or a chatty install can
        # fill the pipe buffer and deadlock.
        $so = $proc.StandardOutput.ReadToEnd()
        $se = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        $script:LastBootOutput = ($so + "`n" + $se)
        $script:LastBootExit = $proc.ExitCode
        return $proc.ExitCode
    } finally {
        $env:HOME = $origHome
        $env:USERPROFILE = $origUserProfile
        $env:APPDATA = $origAppData
        $env:LOCALAPPDATA = $origLocalAppData
    }
}

function Fail($label, $msg) {
    $global:FAIL_LOG += "  FAIL ${label}: $msg"
    $global:CASES_FAIL++
}
function Assert-FileExists($label, $path) { if (-not (Test-Path $path -PathType Leaf)) { Fail $label "expected to exist: $path" } }
function Assert-FileMissing($label, $path) { if (Test-Path $path -PathType Leaf) { Fail $label "expected missing: $path" } }
function Assert-DirExists($label, $path) { if (-not (Test-Path $path -PathType Container)) { Fail $label "expected dir: $path" } }
function Assert-DirMissing($label, $path) { if (Test-Path $path -PathType Container) { Fail $label "expected dir missing: $path" } }
function Assert-Contains($label, $path, $text) { 
    if (-not (Test-Path $path)) { Fail $label "file missing: $path"; return }
    if (-not (Select-String -Path $path -Pattern ([regex]::Escape($text)) -Quiet)) { Fail $label "expected '$text' in $path" }
}
function Assert-NotContains($label, $path, $text) { 
    if (-not (Test-Path $path)) { return }
    if (Select-String -Path $path -Pattern ([regex]::Escape($text)) -Quiet) { Fail $label "expected NOT '$text' in $path" }
}
function Assert-JsonField($label, $path, $field, $expected) {
    # PARSE, never substring-match, JSON that PowerShell wrote. Windows
    # PowerShell 5.1's ConvertTo-Json emits TWO spaces after the colon
    # ("version":  "2.0.2") while PowerShell 7 emits one, so a literal
    # '"version": "99.0.0"' assertion passes on 7 and fails on 5.1 for a file
    # that is perfectly correct.
    if (-not (Test-Path -LiteralPath $path)) { Fail $label "file missing: $path"; return }
    try {
        $obj = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    } catch {
        Fail $label "not valid JSON: $path"; return
    }
    $actual = $obj.$field
    if ("$actual" -ne "$expected") {
        Fail $label "$field = '$actual', expected '$expected' in $path"
    }
}

function Assert-EqualSha($label, $a, $b) {
    if (-not (Test-Path $a) -or -not (Test-Path $b)) { Fail $label "missing file for sha match"; return }
    $sa = (Get-FileHash $a -Algorithm SHA256).Hash
    $sb = (Get-FileHash $b -Algorithm SHA256).Hash
    if ($sa -ne $sb) { Fail $label "sha mismatch: $a vs $b" }
}

function Run-Case($label, $Pattern, $scriptBlock) {
    if ($Pattern -ne "" -and $label -notmatch $Pattern) { return }
    $before_fail = $global:CASES_FAIL
    Write-Host ("  {0,-55} " -f $label) -NoNewline
    try {
        & $scriptBlock
        if ($global:CASES_FAIL -gt $before_fail) { Write-Red "FAIL" }
        else { Write-Grn "PASS"; $global:CASES_PASS++ }
    } catch {
        Write-Red "FAIL"
        Fail $label $_.Exception.Message
    }
}
