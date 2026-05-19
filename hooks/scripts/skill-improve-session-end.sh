#!/bin/bash
# Stop hook: at end of session, scan for correction signals. If any exist,
# inject an agent task block that triggers the in-session "apply edits?" prompt.
# If silent_on_zero_corrections=true and no signals, exit silently.

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/json-utils.sh
. "$SCRIPT_DIR/lib/json-utils.sh"
# shellcheck source=lib/correction-signatures.sh
. "$SCRIPT_DIR/lib/correction-signatures.sh"

# Default emit-continue trap; we may override stdout below.
EMIT_PAYLOAD='{"continue":true}'
trap 'echo "$EMIT_PAYLOAD"' EXIT

si_enabled || exit 0

si_read_stdin SI_RAW
SID="$(si_session_id "$SI_RAW")"
SDIR="$(si_session_dir "$SID")"

# Avoid recursion: Claude Code sets stop_hook_active=true when continuing from a Stop block.
STOP_ACTIVE=$(python3 -c "import json,sys
try: d=json.loads(sys.argv[1] or '{}'); print('1' if d.get('stop_hook_active') else '0')
except: print('0')" "$SI_RAW" 2>/dev/null)
[ "$STOP_ACTIVE" = "1" ] && exit 0

# Extract transcript_path from envelope (if present).
TRANSCRIPT=$(python3 -c "import json,sys
try: d=json.loads(sys.argv[1] or '{}'); print(d.get('transcript_path') or d.get('transcriptPath') or '')
except: print('')" "$SI_RAW" 2>/dev/null)

TOOL_LOG="$SDIR/tool-log.jsonl"
TEXT_HITS_JSON="$(si_scan_assistant_text "$TRANSCRIPT")"
TOOL_HITS_JSON="$(si_scan_tool_log "$TOOL_LOG")"

# Proactive-insight scanning runs in parallel with correction scanning. Hits
# go to a separate weighted gate (proactive_insights.trigger.min_score) so a
# session can fire on insights only, corrections only, or both.
if [ "${SKILL_IMPROVE_INSIGHTS_DISABLED:-0}" = "1" ]; then
    INSIGHT_HITS_JSON="[]"
else
    INSIGHT_HITS_JSON="$(si_scan_proactive_insights "$TRANSCRIPT")"
fi

# Decide: do collected hits meet the configured score threshold? Score = sum of
# per-hit weights from correction_signatures.trigger.weights. Bypass via
# SKILL_IMPROVE_TRIGGER_ANY=1 (legacy any-hit behavior). Override the configured
# min_score via SKILL_IMPROVE_MIN_SCORE=<int> (debugging / tuning aid).
# Insights have their OWN gate; either gate firing is sufficient to inject the
# task block. CORR_GATE / INSIGHT_GATE are exported so the task-block builder
# can adjust wording.
GATE_RESULT=$(SKILL_IMPROVE_TRIGGER_ANY="${SKILL_IMPROVE_TRIGGER_ANY:-0}" SKILL_IMPROVE_MIN_SCORE="${SKILL_IMPROVE_MIN_SCORE:-}" python3 -c "
import json, sys, os
t = json.loads(sys.argv[1] or '[]')
u = json.loads(sys.argv[2] or '[]')
p = json.loads(sys.argv[3] or '[]')
trigger_any = os.environ.get('SKILL_IMPROVE_TRIGGER_ANY') == '1'
try:
    c = json.load(open(os.path.expanduser('~/.agents/hooks/config/skill-improve.config.json')))
except Exception:
    c = {}
trig = (c.get('correction_signatures', {}) or {}).get('trigger', {}) or {}
min_score = int(trig.get('min_score', 2))
weights = trig.get('weights', {}) or {}
sw = int(weights.get('strong', 2)); ww = int(weights.get('weak', 1)); bw = int(weights.get('behavioral', 2))
override = os.environ.get('SKILL_IMPROVE_MIN_SCORE', '')
if override:
    try: min_score = int(override)
    except ValueError: pass
def score(hit, dw, sw=sw, ww=ww, bw=bw):
    w = (hit or {}).get('weight', dw)
    return {'strong': sw, 'weak': ww, 'behavioral': bw}.get(w, ww)
corr_total = sum(score(h, 'weak') for h in t) + sum(score(h, 'behavioral') for h in u)
corr_gate = (1 if (trigger_any and (t or u)) else (1 if corr_total >= min_score else 0))

pi = c.get('proactive_insights', {}) or {}
pi_trig = pi.get('trigger', {}) or {}
pi_min = int(pi_trig.get('min_score', 3))
pi_w = pi_trig.get('weights', {}) or {}
psw = int(pi_w.get('strong', 2)); pww = int(pi_w.get('weak', 1))
def piscore(hit, psw=psw, pww=pww):
    w = (hit or {}).get('weight', 'weak')
    return {'strong': psw, 'weak': pww}.get(w, pww)
pi_total = sum(piscore(h) for h in p)
pi_gate = (1 if (trigger_any and p) else (1 if pi_total >= pi_min else 0))

print(f'{corr_gate}:{pi_gate}')
" "$TEXT_HITS_JSON" "$TOOL_HITS_JSON" "$INSIGHT_HITS_JSON" 2>/dev/null)
CORR_GATE="${GATE_RESULT%%:*}"
INSIGHT_GATE="${GATE_RESULT##*:}"
if [ "$CORR_GATE" = "1" ] || [ "$INSIGHT_GATE" = "1" ]; then
    HAS_HITS=1
else
    HAS_HITS=0
fi

SILENT=$(python3 -c "import json,os
try:
    c=json.load(open(os.path.expanduser('~/.agents/hooks/config/skill-improve.config.json')))
    print('1' if c.get('behavior',{}).get('silent_on_zero_corrections', True) else '0')
except: print('1')")

if [ "$HAS_HITS" != "1" ]; then
    si_run_janitor "$SID" 0
    if [ "$SILENT" = "1" ]; then
        si_log "Stop sid=$SID no-corrections silent (janitor ran)"
        exit 0
    fi
    EMIT_PAYLOAD='{"continue":true,"systemMessage":"skill-improve: no corrections detected this session."}'
    si_log "Stop sid=$SID no-corrections announced (janitor ran)"
    exit 0
fi

# Persist the raw signal bundle for the agent task to consume.
SIGNALS="$SDIR/signals.json"
python3 - "$SDIR" "$TEXT_HITS_JSON" "$TOOL_HITS_JSON" "$INSIGHT_HITS_JSON" "$TRANSCRIPT" "$SID" "$CORR_GATE" "$INSIGHT_GATE" <<'PY' 2>/dev/null
import json, sys, os, datetime
sdir, t, u, p, tr, sid, cg, ig = sys.argv[1:9]
out = {
    "session_id": sid,
    "captured_at": datetime.datetime.utcnow().isoformat() + "Z",
    "transcript_path": tr,
    "assistant_text_hits": json.loads(t or "[]"),
    "tool_log_hits": json.loads(u or "[]"),
    "insight_hits": json.loads(p or "[]"),
    "gates": {"correction": cg == "1", "insight": ig == "1"},
}
with open(os.path.join(sdir, "signals.json"), "w") as f:
    json.dump(out, f, indent=2)
PY

# Compute invoked-customizations.json from the tool log. Customization files
# whose path was read during this session are flagged for attribution priority.
python3 - "$SDIR" <<'PY' 2>/dev/null
import json, os, sys
sdir = sys.argv[1]
log_path = os.path.join(sdir, "tool-log.jsonl")
loaded_path = os.path.join(sdir, "loaded-customizations.json")
invoked = []
seen = set()
try:
    loaded = json.load(open(loaded_path))
    loaded_files = set(loaded.get("customization_files") or loaded.get("skill_files") or [])
except Exception:
    loaded_files = set()
try:
    with open(log_path) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            f_ = rec.get("file") or ""
            if not f_: continue
            invoked_flag = bool(rec.get("customization_invoked"))
            # Defensive fallback: if instrumentation didn't fire (older sessions),
            # treat any read of a loaded-customization path as invoked.
            if not invoked_flag and rec.get("tool") == "read_file" and f_ in loaded_files:
                invoked_flag = True
            if invoked_flag and f_ not in seen:
                seen.add(f_)
                invoked.append({"file": f_, "first_invoked_at": rec.get("ts")})
except Exception:
    pass
out = {"session_id": os.path.basename(sdir), "invoked": invoked, "invoked_count": len(invoked)}
with open(os.path.join(sdir, "invoked-customizations.json"), "w") as fp:
    json.dump(out, fp, indent=2)
PY

# Build the agent task block. This is the prompt the agent will execute on next turn.
TASK_BLOCK=$(cat <<EOF
SKILL-IMPROVE: ${SID}

Correction signals were detected during this session. Do the following BEFORE closing the conversation:

1. Read these files:
   - $SDIR/loaded-customizations.json   (skills/instructions/prompts/agents in scope this session)
   - $SDIR/invoked-customizations.json  (subset actually read/touched this session — attribute against these FIRST)
   - $SDIR/signals.json                 (detected correction signals)
   - $SDIR/tool-log.jsonl               (raw tool activity)

2. For each meaningful correction, identify the single most likely source customization file that SHOULD have prevented it. Prefer files listed in invoked-customizations.json (the agent actually read them this session); only fall back to the full loaded-customizations.json set if no invoked file is a plausible owner. Classify each via the qi-foundation 4 layers (change-risk / protection / signal-trust / outcome-evidence) to help route.

3. Draft a minimal patch per target file:
   - Single-bullet additions or single-line fixes only.
   - Diff must be <= 10 lines total per file (hard cap).
   - Reject anything that requires restructuring — those go on a "needs human authoring" list, not the patch list.

4. Write candidate-edits.json to: $SDIR/candidate-edits.json
   Schema:
   {
     "session_id": "$SID",
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

   $(if [ "$INSIGHT_GATE" = "1" ]; then cat <<'EOFI'
4b. PROACTIVE INSIGHTS DETECTED. signals.json -> insight_hits contains assistant
    observations about latent flaws ("consider X", "would be safer to Y", etc).
    These are unsolicited — there is no self-error trail — so they need a
    different judgment than corrections.

    For each meaningful insight, draft an entry. Two kinds:
      - "kind":"extend" — the observation maps cleanly into an existing
        customization (instruction / skill / prompt / agent) listed in
        invoked-customizations.json or loaded-customizations.json. Same diff cap
        applies (<=10 lines). These flow through the standard reflect gates and
        can be auto-applied.
      - "kind":"create" — the observation describes a recurring concern that
        does NOT fit any existing customization. Suggest a target path under
        ~/.agents/skills/<slug>/SKILL.md (or a new .instructions.md). These are
        ALWAYS routed to needs_human; reflect will not validate them for write.

    Write insight-candidates.json to: $SDIR/insight-candidates.json
    Schema:
    {
      "session_id": "$SID",
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
EOFI
fi)

5. Validate by running:
   bash $SCRIPT_DIR/skill-improve-reflect.sh "$SID"
   (or skill-improve-reflect.ps1 on Windows). It enforces diff cap, hot-skill quarantine, and dismissed-lessons fingerprinting. Trust its output.

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
   bash $SCRIPT_DIR/skill-improve-apply.sh "$SID" "<comma-separated ids or 'none'>"

Do not edit any customization file directly. The apply script handles writes, provenance comments, and state updates.
EOF
)

# Use Claude Code's "decision: block" mechanism so the agent gets the task block as its next prompt.
EMIT_PAYLOAD=$(python3 - "$TASK_BLOCK" <<'PY' 2>/dev/null
import json, sys
print(json.dumps({"decision": "block", "reason": sys.argv[1], "continue": True}))
PY
)
[ -z "$EMIT_PAYLOAD" ] && EMIT_PAYLOAD='{"continue":true}'

si_run_janitor "$SID" 1
si_log "Stop sid=$SID corrections=true task-block-injected (janitor ran)"
exit 0
