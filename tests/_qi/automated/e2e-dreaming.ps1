# Assert.IQ Dreaming E2E driver (PowerShell) — parity with e2e-dreaming.sh.
# Verifies the waking loop + gate + kill-switch.
#   Usage: pwsh tests/_qi/automated/e2e-dreaming.ps1 [-Keep]
[CmdletBinding()]
param([switch]$Keep)

$ErrorActionPreference = 'Stop'
$pack = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$pass = 0; $fail = 0; $failed = @()
function Ok($m)  { $script:pass++; Write-Host "  PASS $m" -ForegroundColor Green }
function Bad($m) { $script:fail++; $script:failed += $m; Write-Host "  FAIL $m" -ForegroundColor Red }

$mem = Join-Path ([System.IO.Path]::GetTempPath()) ("aiq-dream-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $mem '.dream') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $mem 'logs') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $mem 'topics') | Out-Null
Set-Content -LiteralPath (Join-Path $mem '.dream\state.json') -Value "{`n  `"last_dream_utc`": null,`n  `"sessions_since_dream`": 0`n}" -Encoding UTF8

$env:AIQ_PACK_ROOT = $pack
$env:AIQ_MEMORY_DIR = $mem
$env:AIQ_DREAM_MIN_SESSIONS = '5'
$rec  = Join-Path $pack '.assert-iq\dreaming\scripts\dream-record-session.ps1'
$gate = Join-Path $pack '.assert-iq\dreaming\scripts\dream-gate.ps1'
$statePath = Join-Path $mem '.dream\state.json'

try {
    Write-Host "== recorder increments counter + appends log =="
    foreach ($i in 1..5) {
        $out = ('{"session_id":"s' + $i + '"}') | & pwsh -NoProfile -File $rec
        if ($out -notmatch 'continue') { Bad "recorder envelope on run $i" }
    }
    $count = (Get-Content -Raw $statePath | ConvertFrom-Json).sessions_since_dream
    if ($count -eq 5) { Ok "counter reached 5" } else { Bad "counter expected 5, got $count" }
    if (Get-ChildItem -Recurse -Path (Join-Path $mem 'logs') -Filter *.md -ErrorAction SilentlyContinue) { Ok "daily log written" } else { Bad "no daily log" }

    Write-Host "== gate closed below threshold =="
    $d = Get-Content -Raw $statePath | ConvertFrom-Json; $d.sessions_since_dream = 3
    Set-Content -LiteralPath $statePath -Value ($d | ConvertTo-Json) -Encoding UTF8
    $out = '{}' | & pwsh -NoProfile -File $gate
    if ($out -match 'systemMessage') { Bad "gate fired at 3 sessions" } else { Ok "gate closed at 3 sessions" }

    Write-Host "== gate opens at threshold =="
    $d = Get-Content -Raw $statePath | ConvertFrom-Json; $d.sessions_since_dream = 5
    Set-Content -LiteralPath $statePath -Value ($d | ConvertTo-Json) -Encoding UTF8
    $out = '{}' | & pwsh -NoProfile -File $gate
    if ($out -match 'systemMessage') { Ok "gate opened at 5 sessions" } else { Bad "gate did not open at 5" }

    Write-Host "== kill-switch no-op =="
    $env:AIQ_DREAMING_DISABLED = '1'
    $out = '{}' | & pwsh -NoProfile -File $gate
    if ($out -match 'continue' -and $out -notmatch 'systemMessage') { Ok "AIQ_DREAMING_DISABLED honored" } else { Bad "kill-switch not honored" }
    Remove-Item Env:\AIQ_DREAMING_DISABLED -ErrorAction SilentlyContinue
}
finally {
    if (-not $Keep) { Remove-Item -Recurse -Force -LiteralPath $mem -ErrorAction SilentlyContinue }
    else { Write-Host "(kept: $mem)" }
}

Write-Host ""
Write-Host "Dreaming E2E: $pass passed, $fail failed"
if ($fail -gt 0) { $failed | ForEach-Object { Write-Host "  - $_" }; exit 1 }
