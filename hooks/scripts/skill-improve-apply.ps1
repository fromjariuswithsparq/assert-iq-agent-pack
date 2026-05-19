# Applier (Windows): applies user-accepted edits with provenance + state updates.
# Usage: skill-improve-apply.ps1 <session-id> <ids|none|all>

param(
    [Parameter(Mandatory=$true)][string]$SessionId,
    [Parameter(Mandatory=$true)][string]$Selection
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\json-utils.ps1')

$sdir = Join-Path $Script:SkillImproveSessions $SessionId
$validatedPath = Join-Path $sdir 'candidate-edits.validated.json'
$iValidatedPath = Join-Path $sdir 'insight-candidates.validated.json'
if (-not (Test-Path $validatedPath) -and -not (Test-Path $iValidatedPath)) {
    Write-Error "no validated file at $sdir"; exit 2
}

# Dry-run: "diff N" prints the patch for candidate N (or "I N" for insight).
if ($Selection -match '^\s*diff\s+(I?\d+)\s*$') {
    $rawId = $Matches[1]
    $isInsight = $rawId.StartsWith('I') -or $rawId.StartsWith('i')
    $num = if ($isInsight) { [int]$rawId.Substring(1) } else { [int]$rawId }
    $src = if ($isInsight) { $iValidatedPath } else { $validatedPath }
    if (-not (Test-Path $src)) { Write-Output "no validated file for id=$rawId"; exit 2 }
    $vv = Get-Content -Raw $src | ConvertFrom-Json
    $match = $vv.validated | Where-Object { [int]$_.id -eq $num } | Select-Object -First 1
    if (-not $match) { Write-Output "no validated candidate with id=$rawId"; exit 2 }
    $label = if ($isInsight) { "I$num" } else { "$num" }
    Write-Output "=== diff for candidate #$label ==="
    Write-Output ("target_file : {0}" -f $match.target_file)
    Write-Output ("patch_mode  : {0}" -f $match.patch_mode)
    Write-Output ("confidence  : {0}   qi_layer: {1}" -f $match.confidence, $match.qi_layer)
    if ($isInsight) { Write-Output ("kind        : {0}" -f $match.kind) }
    Write-Output ("diff_lines  : {0}" -f $match.diff_lines)
    Write-Output ("summary     : {0}" -f $match.summary)
    Write-Output "--- anchor_text ---"
    if ($match.patch -and $match.patch.anchor_text) { Write-Output "$($match.patch.anchor_text)" } else { Write-Output "(none)" }
    Write-Output "--- new_text ---"
    if ($match.patch -and $match.patch.new_text) { Write-Output "$($match.patch.new_text)" } else { Write-Output "(none)" }
    Write-Output "=== end diff (no changes applied) ==="
    Write-SiLog "Apply sid=$SessionId sel='diff $rawId' (dry-run)"
    exit 0
}

$v  = if (Test-Path $validatedPath)  { Get-Content -Raw $validatedPath  | ConvertFrom-Json } else { [pscustomobject]@{ validated = @(); needs_human = @() } }
$vi = if (Test-Path $iValidatedPath) { Get-Content -Raw $iValidatedPath | ConvertFrom-Json } else { [pscustomobject]@{ validated = @(); needs_human = @() } }
$corrValidated = @($v.validated)  | ForEach-Object { $_ | Add-Member -NotePropertyName _source -NotePropertyValue 'correction' -Force -PassThru }
$insValidated  = @($vi.validated) | ForEach-Object { $_ | Add-Member -NotePropertyName _source -NotePropertyValue 'insight'    -Force -PassThru }
$validated = @($corrValidated) + @($insValidated)

$sel = $Selection.Trim().ToLower()
$acceptCorrIds = @()
$acceptInsIds  = @()
if ($sel -eq 'all') {
    $acceptCorrIds = $corrValidated | ForEach-Object { [int]$_.id }
    $acceptInsIds  = $insValidated  | ForEach-Object { [int]$_.id }
} elseif ($sel -eq 'none') {
    # nothing
} else {
    $invalidTokens = @()
    $seenAny = $false
    foreach ($p in $sel.Split(',')) {
        $p = $p.Trim()
        if (-not $p) { continue }
        $seenAny = $true
        if ($p -match '^i(\d+)$') { $acceptInsIds += [int]$Matches[1] }
        elseif ($p -match '^\d+$') { $acceptCorrIds += [int]$p }
        else { $invalidTokens += $p }
    }
    if ((-not $seenAny) -or $invalidTokens.Count -gt 0) {
        $bad = if ($invalidTokens.Count -gt 0) { ($invalidTokens -join ', ') } else { $sel }
        Write-Error "invalid selection: $bad. Use 'all', 'none', comma-separated numeric ids, or insight ids prefixed with 'i'."
        exit 2
    }
}

$date = (Get-Date).ToString('yyyy-MM-dd')
$applied  = New-Object System.Collections.ArrayList
$rejected = New-Object System.Collections.ArrayList
$validModes = @('insert_after','replace','append_eof')

function Get-FrontmatterEndOffset([string]$content) {
    if (-not $content.StartsWith('---')) { return 0 }
    $nl = $content.IndexOf("`n")
    if ($nl -lt 0) { return 0 }
    $firstLine = $content.Substring(0, $nl).Trim()
    if ($firstLine -ne '---') { return 0 }
    $rest = $content.Substring($nl)
    $m = [regex]::Match($rest, "`n---[ `t]*(`n|`$)")
    if (-not $m.Success) { return 0 }
    return $nl + $m.Index + $m.Length
}

foreach ($c in $validated) {
    $src = if ($c._source) { "$($c._source)" } else { 'correction' }
    $acceptSet = if ($src -eq 'insight') { $acceptInsIds } else { $acceptCorrIds }
    if ($acceptSet -notcontains [int]$c.id) { [void]$rejected.Add($c); continue }
    $target  = "$($c.target_file)"
    $anchor  = ''
    $newText = ''
    if ($c.patch) {
        if ($c.patch.anchor_text) { $anchor  = "$($c.patch.anchor_text)" }
        if ($c.patch.new_text)    { $newText = "$($c.patch.new_text)" }
    }
    $patchMode = ''
    if ($c.patch_mode)              { $patchMode = "$($c.patch_mode)".Trim().ToLower() }
    elseif ($c.patch -and $c.patch.mode) { $patchMode = "$($c.patch.mode)".Trim().ToLower() }

    if ($validModes -notcontains $patchMode) {
        $c | Add-Member -NotePropertyName apply_error -NotePropertyValue "invalid patch_mode at apply: '$patchMode'" -Force
        [void]$rejected.Add($c); continue
    }
    if (-not (Test-Path $target)) {
        $c | Add-Member -NotePropertyName apply_error -NotePropertyValue 'target missing at apply time' -Force
        [void]$rejected.Add($c); continue
    }
    try {
        $content = Get-Content -Raw -Path $target -ErrorAction Stop
    } catch {
        $c | Add-Member -NotePropertyName apply_error -NotePropertyValue "read failed: $_" -Force
        [void]$rejected.Add($c); continue
    }

    $provMarker = if ($src -eq 'insight') {
        "<!-- self-improve (insight): session $SessionId, $date -->"
    } else {
        "<!-- self-improve: session $SessionId, $date -->"
    }
    # Dedup: if this exact session+date marker already exists in the file (a
    # prior patch in the same apply run wrote one), drop the marker for this
    # patch — one provenance comment per (target,session) is enough.
    $prov = if ($content.Contains($provMarker)) { '' } else { "`n$provMarker" }
    $fmEnd = Get-FrontmatterEndOffset $content

    if ($patchMode -eq 'insert_after' -or $patchMode -eq 'replace') {
        if (-not $anchor) {
            $c | Add-Member -NotePropertyName apply_error -NotePropertyValue "anchor_text required for $patchMode" -Force
            [void]$rejected.Add($c); continue
        }
        $anchorPos = $content.IndexOf($anchor)
        if ($anchorPos -lt 0) {
            $c | Add-Member -NotePropertyName apply_error -NotePropertyValue 'anchor_not_found' -Force
            [void]$rejected.Add($c); continue
        }
        if ($anchorPos -lt $fmEnd) {
            $c | Add-Member -NotePropertyName apply_error -NotePropertyValue 'patch_inside_frontmatter' -Force
            [void]$rejected.Add($c); continue
        }
        if ($patchMode -eq 'insert_after') {
            $replacement = $anchor + "`n" + $newText.TrimEnd() + $prov
        } else {
            $replacement = $newText.TrimEnd() + $prov
        }
        $updated = $content.Substring(0, $anchorPos) + $replacement + $content.Substring($anchorPos + $anchor.Length)
    } else {
        # append_eof
        $sep = if ($content.EndsWith("`n")) { '' } else { "`n" }
        $updated = $content + $sep + $newText.TrimEnd() + $prov + "`n"
    }

    try {
        Set-Content -Path $target -Value $updated -Encoding UTF8 -NoNewline
        $c | Add-Member -NotePropertyName applied_at -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o')) -Force
        [void]$applied.Add($c)
    } catch {
        $c | Add-Member -NotePropertyName apply_error -NotePropertyValue "write failed: $_" -Force
        [void]$rejected.Add($c)
    }
}

$dismissedPath = Join-Path $Script:SkillImproveState 'dismissed-lessons.json'
$freqPath      = Join-Path $Script:SkillImproveState 'edit-frequency.json'
$recurrencePath = Join-Path $Script:SkillImproveState 'correction-recurrence.json'
Invoke-SiWithStateLock {
$ds = @{ dismissed = @() }; $fq = @{ edits = @() }
try { $ds = Get-Content -Raw $dismissedPath | ConvertFrom-Json } catch {}
try { $fq = Get-Content -Raw $freqPath      | ConvertFrom-Json } catch {}
if (-not $ds.dismissed) { $ds | Add-Member -NotePropertyName dismissed -NotePropertyValue @() -Force }
if (-not $fq.edits)     { $fq | Add-Member -NotePropertyName edits     -NotePropertyValue @() -Force }

foreach ($c in $rejected) {
    if ($c.apply_error) { continue }
    $fp = "$($c.fingerprint)"
    if ($fp -and ($ds.dismissed -notcontains $fp)) { $ds.dismissed += $fp }
}
foreach ($c in $applied) {
    $fq.edits += @{
        ts          = $c.applied_at
        session_id  = $SessionId
        target_file = $c.target_file
        summary     = "$($c.summary)"
        fingerprint = "$($c.fingerprint)"
    }
}

# Recurrence tracking — parity with apply.sh. Same fingerprint applied >= 2
# times in 30 days triggers needs-rewrite quarantine in reflect.
$rec = @{ entries = @{} }
try { $rec = Get-Content -Raw $recurrencePath | ConvertFrom-Json } catch {}
if (-not $rec.entries) { $rec | Add-Member -NotePropertyName entries -NotePropertyValue (@{}) -Force }
$entries = @{}
# Carry forward existing entries into a hashtable for mutation.
if ($rec.entries) {
    foreach ($prop in $rec.entries.PSObject.Properties) {
        $entries[$prop.Name] = $prop.Value
    }
}
foreach ($c in $applied) {
    $fp = "$($c.fingerprint)"; if (-not $fp) { continue }
    $existing = $entries[$fp]
    if (-not $existing) { $existing = [pscustomobject]@{ target_file = "$($c.target_file)"; applied_count = 0; history = @() } }
    $existing.target_file    = "$($c.target_file)"
    $existing.applied_count  = [int]($existing.applied_count) + 1
    $existing | Add-Member -NotePropertyName last_applied_at -NotePropertyValue "$($c.applied_at)" -Force
    $newHist = @($existing.history) + @(@{ ts = "$($c.applied_at)"; session_id = $SessionId })
    if ($newHist.Count -gt 10) { $newHist = $newHist[($newHist.Count - 10)..($newHist.Count - 1)] }
    $existing.history = $newHist
    $entries[$fp] = $existing
}
@{ entries = $entries } | ConvertTo-Json -Depth 10 | Set-Content -Path $recurrencePath -Encoding UTF8

$ds | ConvertTo-Json -Depth 6 | Set-Content -Path $dismissedPath -Encoding UTF8
$fq | ConvertTo-Json -Depth 6 | Set-Content -Path $freqPath      -Encoding UTF8
}  # end Invoke-SiWithStateLock

$decisions = @{
    session_id = $SessionId
    decided_at = (Get-Date).ToUniversalTime().ToString('o')
    selection  = $sel
    applied    = $applied
    rejected   = $rejected
}
$decisions | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $sdir 'decisions.json') -Encoding UTF8

