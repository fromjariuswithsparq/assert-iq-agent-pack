# Validator (Windows): reads candidate-edits.json, enforces policy,
# writes candidate-edits.validated.json. Mirrors skill-improve-reflect.sh.
# Usage: skill-improve-reflect.ps1 <session-id>

param([Parameter(Mandatory=$true)][string]$SessionId)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\json-utils.ps1')

$sdir = Join-Path $Script:SkillImproveSessions $SessionId
$cand = Join-Path $sdir 'candidate-edits.json'
$icand = Join-Path $sdir 'insight-candidates.json'
if (-not (Test-Path $cand) -and -not (Test-Path $icand)) {
    Write-Error "no candidate-edits.json or insight-candidates.json at $sdir"; exit 2
}

$cfg = Get-Content -Raw -Path $Script:SkillImproveConfig | ConvertFrom-Json
$diffMax  = [int]($cfg.thresholds.diff_max_lines     | Select-Object -First 1); if (-not $diffMax) { $diffMax = 10 }
$hotWin   = [int]($cfg.thresholds.hot_skill_window_days | Select-Object -First 1); if (-not $hotWin)  { $hotWin = 7 }
$hotLimit = [int]($cfg.thresholds.hot_skill_edit_limit  | Select-Object -First 1); if (-not $hotLimit){ $hotLimit = 3 }
$minConf  = "$($cfg.thresholds.min_confidence)".ToLower(); if (-not $minConf) { $minConf = 'medium' }
$rank = @{ low=0; medium=1; high=2 }

$dismissedPath = Join-Path $Script:SkillImproveState 'dismissed-lessons.json'
$freqPath      = Join-Path $Script:SkillImproveState 'edit-frequency.json'
$recurrencePath = Join-Path $Script:SkillImproveState 'correction-recurrence.json'
$needsRewritePath = Join-Path $Script:SkillImproveState 'needs-rewrite.json'
$dismissed = @()
$editsLog  = @()
$recurrence = @{}
$needsRewrite = New-Object System.Collections.Generic.HashSet[string]
try { $dismissed = @((Get-Content -Raw $dismissedPath | ConvertFrom-Json).dismissed) } catch {}
try { $editsLog  = @((Get-Content -Raw $freqPath      | ConvertFrom-Json).edits) }       catch {}
try {
    $recObj = Get-Content -Raw $recurrencePath | ConvertFrom-Json
    if ($recObj.entries) {
        foreach ($prop in $recObj.entries.PSObject.Properties) { $recurrence[$prop.Name] = $prop.Value }
    }
} catch {}
try {
    $nr = Get-Content -Raw $needsRewritePath | ConvertFrom-Json
    foreach ($t in @($nr.targets)) { [void]$needsRewrite.Add("$t") }
} catch {}
$RecurrenceWindowDays = 30
$RecurrenceTrigger    = 2

$now = (Get-Date).ToUniversalTime()
function Test-Hot([string]$target) {
    $cutoff = $now.AddDays(-1 * $hotWin)
    $count = 0
    foreach ($e in $editsLog) {
        try { $ts = [datetime]::Parse($e.ts).ToUniversalTime() } catch { continue }
        if ($e.target_file -eq $target -and $ts -ge $cutoff) { $count++ }
    }
    return ($count -ge $hotLimit)
}
function Get-SignalEvidenceClass($c) {
    # Coarse signal classifier from candidate.evidence. See reflect.sh for parity.
    $ev = ''
    if ($c.evidence) { $ev = "$($c.evidence)".ToLower() }
    foreach ($tag in @('self_rewrite','reread_after_edit','retry_after_error')) {
        if ($ev.Contains($tag)) { return "behavioral:$tag" }
    }
    $strongMap = [ordered]@{
        'my_mistake'   = @('my mistake')
        'i_was_wrong'  = @('i was wrong')
        'correction'   = @('correction:')
        'scratch_that' = @('scratch that','strike that','i take that back','disregard that')
        'apologize'    = @('apologi')
        'missed'       = @('i missed','overlooked','oversight')
        'should_have'  = @('i should have',"i shouldn't have")
        'not_correct'  = @("that's not right","that's not correct")
    }
    foreach ($k in $strongMap.Keys) {
        foreach ($n in $strongMap[$k]) { if ($ev.Contains($n)) { return "text:strong:$k" } }
    }
    foreach ($n in @('actually','turns out','let me re','never mind','second thought','wait','hold on','instead',"won't work","doesn't work","didn't work")) {
        if ($ev.Contains($n)) { return 'text:weak' }
    }
    return 'unknown'
}

