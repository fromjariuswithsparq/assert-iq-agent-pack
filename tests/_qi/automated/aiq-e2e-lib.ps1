# Assert.IQ E2E PowerShell Library
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

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
        $psi.FileName = (Get-Command pwsh).Source
        foreach ($a in $bootArgs) { $psi.ArgumentList.Add([string]$a) }
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.Close()
        $null = $proc.StandardOutput.ReadToEnd()
        $null = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        return $proc.ExitCode
    } finally {
        $env:HOME = $origHome
        $env:USERPROFILE = $origUserProfile
        $env:APPDATA = $origAppData
        $env:LOCALAPPDATA = $origLocalAppData
    }
}

function Invoke-RunHook($pair, $scriptRel, $sid, $extraEnv) {
    $ws = $pair.ws; $homeDir = $pair.home
    $payload = "{`"session_id`":`"$sid`",`"hook_event_name`":`"test`"}"
    $path = "$ws\$scriptRel"
    
    $origHome = $env:HOME; $env:HOME = $homeDir
    $origEnv = @{}
    if ($extraEnv) {
        foreach ($k in $extraEnv.Keys) { $origEnv[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $extraEnv[$k]) }
    }
    
    try {
        $out = $payload | & pwsh -NoProfile -File $path 2>&1
        return $out | Out-String
    } catch {
        return $_.Exception.Message
    } finally {
        $env:HOME = $origHome
        foreach ($k in $origEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $origEnv[$k]) }
    }
}

function Invoke-RunHookUser($pair, $scriptRel, $sid, $extraEnv) {
    $ws = $pair.ws; $homeDir = $pair.home
    $payload = "{`"session_id`":`"$sid`",`"hook_event_name`":`"test`"}"
    $path = "$homeDir\.agents\hooks\$scriptRel"
    
    $origHome = $env:HOME; $env:HOME = $homeDir
    $origEnv = @{}
    if ($extraEnv) {
        foreach ($k in $extraEnv.Keys) { $origEnv[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $extraEnv[$k]) }
    }
    
    try {
        $out = $payload | & pwsh -NoProfile -File $path 2>&1
        return $out | Out-String
    } catch {
        return $_.Exception.Message
    } finally {
        $env:HOME = $origHome
        foreach ($k in $origEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $origEnv[$k]) }
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
