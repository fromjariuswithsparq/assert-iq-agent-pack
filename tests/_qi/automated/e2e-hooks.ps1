<#
.SYNOPSIS
Assert.IQ hooks E2E driver (PowerShell).
#>
param(
    [switch]$Keep,
    [string]$Pattern = ""
)

$PackDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
. "$PSScriptRoot/aiq-e2e-lib.ps1"

Run-Case "01 workspace install layout" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    Assert-FileExists 01 "$ws\hooks\hooks.json"
    Assert-FileExists 01 "$ws\hooks\scripts\lib\json-utils.ps1"
    Assert-DirExists  01 "$ws\hooks\sessions"
    Assert-Contains   01 "$ws\hooks\hooks.json" "SKILL_IMPROVE_ROOT"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "02 user install layout" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws; $homeDir = $pair.home
    Invoke-RunBoot $pair @("--preset=portable", "--mode=committed", "--hooks=user", "--yes") | Out-Null
    Assert-FileExists 02 "$homeDir\.agents\hooks\hooks.json"
    Assert-FileExists 02 "$homeDir\.agents\hooks\scripts\lib\json-utils.ps1"
    Assert-DirExists  02 "$homeDir\.agents\hooks\sessions"
    Assert-Contains   02 "$homeDir\.agents\hooks\hooks.json" "SKILL_IMPROVE_ROOT"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "03 workspace SessionStart writes local" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws; $homeDir = $pair.home
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    $out = Invoke-RunHook $pair "hooks\scripts\skill-improve-session-start.ps1" "sid-A" @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks" }
    if ($out -notmatch "`"continue`":true") { Fail 03 "missing continue envelope" }
    Assert-DirExists  03 "$ws\hooks\sessions\sid-A"
    Assert-FileExists 03 "$ws\hooks\sessions\sid-A\loaded-customizations.json"
    Assert-DirMissing 03 "$homeDir\.agents\hooks\sessions\sid-A"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "04 user SessionStart writes ~/.agents" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws; $homeDir = $pair.home
    Invoke-RunBoot $pair @("--preset=portable", "--mode=committed", "--hooks=user", "--yes") | Out-Null
    $out = Invoke-RunHookUser $pair "scripts\skill-improve-session-start.ps1" "sid-B" @{ "SKILL_IMPROVE_ROOT" = "$homeDir\.agents\hooks" }
    if ($out -notmatch "`"continue`":true") { Fail 04 "missing continue envelope" }
    Assert-DirExists  04 "$homeDir\.agents\hooks\sessions\sid-B"
    Assert-FileExists 04 "$homeDir\.agents\hooks\sessions\sid-B\loaded-customizations.json"
    Assert-DirMissing 04 "$ws\hooks\sessions\sid-B"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "05 PostToolUse telemetry continues" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    $out = Invoke-RunHook $pair "hooks\scripts\track-telemetry.ps1" "sid-T" @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks"; "AZURE_MCP_COLLECT_TELEMETRY" = "false" }
    if ($out -notmatch "`"continue`":true") { Fail 05 "expected continue:true, got: $out" }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "06 PostToolUse detect appends log" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    $out = Invoke-RunHook $pair "hooks\scripts\skill-improve-detect.ps1" "sid-D" @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks" }
    Assert-FileExists 06 "$ws\hooks\sessions\sid-D\tool-log.jsonl"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "07 Stop writes log entry" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    $out = Invoke-RunHook $pair "hooks\scripts\skill-improve-session-end.ps1" "sid-S" @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks" }
    Assert-FileExists 07 "$ws\hooks\logs\skill-improve.log"
    Assert-Contains   07 "$ws\hooks\logs\skill-improve.log" "sid=sid-S"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "08 config.enabled=false no-op" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    $conf = Get-Content "$ws\hooks\config\skill-improve.config.json" -Raw | ConvertFrom-Json
    $conf.enabled = $false
    $conf | ConvertTo-Json -Depth 10 | Set-Content "$ws\hooks\config\skill-improve.config.json"
    $out = Invoke-RunHook $pair "hooks\scripts\skill-improve-session-start.ps1" "sid-OFF" @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks" }
    Assert-DirMissing 08 "$ws\hooks\sessions\sid-OFF"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "09 SKILL_IMPROVE_DISABLED=1 no-op" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    $out = Invoke-RunHook $pair "hooks\scripts\skill-improve-session-start.ps1" "sid-ENVOFF" @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks"; "SKILL_IMPROVE_DISABLED" = "1" }
    Assert-DirMissing 09 "$ws\hooks\sessions\sid-ENVOFF"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "10 dedup suppresses double-fire" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    $sid = "sid-DEDUP-123"
    $out1 = Invoke-RunHook $pair "hooks\scripts\skill-improve-session-start.ps1" $sid @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks" }
    $out2 = Invoke-RunHook $pair "hooks\scripts\skill-improve-session-start.ps1" $sid @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks" }
    if ($out2 -notmatch "`"continue`":true") { Fail 10 "second fire missing continue:true" }
    Assert-Contains 10 "$ws\hooks\logs\skill-improve.log" "dedup SessionStart sid=$sid"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "11 DEDUP_WINDOW_SECONDS=0 disables" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    $sid = "sid-NODEDUP-123"
    $out1 = Invoke-RunHook $pair "hooks\scripts\skill-improve-session-start.ps1" $sid @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks"; "SKILL_IMPROVE_DEDUP_WINDOW_SECONDS" = "0" }
    $out2 = Invoke-RunHook $pair "hooks\scripts\skill-improve-session-start.ps1" $sid @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks"; "SKILL_IMPROVE_DEDUP_WINDOW_SECONDS" = "0" }
    Assert-NotContains 11 "$ws\hooks\logs\skill-improve.log" "dedup SessionStart sid=$sid"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "12 dedup is per-event" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    $sid = "sid-PER-123"
    $out1 = Invoke-RunHook $pair "hooks\scripts\skill-improve-session-start.ps1" $sid @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks" }
    $out2 = Invoke-RunHook $pair "hooks\scripts\skill-improve-session-end.ps1" $sid @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks" }
    Assert-Contains 12 "$ws\hooks\logs\skill-improve.log" "sid=$sid"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "13 dedup marker created under state/" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    $sid = "sid-MARK-123"
    $out = Invoke-RunHook $pair "hooks\scripts\skill-improve-session-start.ps1" $sid @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks" }
    $markers = Get-ChildItem -Path "$ws\hooks\state" -Filter ".dedup-*" -ErrorAction SilentlyContinue
    if ($markers.Count -eq 0) { Fail 13 "no .dedup-* marker created" }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "14 workspace/user installs isolated" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws; $homeDir = $pair.home
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    Invoke-RunBoot $pair @("--preset=portable", "--mode=committed", "--hooks=user", "--yes") | Out-Null
    $out1 = Invoke-RunHook $pair "hooks\scripts\skill-improve-session-start.ps1" "sid-WS-ONLY" @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks" }
    Assert-DirExists  14 "$ws\hooks\sessions\sid-WS-ONLY"
    Assert-DirMissing 14 "$homeDir\.agents\hooks\sessions\sid-WS-ONLY"
    
    $out2 = Invoke-RunHookUser $pair "scripts\skill-improve-session-start.ps1" "sid-USR-ONLY" @{ "SKILL_IMPROVE_ROOT" = "$homeDir\.agents\hooks" }
    Assert-DirExists  14 "$homeDir\.agents\hooks\sessions\sid-USR-ONLY"
    Assert-DirMissing 14 "$ws\hooks\sessions\sid-USR-ONLY"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "15 --uninstall --user clears hooks" $Pattern {
    $pair = Invoke-MkFixture
    $homeDir = $pair.home
    Invoke-RunBoot $pair @("--preset=portable", "--mode=committed", "--hooks=user", "--yes") | Out-Null
    Assert-FileExists 15 "$homeDir\.agents\hooks\hooks.json"
    Invoke-RunBoot $pair @("--uninstall", "--user", "--yes") | Out-Null
    Assert-FileMissing 15 "$homeDir\.agents\hooks\hooks.json"
    Assert-DirMissing  15 "$homeDir\.agents\hooks\scripts"
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "16 Stop emits systemMessage when announced" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    $cfgPath = "$ws\hooks\config\skill-improve.config.json"
    $cfg = Get-Content -Raw $cfgPath | ConvertFrom-Json
    if (-not $cfg.behavior) { $cfg | Add-Member -NotePropertyName behavior -NotePropertyValue (New-Object PSObject) -Force }
    $cfg.behavior | Add-Member -NotePropertyName silent_on_zero_corrections -NotePropertyValue $false -Force
    $cfg | ConvertTo-Json -Depth 10 | Set-Content -Path $cfgPath -Encoding UTF8
    $out = Invoke-RunHook $pair "hooks\scripts\skill-improve-session-end.ps1" "sid-ANN" @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks" }
    if ($out -notmatch '"systemMessage":"skill-improve: no corrections detected this session."') {
        Fail 16 "expected systemMessage envelope, got: $out"
    }
    if ($out -notmatch '"continue":true') { Fail 16 "missing continue:true: $out" }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "17 Stop silent when silent_on_zero=true" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    $cfgPath = "$ws\hooks\config\skill-improve.config.json"
    $cfg = Get-Content -Raw $cfgPath | ConvertFrom-Json
    if (-not $cfg.behavior) { $cfg | Add-Member -NotePropertyName behavior -NotePropertyValue (New-Object PSObject) -Force }
    $cfg.behavior | Add-Member -NotePropertyName silent_on_zero_corrections -NotePropertyValue $true -Force
    $cfg | ConvertTo-Json -Depth 10 | Set-Content -Path $cfgPath -Encoding UTF8
    $out = Invoke-RunHook $pair "hooks\scripts\skill-improve-session-end.ps1" "sid-SIL" @{ "SKILL_IMPROVE_ROOT" = "$ws\hooks" }
    if ($out -match 'systemMessage') { Fail 17 "expected no systemMessage when silent=true, got: $out" }
    if ($out -notmatch '"continue":true') { Fail 17 "missing continue:true: $out" }
    Invoke-CleanupFixture $pair $Keep
}

Run-Case "18 Stop emits decision:block on corrections" $Pattern {
    $pair = Invoke-MkFixture
    $ws = $pair.ws
    Invoke-RunBoot $pair @("--preset=pod", "--mode=committed", "--hooks=workspace", "--yes") | Out-Null
    $sessionsDir = "$ws\hooks\sessions"
    if (-not (Test-Path $sessionsDir)) { New-Item -ItemType Directory -Path $sessionsDir -Force | Out-Null }
    $tx = "$sessionsDir\.fake-transcript.jsonl"
    @(
        '{"role":"assistant","content":"Scratch that - my mistake, the correct answer is different."}'
        '{"role":"assistant","content":"Apologize for the oversight; I should have checked first."}'
    ) | Set-Content -Path $tx -Encoding UTF8
    $payload = (@{ session_id = "sid-CORR"; hook_event_name = "Stop"; transcript_path = $tx } | ConvertTo-Json -Compress)
    $homeDir = $pair.home
    $origHome = $env:HOME; $env:HOME = $homeDir
    $origRoot = [Environment]::GetEnvironmentVariable("SKILL_IMPROVE_ROOT")
    [Environment]::SetEnvironmentVariable("SKILL_IMPROVE_ROOT", "$ws\hooks")
    try {
        $out = $payload | & pwsh -NoProfile -File "$ws\hooks\scripts\skill-improve-session-end.ps1" 2>&1 | Out-String
    } finally {
        $env:HOME = $origHome
        [Environment]::SetEnvironmentVariable("SKILL_IMPROVE_ROOT", $origRoot)
    }
    if ($out -notmatch '"decision":\s*"block"') { Fail 18 "expected decision:block envelope when corrections fire, got: $out" }
    if ($out -notmatch 'SKILL-IMPROVE: sid-CORR') { Fail 18 "expected SKILL-IMPROVE task block in reason, got: $out" }
    Assert-Contains 18 "$ws\hooks\logs\skill-improve.log" "Stop sid=sid-CORR corrections=true"
    Invoke-CleanupFixture $pair $Keep
}

echo "`nSummary: $($global:CASES_PASS) pass, $($global:CASES_FAIL) fail"
if ($global:CASES_FAIL -gt 0) {
    echo "Failures:"
    $global:FAIL_LOG | ForEach-Object { Write-Red $_ }
    exit 1
}
