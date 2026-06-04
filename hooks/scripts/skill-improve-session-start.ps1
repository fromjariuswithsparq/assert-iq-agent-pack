# SessionStart hook (Windows): snapshot candidate SKILL.md / instructions.md files.
# Never blocks; logs to %USERPROFILE%\.agents\hooks\logs\skill-improve.log.

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'lib\json-utils.ps1')

try {
    if (-not (Test-SiEnabled)) { Send-SiContinue; exit 0 }

    $raw = Read-SiStdin
    Invoke-SiDedupOrExit -Event 'SessionStart' -Raw $raw
    $sid = Get-SiSessionId -Raw $raw
    $sdir = Get-SiSessionDir -SessionId $sid

    $cfg = $null
    try { $cfg = Get-Content -Raw -Path $Script:SkillImproveConfig | ConvertFrom-Json } catch {}

    $roots = @()
    # Prefer customization_roots; fall back to legacy skill_roots for back-compat.
    $rootList = $null
    if ($cfg.customization_roots) { $rootList = $cfg.customization_roots }
    elseif ($cfg.skill_roots) { $rootList = $cfg.skill_roots }
    if ($rootList) {
        foreach ($r in $rootList) {
            $expanded = $r -replace '^~', $env:USERPROFILE
            $expanded = $expanded -replace '/', '\'
            $roots += $expanded
        }
    }
    $patterns = @('SKILL.md','*.instructions.md','*.prompt.md','copilot-instructions.md','AGENTS.md')
    if ($cfg.customization_file_patterns) { $patterns = @($cfg.customization_file_patterns) }
    elseif ($cfg.skill_file_patterns) { $patterns = @($cfg.skill_file_patterns) }

    $found = New-Object System.Collections.ArrayList
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($pat in $patterns) {
            Get-ChildItem -Path $root -Recurse -Filter $pat -ErrorAction SilentlyContinue |
                Where-Object {
                    $p = $_.FullName
                    -not ($p -match '\\\.git\\' -or $p -match '\\node_modules\\' -or $p -match '\\bin\\' -or $p -match '\\obj\\')
                } | ForEach-Object {
                    [void]$found.Add(@{
                        path  = $_.FullName
                        size  = $_.Length
                        mtime = ([DateTimeOffset]$_.LastWriteTimeUtc).ToUnixTimeSeconds()
                    })
                }
        }
    }

    $transcript = ''
    $source = ''
    try {
        if ($raw) {
            $d = $raw | ConvertFrom-Json -ErrorAction Stop
            if ($d.transcript_path) { $transcript = $d.transcript_path }
            elseif ($d.transcriptPath) { $transcript = $d.transcriptPath }
            if ($d.source) { $source = $d.source }
        }
    } catch {}

    $out = @{
        session_id      = $sid
        captured_at     = (Get-Date).ToUniversalTime().ToString('o')
        transcript_path = $transcript
        source          = $source
        cwd             = (Get-Location).Path
        customization_files = $found
    }
    $out | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $sdir 'loaded-customizations.json') -Encoding UTF8
    Write-SiLog "SessionStart sid=$sid dir=$sdir"
} catch {
    Write-SiLog "SessionStart error: $_"
}

Send-SiContinue
