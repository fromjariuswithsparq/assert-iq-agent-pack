# Correction-signature heuristics (PowerShell side).
# Dot-sourced by skill-improve-session-end.ps1 after json-utils.ps1.

function Get-SiAssistantTextHits {
    param([string]$TranscriptPath)
    if (-not (Test-Path $TranscriptPath)) { return @() }

    # patterns: list of @{ regex; weight; raw }
    $patterns = New-Object System.Collections.ArrayList
    try {
        $cfg = Get-Content -Raw -Path $Script:SkillImproveConfig | ConvertFrom-Json
        foreach ($entry in @($cfg.correction_signatures.assistant_text_regex)) {
            if ($entry -is [string]) {
                [void]$patterns.Add(@{ regex = [regex]::new($entry, 'IgnoreCase'); weight = 'weak'; raw = $entry })
            } elseif ($entry.pattern) {
                $w = if ($entry.weight) { "$($entry.weight)" } else { 'weak' }
                if ($w -ne 'strong' -and $w -ne 'weak') { $w = 'weak' }
                [void]$patterns.Add(@{ regex = [regex]::new($entry.pattern, 'IgnoreCase'); weight = $w; raw = $entry.pattern })
            }
        }
    } catch {}

    if ($patterns.Count -eq 0) { return @() }

    $hits = New-Object System.Collections.ArrayList
    $i = 0
    Get-Content -Path $TranscriptPath -ErrorAction SilentlyContinue | ForEach-Object {
        $i++
        $line = $_.Trim()
        if (-not $line) { return }
        $text = ''
        $role = ''
        try {
            $rec = $line | ConvertFrom-Json -ErrorAction Stop
            if ($rec.role) { $role = "$($rec.role)".ToLower() }
            elseif ($rec.type) { $role = "$($rec.type)".ToLower() }
            elseif ($rec.message -and $rec.message.role) { $role = "$($rec.message.role)".ToLower() }

            $content = $rec.content
            if (-not $content -and $rec.message) { $content = $rec.message.content }
            if (-not $content) { $content = $rec.text }
            if ($content -is [array]) {
                $text = ($content | ForEach-Object { if ($_.text) { $_.text } else { "$_" } }) -join ' '
            } else { $text = "$content" }
        } catch {
            $text = $line
        }
        if ($role -and ($role -notin @('assistant','agent','model'))) { return }
        foreach ($p in $patterns) {
            $m = $p.regex.Match($text)
            if ($m.Success) {
                $snippet = $text.Substring(0, [Math]::Min(240, $text.Length))
                $matchTxt = $m.Value.Substring(0, [Math]::Min(80, $m.Value.Length))
                [void]$hits.Add(@{ line = $i; snippet = $snippet; weight = $p.weight; pattern = $p.raw; match = $matchTxt })
                break  # one hit per line, avoid double-counting
            }
        }
    }
    return $hits
}

function Get-SiToolLogHits {
    param([string]$LogPath)
    if (-not (Test-Path $LogPath)) { return @() }

    $rereadWindow = 3
    $selfEditWindow = 2
    try {
        $cfg = Get-Content -Raw -Path $Script:SkillImproveConfig | ConvertFrom-Json
        if ($cfg.correction_signatures.tool_patterns.reread_window_turns) {
            $rereadWindow = [int]$cfg.correction_signatures.tool_patterns.reread_window_turns
        }
        if ($cfg.correction_signatures.tool_patterns.self_edit_window_turns) {
            $selfEditWindow = [int]$cfg.correction_signatures.tool_patterns.self_edit_window_turns
        }
    } catch {}

    $entries = @()
    Get-Content -Path $LogPath -ErrorAction SilentlyContinue | ForEach-Object {
        $l = $_.Trim()
        if (-not $l) { return }
        try { $entries += ($l | ConvertFrom-Json -ErrorAction Stop) } catch {}
    }

    $hits = New-Object System.Collections.ArrayList
    $reads = @{}; $edits = @{}
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $e = $entries[$i]
        if (-not $e.file) { continue }
        # VS Code: read_file / replace_string_in_file / multi_replace_string_in_file / create_file
        # Claude Code: Read / Edit / MultiEdit / Write
        if ($e.tool -in @('read_file','Read')) {
            if (-not $reads[$e.file]) { $reads[$e.file] = @() }
            $reads[$e.file] += $i
        } elseif ($e.tool -in @('replace_string_in_file','multi_replace_string_in_file','create_file','Edit','MultiEdit','Write')) {
            if (-not $edits[$e.file]) { $edits[$e.file] = @() }
            $edits[$e.file] += $i
        }
    }

    # Behavioral-context downgrade: if the agent did substantive other work
    # between the edit and the re-read / self-rewrite, downgrade to weak.
    function Get-InterveningOtherFiles($startIdx, $endIdx, $targetF) {
        $others = New-Object System.Collections.Generic.HashSet[string]
        for ($k = $startIdx + 1; $k -lt $endIdx; $k++) {
            if ($k -lt 0 -or $k -ge $entries.Count) { continue }
            $of = "$($entries[$k].file)"
            if ($of -and $of -ne $targetF) { [void]$others.Add($of) }
        }
        return $others.Count
    }

    foreach ($f in $edits.Keys) {
        $eidxs = $edits[$f]; $ridxs = $reads[$f]
        if (-not $ridxs) { continue }
        foreach ($ei in $eidxs) {
            foreach ($ri in $ridxs) {
                if (($ri - $ei) -gt 0 -and ($ri - $ei) -le $rereadWindow) {
                    $w = if ((Get-InterveningOtherFiles $ei $ri $f) -ge 2) { 'weak' } else { 'behavioral' }
                    [void]$hits.Add(@{ type='reread_after_edit'; file=$f; edit_idx=$ei; read_idx=$ri; weight=$w }); break
                }
            }
        }
    }
    foreach ($f in $edits.Keys) {
        $eidxs = $edits[$f]
        for ($i = 0; $i -lt $eidxs.Count - 1; $i++) {
            if (($eidxs[$i+1] - $eidxs[$i]) -gt 0 -and ($eidxs[$i+1] - $eidxs[$i]) -le $selfEditWindow) {
                $w = if ((Get-InterveningOtherFiles $eidxs[$i] $eidxs[$i+1] $f) -ge 2) { 'weak' } else { 'behavioral' }
                [void]$hits.Add(@{ type='self_rewrite'; file=$f; first_idx=$eidxs[$i]; second_idx=$eidxs[$i+1]; weight=$w })
            }
        }
    }
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $e = $entries[$i]
        if ($e.error -and ($i + 1) -lt $entries.Count) {
            $n = $entries[$i+1]
            if ($e.file -and $n.file -eq $e.file) {
                [void]$hits.Add(@{ type='retry_after_error'; file=$e.file; idx=$i; weight='behavioral' })
            }
        }
    }
    return $hits
}

