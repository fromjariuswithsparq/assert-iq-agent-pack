#!/bin/bash
# Validator: reads sessions/<id>/candidate-edits.json drafted by the agent,
# enforces diff cap + hot-skill quarantine + dismissed-lessons filtering,
# and writes back a normalized candidate-edits.validated.json the agent
# (and apply script) should trust.
#
# Usage: skill-improve-reflect.sh <session-id>

set +e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/json-utils.sh
. "$SCRIPT_DIR/lib/json-utils.sh"

SID="$1"
if [ -z "$SID" ]; then echo "usage: $0 <session-id>" >&2; exit 2; fi

SDIR="$SKILL_IMPROVE_SESSIONS/$SID"
CAND="$SDIR/candidate-edits.json"
ICAND="$SDIR/insight-candidates.json"
if [ ! -f "$CAND" ] && [ ! -f "$ICAND" ]; then
    echo "no candidate-edits.json or insight-candidates.json at $SDIR" >&2
    exit 2
fi

python3 - "$SDIR" "$SKILL_IMPROVE_CONFIG" "$SKILL_IMPROVE_STATE" <<'PY'
import json, os, sys, hashlib, datetime

sdir, cfg_path, state_dir = sys.argv[1:4]
cand_path = os.path.join(sdir, "candidate-edits.json")
icand_path = os.path.join(sdir, "insight-candidates.json")
if os.path.isfile(cand_path):
    with open(cand_path) as f:
        cand = json.load(f)
else:
    cand = {"session_id": os.path.basename(sdir), "candidates": [], "needs_human": []}
with open(cfg_path) as f:
    cfg = json.load(f)

thresholds = cfg.get("thresholds", {})
diff_max = int(thresholds.get("diff_max_lines", 10))
hot_window_days = int(thresholds.get("hot_skill_window_days", 7))
hot_limit = int(thresholds.get("hot_skill_edit_limit", 3))
min_conf = (thresholds.get("min_confidence") or "medium").lower()
conf_rank = {"low": 0, "medium": 1, "high": 2}

# Load state.
dismissed_path = os.path.join(state_dir, "dismissed-lessons.json")
freq_path = os.path.join(state_dir, "edit-frequency.json")
recurrence_path = os.path.join(state_dir, "correction-recurrence.json")
needs_rewrite_path = os.path.join(state_dir, "needs-rewrite.json")
try: dismissed = json.load(open(dismissed_path)).get("dismissed", [])
except: dismissed = []
try: edits_log = json.load(open(freq_path)).get("edits", [])
except: edits_log = []
try: recurrence = json.load(open(recurrence_path)).get("entries", {})
except: recurrence = {}
try: needs_rewrite = set(json.load(open(needs_rewrite_path)).get("targets", []))
except: needs_rewrite = set()

RECURRENCE_WINDOW_DAYS = 30
RECURRENCE_TRIGGER = 2  # applied_count threshold inside the window to quarantine

now = datetime.datetime.utcnow()
def hot(target):
    cutoff = now - datetime.timedelta(days=hot_window_days)
    count = 0
    for e in edits_log:
        try:
            ts = datetime.datetime.fromisoformat(e["ts"].replace("Z",""))
        except Exception:
            continue
        if e.get("target_file") == target and ts >= cutoff:
            count += 1
    return count >= hot_limit

