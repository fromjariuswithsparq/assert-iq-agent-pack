# Assert.IQ Dreaming E2E driver (PowerShell) -- parity with e2e-dreaming.sh.
# Verifies the waking loop + gate + kill-switch.
#   Usage: pwsh tests/_qi/automated/e2e-dreaming.ps1 [-Keep]
[CmdletBinding()]
param([switch]$Keep)

$ErrorActionPreference = 'Stop'
$pack = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$pass = 0; $fail = 0; $failed = @()
function Ok($m)  { $script:pass++; Write-Host "  PASS $m" -ForegroundColor Green }
function Bad($m) { $script:fail++; $script:failed += $m; Write-Host "  FAIL $m" -ForegroundColor Red }

# The host used to spawn child PowerShell processes. Hard-coding 'pwsh' made the
# suite unrunnable on a stock Windows box: PowerShell 7 is an optional install,
# while Windows PowerShell 5.1 is always present and IS a supported host for the
# pack. Reusing the current host also means the tests exercise whichever
# PowerShell the developer actually invoked them with.
$AiqPwsh = try { [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }
           catch { if ($PSVersionTable.PSVersion.Major -ge 6) { 'pwsh' } else { 'powershell' } }

# PYTHON: `python3` is not a reliable name. On Windows the Microsoft Store ships
# a python3 STUB that resolves on PATH but always fails, and the python.org
# installer provides python.exe with no python3.exe. Probe by EXECUTING the
# candidate -- mirrors aiq_resolve_python in
# .assert-iq/tests/_qi/automated/lib/aiq-test-lib.sh.
function Resolve-Python {
    # Windows PowerShell 5.1 turns ANY native-command stderr into a terminating
    # NativeCommandError while $ErrorActionPreference is 'Stop' (set at the top
    # of this script). The Microsoft Store python3 stub writes its install hint
    # to stderr, so probing it aborted the entire suite instead of just failing
    # that candidate -- '2>$null' does not prevent it. Relax the preference for
    # the duration of the probes only.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        foreach ($cand in @('python3', 'python')) {
            if (-not (Get-Command $cand -ErrorAction SilentlyContinue)) { continue }
            & $cand -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { return [pscustomobject]@{ Exe = $cand; PreArgs = @() } }
        }
        if (Get-Command py -ErrorAction SilentlyContinue) {
            & py -3 -c 'import sys; sys.exit(0)' 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { return [pscustomobject]@{ Exe = 'py'; PreArgs = @('-3') } }
        }
        return $null
    } finally {
        $ErrorActionPreference = $prevEap
    }
}

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
        $out = ('{"session_id":"s' + $i + '"}') | & $AiqPwsh -NoProfile -File $rec
        if ($out -notmatch 'continue') { Bad "recorder envelope on run $i" }
    }
    $count = (Get-Content -Raw $statePath | ConvertFrom-Json).sessions_since_dream
    if ($count -eq 5) { Ok "counter reached 5" } else { Bad "counter expected 5, got $count" }
    if (Get-ChildItem -Recurse -Path (Join-Path $mem 'logs') -Filter *.md -ErrorAction SilentlyContinue) { Ok "daily log written" } else { Bad "no daily log" }

    Write-Host "== gate closed below threshold =="
    $d = Get-Content -Raw $statePath | ConvertFrom-Json; $d.sessions_since_dream = 3
    Set-Content -LiteralPath $statePath -Value ($d | ConvertTo-Json) -Encoding UTF8
    $out = '{}' | & $AiqPwsh -NoProfile -File $gate
    if ($out -match 'systemMessage') { Bad "gate fired at 3 sessions" } else { Ok "gate closed at 3 sessions" }

    Write-Host "== gate opens at threshold =="
    $d = Get-Content -Raw $statePath | ConvertFrom-Json; $d.sessions_since_dream = 5
    Set-Content -LiteralPath $statePath -Value ($d | ConvertTo-Json) -Encoding UTF8
    $out = '{}' | & $AiqPwsh -NoProfile -File $gate
    if ($out -match 'systemMessage') { Ok "gate opened at 5 sessions" } else { Bad "gate did not open at 5" }

    Write-Host "== gate time-gated when recently dreamed =="
    $recent = [DateTime]::UtcNow.ToString('o')
    Set-Content -LiteralPath $statePath -Encoding UTF8 -Value (
        [pscustomobject]@{ last_dream_utc = $recent; sessions_since_dream = 9 } | ConvertTo-Json)
    $env:AIQ_DREAM_MIN_HOURS = '24'
    $out = '{}' | & $AiqPwsh -NoProfile -File $gate
    if ($out -match 'systemMessage') { Bad "gate fired despite recent dream (time gate)" } else { Ok "gate held by time gate" }
    Remove-Item -Path 'Env:AIQ_DREAM_MIN_HOURS' -ErrorAction SilentlyContinue

    Write-Host "== service enforces memory write-sandbox =="
    $py = Resolve-Python
    if (-not $py) {
        Bad "sandbox case needs Python 3 (tried python3, python, py -3); none usable"
    } else {
        $svc = Join-Path $pack '.assert-iq/dreaming/service/dreaming_service.py'
        $code = @'
import importlib.util, sys, pathlib
svc, mem = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("dsvc", svc)
m = importlib.util.module_from_spec(spec); sys.modules["dsvc"] = m; spec.loader.exec_module(m)
cfg = m.DreamConfig(project_root=pathlib.Path(mem).parent, memory_rel=pathlib.Path(mem).name)
cyc = m.DreamCycle(cfg, client=None)
try:
    cyc._apply({"files": {"../../escape.md": "pwned"}})
    print("NO_ERROR")
except PermissionError:
    print("BLOCKED")
except Exception as e:
    print("OTHER:" + type(e).__name__)
'@
        $argv = @(); $argv += $py.PreArgs; $argv += @('-', $svc, $mem)
        $sb = ($code | & $py.Exe @argv 2>$null | Select-Object -Last 1)
        if ($sb -eq 'BLOCKED') { Ok "write outside memory/ refused" } else { Bad "sandbox not enforced (got: $sb)" }
    }

    Write-Host "== kill-switch no-op =="
    $env:AIQ_DREAMING_DISABLED = '1'
    $out = '{}' | & $AiqPwsh -NoProfile -File $gate
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