# Scan transcript ($TranscriptPath) for proactive-insight markers — unsolicited
# observations about latent flaws. Parity with si_scan_proactive_insights in
# the bash side. When proactive_insights.require_file_reference is true
# (default), only counts hits with a co-occurring path-like token; that token
# is attached as `file_ref`.
function Get-SiProactiveInsightHits {
    param([string]$TranscriptPath)
    $hits = New-Object System.Collections.ArrayList
    if (-not (Test-Path $TranscriptPath)) { return ,$hits }
    $patterns = @()
    $requireFile = $true
    try {
        $cfg = Get-Content -Raw -Path $Script:SkillImproveConfig | ConvertFrom-Json
        $pi = $cfg.proactive_insights
        if (-not $pi) { return ,$hits }
        if ($null -ne $pi.enabled -and -not [bool]$pi.enabled) { return ,$hits }
        if ($null -ne $pi.require_file_reference) { $requireFile = [bool]$pi.require_file_reference }
        foreach ($entry in @($pi.proactive_insight_regex)) {
            if ($entry -and $entry.pattern) {
                $w = if ($entry.weight) { "$($entry.weight)" } else { 'weak' }
                if ($w -ne 'strong' -and $w -ne 'weak') { $w = 'weak' }
                $patterns += ,@{
                    rx      = [regex]::new("$($entry.pattern)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    weight  = $w
                    raw     = "$($entry.pattern)"
                }
            }
        }
    } catch { return ,$hits }
    if ($patterns.Count -eq 0) { return ,$hits }

    $fileRx = [regex]::new('(?:[\w./~-]+\.(?:md|cs|ts|tsx|js|jsx|py|yml|yaml|sh|ps1|json|cshtml|xaml|sql|rb|go|rs|java|kt))|(?:~?/[\w./-]+/[\w./-]+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $lineNum = 0
    foreach ($line in [System.IO.File]::ReadLines($TranscriptPath)) {
        $lineNum++
        if (-not $line) { continue }
        $text = ''
        $role = ''
        try {
            $rec = $line | ConvertFrom-Json
            $role = "$(($rec.role) -as [string])$(($rec.type) -as [string])"
            if ($null -ne $rec.message -and $null -ne $rec.message.role) { $role = "$($rec.message.role)" }
            $content = if ($rec.content) { $rec.content }
                       elseif ($rec.message -and $rec.message.content) { $rec.message.content }
                       elseif ($rec.text) { $rec.text } else { '' }
            if ($content -is [System.Collections.IEnumerable] -and -not ($content -is [string])) {
                $text = (@($content) | ForEach-Object {
                    if ($_ -is [string]) { $_ } elseif ($_.text) { "$($_.text)" } else { '' }
                }) -join ' '
            } else {
                $text = "$content"
            }
        } catch {
            $text = $line
        }
        $role = $role.ToLower()
        if ($role -and $role -notin @('assistant', 'agent', 'model')) { continue }
        $fileMatch = $fileRx.Match($text)
        $fileRef = if ($fileMatch.Success) { $fileMatch.Value } else { '' }
        if ($requireFile -and -not $fileRef) { continue }
        foreach ($p in $patterns) {
            $m = $p.rx.Match($text)
            if ($m.Success) {
                $snippet = if ($text.Length -gt 240) { $text.Substring(0, 240) } else { $text }
                $matchStr = if ($m.Value.Length -gt 80) { $m.Value.Substring(0, 80) } else { $m.Value }
                [void]$hits.Add(@{
                    line     = $lineNum
                    snippet  = $snippet
                    weight   = $p.weight
                    pattern  = $p.raw
                    match    = $matchStr
                    file_ref = $fileRef
                })
                break
            }
        }
    }
    return ,$hits
}