def _signal_evidence_class(c):
    """Derive a coarse signal class from candidate.evidence so the
    fingerprint reflects WHY we patched, not WHAT we wrote. Keeps multiple
    fixes for the same (target, layer, root-cause) class de-duplicated even
    when the wording differs."""
    ev = (c.get("evidence") or "").lower()
    # Behavioral markers (from si_scan_tool_log type tags).
    for tag in ("self_rewrite", "reread_after_edit", "retry_after_error"):
        if tag in ev:
            return f"behavioral:{tag}"
    # Strong text markers (mirror config's strong-weighted patterns).
    strong_terms = [
        ("my_mistake",      ["my mistake"]),
        ("i_was_wrong",     ["i was wrong"]),
        ("correction",      ["correction:"]),
        ("scratch_that",    ["scratch that", "strike that", "i take that back", "disregard that"]),
        ("apologize",       ["apologi"]),
        ("missed",          ["i missed", "overlooked", "oversight"]),
        ("should_have",     ["i should have", "i shouldn't have"]),
        ("not_correct",     ["that's not right", "that's not correct"]),
    ]
    for class_name, needles in strong_terms:
        if any(n in ev for n in needles):
            return f"text:strong:{class_name}"
    # Weak text markers.
    weak_terms = ["actually", "turns out", "let me re", "never mind", "second thought",
                  "wait", "hold on", "instead", "won't work", "doesn't work", "didn't work"]
    if any(n in ev for n in weak_terms):
        return "text:weak"
    return "unknown"

def fingerprint(c):
    """Signal-shaped fingerprint: same (target, qi_layer, signal_class, kind) collapses to
    one entry. `kind` is "correction" by default; insight candidates pass
    "insight_extend" / "insight_create" so they live in their own dismissed-lessons
    namespace and don't collide with corrections on the same target/layer.
    Earlier releases hashed (target + new_text); see legacy_fingerprint."""
    parts = [
        c.get("target_file", "") or c.get("target_file_suggestion", ""),
        (c.get("qi_layer") or "").lower(),
        _signal_evidence_class(c),
        (c.get("kind") or "correction").lower(),
    ]
    return hashlib.sha256("|".join(parts).encode()).hexdigest()

def legacy_fingerprint(c):
    """Old formula. Kept for one release so already-dismissed entries stay dismissed."""
    body = (c.get("target_file","") + "|" + (c.get("patch", {}).get("new_text","")).strip().lower())
    return hashlib.sha256(body.encode()).hexdigest()

validated = []
skipped = []
VALID_PATCH_MODES = {"insert_after", "replace", "append_eof"}
for c in cand.get("candidates", []):
    target = c.get("target_file","")
    patch = c.get("patch", {}) or {}
    new_text = patch.get("new_text","") or ""
    anchor_text = patch.get("anchor_text","") or ""
    # Accept patch_mode at top level (preferred) or under patch.mode for tolerance.
    patch_mode = (c.get("patch_mode") or patch.get("mode") or "").strip().lower()
    c["patch_mode"] = patch_mode

    # Two-sided diff_lines: always compute, override agent-supplied value if it understates.
    def _line_count(s):
        s = s or ""
        return s.count("\n") + (1 if s.strip() else 0)
    computed_diff = max(_line_count(new_text), _line_count(anchor_text), 1)
    agent_diff = c.get("diff_lines")
    if not isinstance(agent_diff, int) or agent_diff < computed_diff:
        diff_lines = computed_diff
    else:
        diff_lines = agent_diff
    c["diff_lines"] = diff_lines
    c["fingerprint"] = fingerprint(c)
    c["legacy_fingerprint"] = legacy_fingerprint(c)

    reason = None
    if not target or not os.path.isfile(target):
        reason = "target_file_missing"
    elif not new_text.strip():
        reason = "empty_patch"
    elif patch_mode not in VALID_PATCH_MODES:
        reason = "missing_or_invalid_patch_mode (expected one of: insert_after|replace|append_eof)"
    elif patch_mode in ("insert_after", "replace") and not anchor_text.strip():
        reason = f"anchor_text_required_for_{patch_mode}"
    elif diff_lines > diff_max:
        reason = f"diff_exceeds_cap ({diff_lines}>{diff_max})"
    elif c["fingerprint"] in dismissed or c["legacy_fingerprint"] in dismissed:
        reason = "previously_dismissed"
    elif target in needs_rewrite:
        reason = "needs_rewrite_quarantine (target previously failed automated patches; requires human rewrite)"
    elif conf_rank.get((c.get("confidence") or "").lower(), 0) < conf_rank.get(min_conf, 1):
        reason = f"confidence_below_{min_conf}"
    elif hot(target):
        reason = f"hot_skill_quarantine (>{hot_limit} edits in {hot_window_days}d)"
    else:
        # Recurrence quarantine: if this exact fingerprint was applied >= RECURRENCE_TRIGGER
        # times within the recurrence window, the prior patches did not fix the issue.
        rec_entry = recurrence.get(c["fingerprint"]) or {}
        applied_count = int(rec_entry.get("applied_count", 0))
        last_applied = rec_entry.get("last_applied_at", "")
        recent = False
        if last_applied:
            try:
                ts = datetime.datetime.fromisoformat(last_applied.replace("Z", ""))
                if (now - ts).days <= RECURRENCE_WINDOW_DAYS:
                    recent = True
            except Exception:
                recent = False
        if recent and applied_count >= RECURRENCE_TRIGGER:
            reason = f"recurrence_quarantine (signal recurred after {applied_count} applied patches in {RECURRENCE_WINDOW_DAYS}d)"
            needs_rewrite.add(target)

    if reason:
        c["skip_reason"] = reason
        skipped.append(c)
    else:
        validated.append(c)