$errCount = ($rejected | Where-Object { $_.apply_error }).Count
$dismCount = ($rejected | Where-Object { -not $_.apply_error }).Count
Write-Output ("applied: {0}  rejected/dismissed: {1}  errors: {2}" -f $applied.Count, $dismCount, $errCount)
$needsHuman = @(@($v.needs_human) + @($vi.needs_human))
if ($needsHuman.Count -gt 0) {
    Write-Output ("needs_human: {0}  (not auto-applied)" -f $needsHuman.Count)
    foreach ($nh in $needsHuman) {
        $tgt = if ($nh.target_file) { $nh.target_file } elseif ($nh.target_file_suggestion) { $nh.target_file_suggestion } else { '?' }
        $reason = if ($nh.reason) { $nh.reason } elseif ($nh.needs_human_reason) { $nh.needs_human_reason } else { "$($nh.summary)" }
        $kindTag = if ($nh.kind) { " (insight, kind=$($nh.kind))" } else { '' }
        Write-Output ("  [needs_human] {0} — {1}{2}" -f $tgt, $reason, $kindTag)
    }
}
foreach ($c in $applied)  {
    $label = if ($c._source -eq 'insight') { "I$($c.id)" } else { "$($c.id)" }
    Write-Output ("  [applied {0}] {1} — {2}" -f $label, $c.target_file, $c.summary)
}
foreach ($c in $rejected) {
    $label = if ($c._source -eq 'insight') { "I$($c.id)" } else { "$($c.id)" }
    if ($c.apply_error) { Write-Output ("  [error {0}]   {1} — {2}" -f $label, $c.target_file, $c.apply_error) }
    else                { Write-Output ("  [dismissed {0}] {1} — {2}" -f $label, $c.target_file, $c.summary) }
}
Write-SiLog "Apply sid=$SessionId sel=$sel rc=0"