function _SiHash([string]$body) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($body))
    return (-join ($bytes | ForEach-Object { $_.ToString('x2') }))
}

function Get-Fingerprint($c) {
    # Signal-shaped: (target, qi_layer, signal_evidence_class, kind).
    $layer = ''
    if ($c.qi_layer) { $layer = "$($c.qi_layer)".ToLower() }
    $cls = Get-SignalEvidenceClass $c
    $kind = 'correction'
    if ($c.kind) { $kind = "$($c.kind)".ToLower() }
    $target = "$($c.target_file)"
    if (-not $target -and $c.target_file_suggestion) { $target = "$($c.target_file_suggestion)" }
    return (_SiHash "$target|$layer|$cls|$kind")
}

function Get-LegacyFingerprint($c) {
    $newText = ''
    if ($c.patch -and $c.patch.new_text) { $newText = "$($c.patch.new_text)".Trim().ToLower() }
    return (_SiHash "$($c.target_file)|$newText")
}

$input = if (Test-Path $cand) { Get-Content -Raw $cand | ConvertFrom-Json } else { [pscustomobject]@{ session_id = $SessionId; candidates = @(); needs_human = @() } }
$validated = New-Object System.Collections.ArrayList
$skipped   = New-Object System.Collections.ArrayList
$validModes = @('insert_after','replace','append_eof')

function Get-LineCount([string]$s) {
    if (-not $s) { return 0 }
    $hasContent = if ($s.Trim()) { 1 } else { 0 }
    return ($s.Split("`n").Length - 1) + $hasContent
}

foreach ($c in @($input.candidates)) {
    $target = "$($c.target_file)"
    $newText = ''
    $anchorText = ''
    if ($c.patch) {
        if ($c.patch.new_text)    { $newText    = "$($c.patch.new_text)" }
        if ($c.patch.anchor_text) { $anchorText = "$($c.patch.anchor_text)" }
    }
    $patchMode = ''
    if ($c.patch_mode)              { $patchMode = "$($c.patch_mode)".Trim().ToLower() }
    elseif ($c.patch -and $c.patch.mode) { $patchMode = "$($c.patch.mode)".Trim().ToLower() }
    $c | Add-Member -NotePropertyName patch_mode -NotePropertyValue $patchMode -Force

    $computed = [Math]::Max([Math]::Max((Get-LineCount $newText), (Get-LineCount $anchorText)), 1)
    $agentDiff = $c.diff_lines
    if (-not ($agentDiff -is [int]) -or $agentDiff -lt $computed) {
        $diffLines = $computed
    } else {
        $diffLines = $agentDiff
    }
    $c | Add-Member -NotePropertyName diff_lines -NotePropertyValue $diffLines -Force
    $fp = Get-Fingerprint $c
    $lfp = Get-LegacyFingerprint $c
    $c | Add-Member -NotePropertyName fingerprint -NotePropertyValue $fp -Force
    $c | Add-Member -NotePropertyName legacy_fingerprint -NotePropertyValue $lfp -Force

    $reason = $null
    if (-not $target -or -not (Test-Path $target))                                  { $reason = 'target_file_missing' }
    elseif (-not $newText.Trim())                                                   { $reason = 'empty_patch' }
    elseif ($validModes -notcontains $patchMode)                                    { $reason = 'missing_or_invalid_patch_mode (expected one of: insert_after|replace|append_eof)' }
    elseif (($patchMode -eq 'insert_after' -or $patchMode -eq 'replace') -and -not $anchorText.Trim()) { $reason = "anchor_text_required_for_$patchMode" }
    elseif ($diffLines -gt $diffMax)                                                { $reason = "diff_exceeds_cap ($diffLines>$diffMax)" }
    elseif (($dismissed -contains $fp) -or ($dismissed -contains $lfp))            { $reason = 'previously_dismissed' }
    elseif ($needsRewrite.Contains($target))                                        { $reason = 'needs_rewrite_quarantine (target previously failed automated patches; requires human rewrite)' }
    elseif ($rank[("$($c.confidence)".ToLower())] -lt $rank[$minConf])              { $reason = "confidence_below_$minConf" }
    elseif (Test-Hot $target)                                                       { $reason = "hot_skill_quarantine (>$hotLimit edits in ${hotWin}d)" }
    else {
        # Recurrence quarantine: same fingerprint applied >= trigger within window.
        $recEntry = $recurrence[$fp]
        if ($recEntry) {
            $appliedCount = [int]($recEntry.applied_count)
            $recent = $false
            try {
                $lastApplied = [datetime]::Parse("$($recEntry.last_applied_at)").ToUniversalTime()
                if ($now.Subtract($lastApplied).Days -le $RecurrenceWindowDays) { $recent = $true }
            } catch {}
            if ($recent -and $appliedCount -ge $RecurrenceTrigger) {
                $reason = "recurrence_quarantine (signal recurred after $appliedCount applied patches in ${RecurrenceWindowDays}d)"
                [void]$needsRewrite.Add($target)
            }
        }
    }

    if ($reason) {
        $c | Add-Member -NotePropertyName skip_reason -NotePropertyValue $reason -Force
        [void]$skipped.Add($c)
    } else {
        [void]$validated.Add($c)
    }
}