# Persist needs-rewrite state (sticky until a human removes it — see README).
# Locked to coordinate with concurrent apply/session-end writers.
try:
    import fcntl as _fcntl
    os.makedirs(state_dir, exist_ok=True)
    with open(os.path.join(state_dir, ".state.lock"), "a+") as _lf:
        _fcntl.flock(_lf.fileno(), _fcntl.LOCK_EX)
        with open(needs_rewrite_path, "w") as f:
            json.dump({"targets": sorted(needs_rewrite)}, f, indent=2)
except Exception:
    pass

# Renumber ids 1..N for the user-facing list.
for i, c in enumerate(validated, 1):
    c["id"] = i

out = {
    "session_id": cand.get("session_id"),
    "validated_at": now.isoformat() + "Z",
    "validated": validated,
    "skipped": skipped,
    "needs_human": cand.get("needs_human", []),
    "policy": {
        "diff_max_lines": diff_max,
        "hot_skill_window_days": hot_window_days,
        "hot_skill_edit_limit": hot_limit,
        "min_confidence": min_conf,
    },
}
with open(os.path.join(sdir, "candidate-edits.validated.json"), "w") as f:
    json.dump(out, f, indent=2)

# ---- Insight candidates (Phase 6) ----
# Validate insight-candidates.json against the same gates as corrections, with
# two differences:
#   * kind="create" is ALWAYS routed to needs_human (never auto-applied), even
#     if everything else passes. The fingerprint still records it so dismissal
#     can stick.
#   * `target_file` may be absent for kind="create" (suggestion only); use
#     `target_file_suggestion` for fingerprinting / display.
ivalidated, iskipped, ineeds = [], [], []
if os.path.isfile(icand_path):
    try:
        with open(icand_path) as f:
            icand = json.load(f)
    except Exception:
        icand = {"candidates": []}
    for c in icand.get("candidates", []):
        kind = (c.get("kind") or "extend").lower()
        c["kind"] = kind
        target = c.get("target_file") or c.get("target_file_suggestion") or ""
        patch = c.get("patch", {}) or {}
        new_text = patch.get("new_text","") or ""
        anchor_text = patch.get("anchor_text","") or ""
        patch_mode = (c.get("patch_mode") or patch.get("mode") or "").strip().lower()
        c["patch_mode"] = patch_mode
        def _lc(s):
            s = s or ""
            return s.count("\n") + (1 if s.strip() else 0)
        computed_diff = max(_lc(new_text), _lc(anchor_text), 1)
        agent_diff = c.get("diff_lines")
        diff_lines = computed_diff if (not isinstance(agent_diff, int) or agent_diff < computed_diff) else agent_diff
        c["diff_lines"] = diff_lines
        c["fingerprint"] = fingerprint(c)
        c["legacy_fingerprint"] = legacy_fingerprint(c)

        if kind == "create":
            # Always human-only — author a new skill / instruction file.
            c["needs_human_reason"] = "insight_kind_create"
            ineeds.append(c)
            continue
        if kind != "extend":
            c["skip_reason"] = f"unknown_kind ({kind!r}; expected extend|create)"
            iskipped.append(c); continue

        reason = None
        if not target or not os.path.isfile(target):
            reason = "target_file_missing"
        elif not new_text.strip():
            reason = "empty_patch"
        elif patch_mode not in VALID_PATCH_MODES:
            reason = "missing_or_invalid_patch_mode (expected one of: insert_after|replace|append_eof)"
        elif patch_mode in ("insert_after", "replace") and not anchor_text.strip():
            reason = f"anchor_text_required_for_{patch_mode}"
        elif diff_lines > diff_max:
            reason = f"diff_exceeds_cap ({diff_lines}>{diff_max})"
        elif c["fingerprint"] in dismissed or c["legacy_fingerprint"] in dismissed:
            reason = "previously_dismissed"
        elif target in needs_rewrite:
            reason = "needs_rewrite_quarantine"
        elif conf_rank.get((c.get("confidence") or "").lower(), 0) < conf_rank.get(min_conf, 1):
            reason = f"confidence_below_{min_conf}"
        elif hot(target):
            reason = f"hot_skill_quarantine (>{hot_limit} edits in {hot_window_days}d)"
        else:
            rec_entry = recurrence.get(c["fingerprint"]) or {}
            applied_count = int(rec_entry.get("applied_count", 0))
            last_applied = rec_entry.get("last_applied_at", "")
            recent = False
            if last_applied:
                try:
                    ts = datetime.datetime.fromisoformat(last_applied.replace("Z", ""))
                    if (now - ts).days <= RECURRENCE_WINDOW_DAYS:
                        recent = True
                except Exception:
                    recent = False
            if recent and applied_count >= RECURRENCE_TRIGGER:
                reason = f"recurrence_quarantine (signal recurred after {applied_count} applied patches in {RECURRENCE_WINDOW_DAYS}d)"

        if reason:
            c["skip_reason"] = reason
            iskipped.append(c)
        else:
            ivalidated.append(c)

    for i, c in enumerate(ivalidated, 1):
        c["id"] = i
    iout = {
        "session_id": icand.get("session_id"),
        "validated_at": now.isoformat() + "Z",
        "validated": ivalidated,
        "skipped": iskipped,
        "needs_human": ineeds,
        "policy": {
            "diff_max_lines": diff_max,
            "min_confidence": min_conf,
        },
    }
    with open(os.path.join(sdir, "insight-candidates.validated.json"), "w") as f:
        json.dump(iout, f, indent=2)

# Human summary to stdout.
print(f"validated: {len(validated)}  skipped: {len(skipped)}  needs_human: {len(out['needs_human'])}")
for c in validated:
    print(f"  [{c['id']}] {c['target_file']} — {c.get('summary','')}  (conf={c.get('confidence')}, qi={c.get('qi_layer')})")
for c in skipped:
    print(f"  [skip] {c.get('target_file','?')} — {c.get('skip_reason')}")
if os.path.isfile(icand_path):
    print(f"insights: validated={len(ivalidated)} skipped={len(iskipped)} needs_human={len(ineeds)}")
    for c in ivalidated:
        print(f"  [I{c['id']}] {c['target_file']} — {c.get('summary','')}  (kind=extend, qi={c.get('qi_layer')})")
    for c in ineeds:
        tgt = c.get('target_file') or c.get('target_file_suggestion','?')
        print(f"  [needs_human] {tgt} — {c.get('summary','')}  (insight, kind={c.get('kind')})")
    for c in iskipped:
        tgt = c.get('target_file') or c.get('target_file_suggestion','?')
        print(f"  [I:skip] {tgt} — {c.get('skip_reason')}")
PY

RC=$?
si_log "Reflect sid=$SID rc=$RC"
exit $RC
