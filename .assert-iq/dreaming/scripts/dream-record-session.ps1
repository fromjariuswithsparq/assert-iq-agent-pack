# Waking loop (session end): increment the session counter and append a
# one-line, dated note to today's daily log. Never blocks the agent.
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'lib\dream-utils.ps1')

if (-not (Aiq-Enabled)) { Aiq-EmitContinue; return }

$raw = Aiq-ReadStdin
$sid = Aiq-JsonField -Raw $raw -Names @('session_id','sessionId'); if (-not $sid) { $sid = 'unknown' }
$transcript = Aiq-JsonField -Raw $raw -Names @('transcript_path','transcriptPath')

Aiq-WithStateLock {
    $st = [pscustomobject]@{ last_dream_utc = $null; sessions_since_dream = 0 }
    try { if (Test-Path -LiteralPath $script:AiqDreamState) { $st = Get-Content -LiteralPath $script:AiqDreamState -Raw | ConvertFrom-Json } } catch { }
    $count = 0; if ($st.sessions_since_dream) { $count = [int]$st.sessions_since_dream }
    $out = [ordered]@{ last_dream_utc = $st.last_dream_utc; sessions_since_dream = $count + 1 }
    Set-Content -LiteralPath $script:AiqDreamState -Value ($out | ConvertTo-Json) -Encoding UTF8
}

$now = (Get-Date).ToUniversalTime()
$day = $now.ToString('yyyy-MM-dd'); $y = $now.ToString('yyyy'); $m = $now.ToString('MM')
$logDir = Join-Path $script:AiqMemoryDir "logs\$y\$m"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir "$day.md"
if (-not (Test-Path -LiteralPath $logFile)) { Set-Content -LiteralPath $logFile -Value "# Daily log $day`n" -Encoding UTF8 }
$ts = $now.ToString('yyyy-MM-ddTHH:mm:ss')
$line = if ($transcript) { "- ${ts}Z session $sid ended (transcript: $transcript)" } else { "- ${ts}Z session $sid ended" }
Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8

Aiq-EmitContinue
