# Stop hook (Windows): at end of session, scan for correction signals
# and inject an agent task block if any are found.

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'lib\json-utils.ps1')
. (Join-Path $PSScriptRoot 'lib\correction-signatures.ps1')

$emit = '{"continue":true}'

try {
    if (-not (Test-SiEnabled)) { Write-Output $emit; exit 0 }

    $raw = Read-SiStdin
    Invoke-SiDedupOrExit -Event 'Stop' -Raw $raw
    $sid = Get-SiSessionId -Raw $raw
    $sdir = Get-SiSessionDir -SessionId $sid

    # Avoid recursion.
    try {
        if ($raw) {
            $d = $raw | ConvertFrom-Json -ErrorAction Stop
            if ($d.stop_hook_active) { Write-Output $emit; exit 0 }
        }
    } catch {}

    $transcript = ''
    try {
        if ($raw) {
            $d = $raw | ConvertFrom-Json -ErrorAction Stop
            if ($d.transcript_path) { $transcript = $d.transcript_path }
            elseif ($d.transcriptPath) { $transcript = $d.transcriptPath }
        }
    } catch {}

    $toolLog = Join-Path $sdir 'tool-log.jsonl'
    $textHits = Get-SiAssistantTextHits -TranscriptPath $transcript
    $toolHits = Get-SiToolLogHits -LogPath $toolLog
    # Proactive-insight pass (parallel to corrections). Honors
    # SKILL_IMPROVE_INSIGHTS_DISABLED=1 as a kill-switch.
    if ($env:SKILL_IMPROVE_INSIGHTS_DISABLED -eq '1') {
        $insightHits = @()
    } else {
        $insightHits = Get-SiProactiveInsightHits -TranscriptPath $transcript
    }

    # Weighted-score gate. Sum hit weights from config trigger.weights;
    # fires when total >= trigger.min_score. SKILL_IMPROVE_TRIGGER_ANY=1
    # restores legacy any-hit behavior. SKILL_IMPROVE_MIN_SCORE=<int> overrides
    # the configured min_score (debugging / tuning aid).
    $corrGate = $false
    $insightGate = $false
    if ($env:SKILL_IMPROVE_TRIGGER_ANY -eq '1') {
        $corrGate    = (($textHits.Count + $toolHits.Count) -gt 0)
        $insightGate = ($insightHits.Count -gt 0)
    } else {
        $minScore = 2
        $sw = 2; $ww = 1; $bw = 2
        $piMin = 3; $psw = 2; $pww = 1
        try {
            $cfgT = Get-Content -Raw -Path $Script:SkillImproveConfig | ConvertFrom-Json
            $trig = $cfgT.correction_signatures.trigger
            if ($trig) {
                if ($null -ne $trig.min_score) { $minScore = [int]$trig.min_score }
                if ($trig.weights) {
                    if ($null -ne $trig.weights.strong)     { $sw = [int]$trig.weights.strong }
                    if ($null -ne $trig.weights.weak)       { $ww = [int]$trig.weights.weak }
                    if ($null -ne $trig.weights.behavioral) { $bw = [int]$trig.weights.behavioral }
                }
            }
            $piTrig = $cfgT.proactive_insights.trigger
            if ($piTrig) {
                if ($null -ne $piTrig.min_score) { $piMin = [int]$piTrig.min_score }
                if ($piTrig.weights) {
                    if ($null -ne $piTrig.weights.strong) { $psw = [int]$piTrig.weights.strong }
                    if ($null -ne $piTrig.weights.weak)   { $pww = [int]$piTrig.weights.weak }
                }
            }
        } catch {}
        if ($env:SKILL_IMPROVE_MIN_SCORE) {
            try { $minScore = [int]$env:SKILL_IMPROVE_MIN_SCORE } catch {}
        }
        $total = 0
        foreach ($h in $textHits) {
            $w = if ($h.weight) { "$($h.weight)" } else { 'weak' }
            $total += @{ 'strong' = $sw; 'weak' = $ww; 'behavioral' = $bw }[$w]
        }
        foreach ($h in $toolHits) {
            $w = if ($h.weight) { "$($h.weight)" } else { 'behavioral' }
            $total += @{ 'strong' = $sw; 'weak' = $ww; 'behavioral' = $bw }[$w]
        }
        $corrGate = ($total -ge $minScore)
        $piTotal = 0
        foreach ($h in $insightHits) {
            $w = if ($h.weight) { "$($h.weight)" } else { 'weak' }
            $piTotal += @{ 'strong' = $psw; 'weak' = $pww }[$w]
        }
        $insightGate = ($piTotal -ge $piMin)
    }
    $hasHits = ($corrGate -or $insightGate)
    $silent = $true
    try {
        $cfg = Get-Content -Raw -Path $Script:SkillImproveConfig | ConvertFrom-Json
        if ($null -ne $cfg.behavior.silent_on_zero_corrections) {
            $silent = [bool]$cfg.behavior.silent_on_zero_corrections
        }
    } catch {}

    if (-not $hasHits) {
        Invoke-SiJanitor -SessionId $sid -HadCorrections $false
        if ($silent) {
            Write-SiLog "Stop sid=$sid no-corrections silent (janitor ran)"
            Write-Output $emit; exit 0
        }
        $emit = '{"continue":true,"systemMessage":"skill-improve: no corrections detected this session."}'
        Write-SiLog "Stop sid=$sid no-corrections announced (janitor ran)"
        Write-Output $emit; exit 0
    }

    $signals = @{
        session_id          = $sid
        captured_at         = (Get-Date).ToUniversalTime().ToString('o')
        transcript_path     = $transcript
        assistant_text_hits = $textHits
        tool_log_hits       = $toolHits
        insight_hits        = $insightHits
        gates               = @{ correction = $corrGate; insight = $insightGate }
    }
    $signals | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $sdir 'signals.json') -Encoding UTF8

    # Compute invoked-customizations.json from tool-log.jsonl.
    $invoked = New-Object System.Collections.ArrayList
    $seen = @{}
    $loadedFiles = @()
    try {
        $loadedPath = Join-Path $sdir 'loaded-customizations.json'
        if (Test-Path $loadedPath) {
            $loaded = Get-Content -Raw $loadedPath | ConvertFrom-Json
            if ($loaded.customization_files) { $loadedFiles = @($loaded.customization_files) }
            elseif ($loaded.skill_files)     { $loadedFiles = @($loaded.skill_files) }
        }
    } catch {}
    $toolLogPath = Join-Path $sdir 'tool-log.jsonl'
    if (Test-Path $toolLogPath) {
        Get-Content -Path $toolLogPath -ErrorAction SilentlyContinue | ForEach-Object {
            $ln = $_.Trim()
            if (-not $ln) { return }
            try {
                $rec = $ln | ConvertFrom-Json -ErrorAction Stop
                $f_ = "$($rec.file)"
                if (-not $f_) { return }
                $inv = [bool]$rec.customization_invoked
                if (-not $inv -and $rec.tool -eq 'read_file' -and ($loadedFiles -contains $f_)) { $inv = $true }
                if ($inv -and -not $seen.ContainsKey($f_)) {
                    $seen[$f_] = $true
                    [void]$invoked.Add(@{ file = $f_; first_invoked_at = "$($rec.ts)" })
                }
            } catch {}
        }
    }
    $invOut = @{ session_id = $sid; invoked = $invoked; invoked_count = $invoked.Count }
    $invOut | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $sdir 'invoked-customizations.json') -Encoding UTF8

    $scriptDir = $PSScriptRoot
    $taskBlock = @"
