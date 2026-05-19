# Shared helpers for skill-improve hooks (PowerShell side).
# Dot-sourced by other scripts: . "$PSScriptRoot\lib\json-utils.ps1"

$Script:SkillImproveRoot     = Join-Path $env:USERPROFILE '.agents\hooks'
$Script:SkillImproveConfig   = Join-Path $Script:SkillImproveRoot 'config\skill-improve.config.json'
$Script:SkillImproveLog      = Join-Path $Script:SkillImproveRoot 'logs\skill-improve.log'
$Script:SkillImproveSessions = Join-Path $Script:SkillImproveRoot 'sessions'
$Script:SkillImproveState    = Join-Path $Script:SkillImproveRoot 'state'

foreach ($d in @(
    (Join-Path $Script:SkillImproveRoot 'logs'),
    $Script:SkillImproveSessions,
    $Script:SkillImproveState
)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

function Send-SiContinue {
    Write-Output '{"continue":true}'
}

function Write-SiLog {
    param([string]$Message)
    try {
        $stamp = (Get-Date).ToUniversalTime().ToString('o')
        Add-Content -Path $Script:SkillImproveLog -Value "$stamp $Message" -ErrorAction SilentlyContinue
    } catch {}
}

# Run a scriptblock under a named cross-process mutex to serialize all shared
# state mutations (dismissed-lessons.json, edit-frequency.json,
# correction-recurrence.json, needs-rewrite.json). Counterpart to
# si_with_state_lock in json-utils.sh.
function Invoke-SiWithStateLock {
    param([Parameter(Mandatory)][scriptblock]$Action)
    $mutex = New-Object System.Threading.Mutex($false, 'Global\HindsightHooksState')
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne(30000) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
        & $Action
    } finally {
        if ($acquired) { try { $mutex.ReleaseMutex() } catch {} }
        $mutex.Dispose()
    }
}

function Test-SiEnabled {
    if ($env:SKILL_IMPROVE_DISABLED -eq '1') { return $false }
    try {
        $cfg = Get-Content -Raw -Path $Script:SkillImproveConfig -ErrorAction Stop | ConvertFrom-Json
        if ($null -ne $cfg.enabled) { return [bool]$cfg.enabled }
        return $true
    } catch { return $true }
}

function Read-SiStdin {
    if ([Console]::IsInputRedirected -eq $false) { return '' }
    try { return [Console]::In.ReadToEnd() } catch { return '' }
}

function Get-SiSessionId {
    param([string]$Raw)
    $sid = ''
    try {
        if ($Raw) {
            $d = $Raw | ConvertFrom-Json -ErrorAction Stop
            if ($d.session_id) { $sid = $d.session_id }
            elseif ($d.sessionId) { $sid = $d.sessionId }
        }
    } catch {}
    if (-not $sid) {
        $seed = (Get-Location).Path + (Get-Date -Format 'yyyy-MM-dd')
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($seed))
        $sid = 'anon-' + (-join ($bytes[0..7] | ForEach-Object { $_.ToString('x2') }))
    }
    return $sid
}

function Get-SiSessionDir {
    param([string]$SessionId)
    $dir = Join-Path $Script:SkillImproveSessions $SessionId
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    return $dir
}

# Janitor: prune silent session, trim edit-frequency, rotate log, sweep old session dirs.
function Invoke-SiJanitor {
    param([string]$SessionId, [bool]$HadCorrections)

    try {
        $cfg = Get-Content -Raw -Path $Script:SkillImproveConfig | ConvertFrom-Json
        $ret = $cfg.retention
    } catch { $ret = $null }

    $keepSilent      = $false; if ($null -ne $ret.keep_silent_sessions) { $keepSilent = [bool]$ret.keep_silent_sessions }
    $keepCorrDays    = 30;    if ($ret.keep_correction_sessions_days)   { $keepCorrDays    = [int]$ret.keep_correction_sessions_days }
    $efKeepDays      = 14;    if ($ret.edit_frequency_keep_days)        { $efKeepDays      = [int]$ret.edit_frequency_keep_days }
    $logMaxLines     = 5000;  if ($ret.log_max_lines)                   { $logMaxLines     = [int]$ret.log_max_lines }
    $minIntervalHrs  = 24;    if ($ret.janitor_min_interval_hours)      { $minIntervalHrs  = [int]$ret.janitor_min_interval_hours }

    $marker = Join-Path $Script:SkillImproveState '.last-janitor'

    # Layer 1a: prune this session if silent and not kept.
    $sdir = Join-Path $Script:SkillImproveSessions $SessionId
    if ((Test-Path $sdir) -and (-not $HadCorrections) -and (-not $keepSilent)) {
        try { Remove-Item -Recurse -Force -Path $sdir -ErrorAction SilentlyContinue } catch {}
    }

    # Gate heavy sweeps to once every N hours.
    $now = (Get-Date).ToUniversalTime()
    $last = $null
    try {
        if (Test-Path $marker) {
            $last = [datetime]::Parse((Get-Content -Raw $marker).Trim()).ToUniversalTime()
        }
    } catch {}
    if ($last -and ($now - $last).TotalHours -lt $minIntervalHrs) { return }

    # Layer 1b: rotate log.
    try {
        if (Test-Path $Script:SkillImproveLog) {
            $lines = Get-Content -Path $Script:SkillImproveLog
            if ($lines.Count -gt $logMaxLines) {
                $lines[-$logMaxLines..-1] | Set-Content -Path $Script:SkillImproveLog -Encoding UTF8
            }
        }
    } catch {}

    # Layer 1c: trim edit-frequency.json.
    $efPath = Join-Path $Script:SkillImproveState 'edit-frequency.json'
    try {
        $ef = Get-Content -Raw $efPath | ConvertFrom-Json
        if ($ef.edits) {
            $cutoff = $now.AddDays(-1 * $efKeepDays)
            $kept = @()
            foreach ($e in $ef.edits) {
                $keep = $true
                try {
                    $ts = [datetime]::Parse($e.ts).ToUniversalTime()
                    if ($ts -lt $cutoff) { $keep = $false }
                } catch {}
                if ($keep) { $kept += $e }
            }
            if ($kept.Count -ne $ef.edits.Count) {
                $ef.edits = $kept
                $ef | ConvertTo-Json -Depth 6 | Set-Content -Path $efPath -Encoding UTF8
            }
        }
    } catch {}

    # Layer 2: sweep correction-session dirs older than keepCorrDays.
    try {
        $cutoffDate = $now.AddDays(-1 * $keepCorrDays)
        Get-ChildItem -Path $Script:SkillImproveSessions -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -lt $cutoffDate } |
            ForEach-Object {
                try { Remove-Item -Recurse -Force -Path $_.FullName -ErrorAction SilentlyContinue } catch {}
            }
    } catch {}

    try { Set-Content -Path $marker -Value $now.ToString('o') -Encoding UTF8 } catch {}
}