for ($i = 0; $i -lt $validated.Count; $i++) {
    $validated[$i] | Add-Member -NotePropertyName id -NotePropertyValue ($i + 1) -Force
}

# Persist needs-rewrite state (sticky). Locked to coordinate with concurrent
# apply/session-end writers.
try {
    $null = New-Item -ItemType Directory -Force -Path $Script:SkillImproveState -ErrorAction SilentlyContinue
    Invoke-SiWithStateLock {
        @{ targets = @($needsRewrite) } | ConvertTo-Json -Depth 4 | Set-Content -Path $needsRewritePath -Encoding UTF8
    }
} catch {}

$out = @{
    session_id   = $input.session_id
    validated_at = $now.ToString('o')
    validated    = $validated
    skipped      = $skipped
    needs_human  = $input.needs_human
    policy       = @{ diff_max_lines = $diffMax; hot_skill_window_days = $hotWin; hot_skill_edit_limit = $hotLimit; min_confidence = $minConf }
}
$out | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $sdir 'candidate-edits.validated.json') -Encoding UTF8

Write-Output ("validated: {0}  skipped: {1}  needs_human: {2}" -f $validated.Count, $skipped.Count, @($input.needs_human).Count)
foreach ($c in $validated) {
    Write-Output ("  [{0}] {1} — {2}  (conf={3}, qi={4})" -f $c.id, $c.target_file, $c.summary, $c.confidence, $c.qi_layer)
}
foreach ($c in $skipped) {
    Write-Output ("  [skip] {0} — {1}" -f $c.target_file, $c.skip_reason)
}