SKILL-IMPROVE: $sid

Correction signals were detected during this session. Do the following BEFORE closing the conversation:

1. Read these files:
   - $sdir\loaded-customizations.json   (skills/instructions/prompts/agents in scope this session)
   - $sdir\invoked-customizations.json  (subset actually read/touched this session — attribute against these FIRST)
   - $sdir\signals.json                 (detected correction signals)
   - $sdir\tool-log.jsonl               (raw tool activity)

2. For each meaningful correction, identify the single most likely source customization file that SHOULD have prevented it. Prefer files listed in invoked-customizations.json (the agent actually read them this session); only fall back to the full loaded-customizations.json set if no invoked file is a plausible owner. Classify each via the qi-foundation 4 layers (change-risk / protection / signal-trust / outcome-evidence) to help route.

3. Draft a minimal patch per target file:
   - Single-bullet additions or single-line fixes only.
   - Diff must be <= 10 lines total per file (hard cap).
   - Reject anything requiring restructuring — those go on a "needs human authoring" list, not the patch list.

4. Write candidate-edits.json to: $sdir\candidate-edits.json
   Schema:
   {
     "session_id": "$sid",
     "candidates": [
       {
         "id": 1,
         "target_file": "<absolute path>",
         "confidence": "high|medium|low",
         "qi_layer": "change-risk|protection|signal-trust|outcome-evidence",
         "summary": "<one line>",
         "patch_mode": "insert_after|replace|append_eof",
         "patch": { "anchor_text": "<verbatim existing snippet; required unless append_eof>", "new_text": "<replacement or insertion>" },
         "diff_lines": <int; will be recomputed by reflect as max(new_lines, anchor_lines)>,
         "evidence": "<which signal fired>"
       }
     ],
     "needs_human": [ { "target_file": "...", "reason": "..." } ]
   }