# ---- Insight candidates (Phase 6) ----
$ivalidated = New-Object System.Collections.ArrayList
$iskipped   = New-Object System.Collections.ArrayList
$ineeds     = New-Object System.Collections.ArrayList
if (Test-Path $icand) {
    try { $iinput = Get-Content -Raw $icand | ConvertFrom-Json } catch { $iinput = [pscustomobject]@{ candidates = @() } }
    foreach ($c in @($iinput.candidates)) {
        $kind = if ($c.kind) { "$($c.kind)".ToLower() } else { 'extend' }
        $c | Add-Member -NotePropertyName kind -NotePropertyValue $kind -Force
        $target = "$($c.target_file)"
        if (-not $target -and $c.target_file_suggestion) { $target = "$($c.target_file_suggestion)" }
        $newText = ''; $anchorText = ''
        if ($c.patch) {
            if ($c.patch.new_text)    { $newText    = "$($c.patch.new_text)" }
            if ($c.patch.anchor_text) { $anchorText = "$($c.patch.anchor_text)" }
        }
        $patchMode = ''
        if ($c.patch_mode)              { $patchMode = "$($c.patch_mode)".Trim().ToLower() }
        elseif ($c.patch -and $c.patch.mode) { $patchMode = "$($c.patch.mode)".Trim().ToLower() }
        $c | Add-Member -NotePropertyName patch_mode -NotePropertyValue $patchMode -Force
        $computed = [Math]::Max([Math]::Max((Get-LineCount $newText), (Get-LineCount $anchorText)), 1)
        $agentDiff = $c.diff_lines
        $diffLines = if (-not ($agentDiff -is [int]) -or $agentDiff -lt $computed) { $computed } else { $agentDiff }
        $c | Add-Member -NotePropertyName diff_lines -NotePropertyValue $diffLines -Force
        $fp = Get-Fingerprint $c
        $lfp = Get-LegacyFingerprint $c
        $c | Add-Member -NotePropertyName fingerprint -NotePropertyValue $fp -Force
        $c | Add-Member -NotePropertyName legacy_fingerprint -NotePropertyValue $lfp -Force

        if ($kind -eq 'create') {
            $c | Add-Member -NotePropertyName needs_human_reason -NotePropertyValue 'insight_kind_create' -Force
            [void]$ineeds.Add($c); continue
        }
        if ($kind -ne 'extend') {
            $c | Add-Member -NotePropertyName skip_reason -NotePropertyValue ("unknown_kind ($kind; expected extend|create)") -Force
            [void]$iskipped.Add($c); continue
        }

        $reason = $null
        if (-not $target -or -not (Test-Path $target))                                  { $reason = 'target_file_missing' }
        elseif (-not $newText.Trim())                                                   { $reason = 'empty_patch' }
        elseif ($validModes -notcontains $patchMode)                                    { $reason = 'missing_or_invalid_patch_mode (expected one of: insert_after|replace|append_eof)' }
        elseif (($patchMode -eq 'insert_after' -or $patchMode -eq 'replace') -and -not $anchorText.Trim()) { $reason = "anchor_text_required_for_$patchMode" }
        elseif ($diffLines -gt $diffMax)                                                { $reason = "diff_exceeds_cap ($diffLines>$diffMax)" }
        elseif (($dismissed -contains $fp) -or ($dismissed -contains $lfp))            { $reason = 'previously_dismissed' }
        elseif ($needsRewrite.Contains($target))                                        { $reason = 'needs_rewrite_quarantine' }
        elseif ($rank[("$($c.confidence)".ToLower())] -lt $rank[$minConf])              { $reason = "confidence_below_$minConf" }
        elseif (Test-Hot $target)                                                       { $reason = "hot_skill_quarantine (>$hotLimit edits in ${hotWin}d)" }
        else {
            $recEntry = $recurrence[$fp]
            if ($recEntry) {
                $appliedCount = [int]($recEntry.applied_count)
                $recent = $false
                try {
                    $lastApplied = [datetime]::Parse("$($recEntry.last_applied_at)").ToUniversalTime()
                    if ($now.Subtract($lastApplied).Days -le $RecurrenceWindowDays) { $recent = $true }
                } catch {}
                if ($recent -and $appliedCount -ge $RecurrenceTrigger) {
                    $reason = "recurrence_quarantine (signal recurred after $appliedCount applied patches in ${RecurrenceWindowDays}d)"
                }
            }
        }
        if ($reason) {
            $c | Add-Member -NotePropertyName skip_reason -NotePropertyValue $reason -Force
            [void]$iskipped.Add($c)
        } else {
            [void]$ivalidated.Add($c)
        }
    }
    for ($i = 0; $i -lt $ivalidated.Count; $i++) {
        $ivalidated[$i] | Add-Member -NotePropertyName id -NotePropertyValue ($i + 1) -Force
    }
    $iout = @{
        session_id   = $iinput.session_id
        validated_at = $now.ToString('o')
        validated    = $ivalidated
        skipped      = $iskipped
        needs_human  = $ineeds
        policy       = @{ diff_max_lines = $diffMax; min_confidence = $minConf }
    }
    $iout | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $sdir 'insight-candidates.validated.json') -Encoding UTF8

    Write-Output ("insights: validated={0} skipped={1} needs_human={2}" -f $ivalidated.Count, $iskipped.Count, $ineeds.Count)
    foreach ($c in $ivalidated) {
        Write-Output ("  [I{0}] {1} — {2}  (kind=extend, qi={3})" -f $c.id, $c.target_file, $c.summary, $c.qi_layer)
    }
    foreach ($c in $ineeds) {
        $tgt = if ($c.target_file) { $c.target_file } else { $c.target_file_suggestion }
        Write-Output ("  [needs_human] {0} — {1}  (insight, kind={2})" -f $tgt, $c.summary, $c.kind)
    }
    foreach ($c in $iskipped) {
        $tgt = if ($c.target_file) { $c.target_file } else { $c.target_file_suggestion }
        Write-Output ("  [I:skip] {0} — {1}" -f $tgt, $c.skip_reason)
    }
}

Write-SiLog "Reflect sid=$SessionId rc=0"