$(if ($insightGate) { @"
4b. PROACTIVE INSIGHTS DETECTED. signals.json -> insight_hits contains assistant
    observations about latent flaws ("consider X", "would be safer to Y", etc).
    These are unsolicited — there is no self-error trail — so they need a
    different judgment than corrections.

    For each meaningful insight, draft an entry. Two kinds:
      - "kind":"extend" — the observation maps cleanly into an existing
        customization listed in invoked-customizations.json or
        loaded-customizations.json. Same diff cap applies (<=10 lines). These
        flow through the standard reflect gates and can be auto-applied.
      - "kind":"create" — the observation describes a recurring concern that
        does NOT fit any existing customization. Suggest a target path under
        ~/.agents/skills/<slug>/SKILL.md (or a new .instructions.md). These are
        ALWAYS routed to needs_human; reflect will not validate them for write.

    Write insight-candidates.json to: $sdir\insight-candidates.json
    Schema:
    {
      "session_id": "$sid",
      "candidates": [
        {
          "id": 1,
          "kind": "extend",
          "target_file": "<absolute path>",
          "confidence": "high|medium|low",
          "qi_layer": "change-risk|protection|signal-trust|outcome-evidence",
          "summary": "<one line>",
          "patch_mode": "insert_after|replace|append_eof",
          "patch": { "anchor_text": "<verbatim existing snippet>", "new_text": "<new>" },
          "diff_lines": <int>,
          "evidence": "<insight snippet + file_ref>"
        },
        {
          "id": 2,
          "kind": "create",
          "target_file_suggestion": "<absolute path under ~/.agents/...>",
          "qi_layer": "...",
          "summary": "<one line>",
          "rationale": "<why no existing customization fits>",
          "evidence": "<insight snippet + file_ref>"
        }
      ]
    }

    Cap total drafts at proactive_insights.max_per_session (config; default 3).
"@ })

5. Validate by running:
   powershell -NoProfile -ExecutionPolicy Bypass -File "$scriptDir\skill-improve-reflect.ps1" "$sid"
   It enforces diff cap, hot-skill quarantine, and dismissed-lessons fingerprinting. Trust its output.

6. After validation succeeds, present this exact format to the user and ASK before applying anything:

   I detected N corrections this session. Proposed updates:
     [1] <path>  — <summary>   (confidence: high, qi: <layer>)
     [2] <path>  — <summary>   (confidence: medium, qi: <layer>)
     [skipped] <path>  — <summary>   (low confidence or dismissed)
     [needs_human] <path>  — <reason>   (too large or restructure)
     [I1] <path>  — <summary>   (insight, kind: extend, qi: <layer>)         # only if insights ran
     [needs_human] <path>  — <reason>   (insight, kind: create)              # only if insights ran
   Apply which? [all / 1,2,I1 / none / diff <id>]   (diff <id> prints the patch and exits without applying)

7. Only after the user replies, invoke:
   powershell -NoProfile -ExecutionPolicy Bypass -File "$scriptDir\skill-improve-apply.ps1" "$sid" "<comma-separated ids or 'none'>"

Do not edit any customization file directly. The apply script handles writes, provenance comments, and state updates.
"@

    $payload = @{ decision = 'block'; reason = $taskBlock; continue = $true } | ConvertTo-Json -Compress -Depth 4
    if ($payload) { $emit = $payload }

    Invoke-SiJanitor -SessionId $sid -HadCorrections $true
    Write-SiLog "Stop sid=$sid corrections=true task-block-injected (janitor ran)"
} catch {
    Write-SiLog "Stop error: $_"
}

Write-Output $emit
