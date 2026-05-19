#!/bin/bash
# Applier: applies user-accepted edits from candidate-edits.validated.json.
# Performs direct edits in the working tree (no git ops), appends a
# provenance comment, bumps edit-frequency, fingerprints rejections.
#
# Usage: skill-improve-apply.sh <session-id> <ids|none|all>
#   ids: comma-separated integers, e.g. "1,3"

set +e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/json-utils.sh
. "$SCRIPT_DIR/lib/json-utils.sh"

SID="$1"; SEL="$2"
if [ -z "$SID" ] || [ -z "$SEL" ]; then
    echo "usage: $0 <session-id> <ids|none|all|diff N>" >&2; exit 2
fi
SDIR="$SKILL_IMPROVE_SESSIONS/$SID"
VALIDATED="$SDIR/candidate-edits.validated.json"
IVALIDATED="$SDIR/insight-candidates.validated.json"
if [ ! -f "$VALIDATED" ] && [ ! -f "$IVALIDATED" ]; then
    echo "no validated file at $SDIR" >&2; exit 2
fi

# Dry-run path: "diff N" prints the patch for candidate N and exits without applying.
# N may be a plain integer (correction) or "I<int>" (insight).
if [[ "$SEL" =~ ^[[:space:]]*diff[[:space:]]+([Ii]?[0-9]+)[[:space:]]*$ ]]; then
    DIFF_ID="${BASH_REMATCH[1]}"
    python3 - "$SDIR" "$DIFF_ID" <<'PY'
import json, os, sys
sdir, want = sys.argv[1], sys.argv[2]
is_insight = want.lower().startswith("i")
num = int(want[1:] if is_insight else want)
vfile = "insight-candidates.validated.json" if is_insight else "candidate-edits.validated.json"
vpath = os.path.join(sdir, vfile)
if not os.path.isfile(vpath):
    print(f"no {vfile}"); sys.exit(2)
v = json.load(open(vpath))
match = next((c for c in v.get("validated", []) if c.get("id") == num), None)
if not match:
    print(f"no validated candidate with id={want}"); sys.exit(2)
patch = match.get("patch", {}) or {}
label = "I" + str(num) if is_insight else str(num)
print(f"=== diff for candidate #{label} ===")
print(f"target_file : {match.get('target_file')}")
print(f"patch_mode  : {match.get('patch_mode')}")
print(f"confidence  : {match.get('confidence')}   qi_layer: {match.get('qi_layer')}")
if is_insight: print(f"kind        : {match.get('kind')}")
print(f"diff_lines  : {match.get('diff_lines')}")
print(f"summary     : {match.get('summary')}")
print(f"--- anchor_text ---")
print(patch.get("anchor_text", "") or "(none)")
print(f"--- new_text ---")
print(patch.get("new_text", "") or "(none)")
print(f"=== end diff (no changes applied) ===")
PY
    si_log "Apply sid=$SID sel='diff $DIFF_ID' (dry-run)"
    exit 0
fi

python3 - "$SDIR" "$SEL" "$SID" "$SKILL_IMPROVE_STATE" <<'PY'
import json, os, sys, datetime, hashlib

sdir, sel, sid, state_dir = sys.argv[1:5]
# Load corrections (may be absent).
cpath = os.path.join(sdir, "candidate-edits.validated.json")
try:
    with open(cpath) as f: vc = json.load(f)
except Exception:
    vc = {"validated": [], "needs_human": []}
# Load insights (may be absent).
ipath = os.path.join(sdir, "insight-candidates.validated.json")
try:
    with open(ipath) as f: vi = json.load(f)
except Exception:
    vi = {"validated": [], "needs_human": []}

# Tag origin so apply can distinguish provenance comments + reporting.
corr_validated = []
for c in vc.get("validated", []):
    c["_source"] = "correction"
    corr_validated.append(c)
ins_validated = []
for c in vi.get("validated", []):
    c["_source"] = "insight"
    ins_validated.append(c)
validated = corr_validated + ins_validated

sel = sel.strip().lower()
accept_corr_ids = set()
accept_ins_ids = set()
if sel == "all":
    accept_corr_ids = {c["id"] for c in corr_validated}
    accept_ins_ids  = {c["id"] for c in ins_validated}
elif sel == "none":
    pass
else:
    invalid_tokens = []
    seen_any = False
    for part in sel.split(","):
        part = part.strip()
        if not part:
            continue
        seen_any = True
        if part.startswith("i") and part[1:].isdigit():
            accept_ins_ids.add(int(part[1:]))
        elif part.isdigit():
            accept_corr_ids.add(int(part))
        else:
            invalid_tokens.append(part)
    if (not seen_any) or invalid_tokens:
        bad = ", ".join(invalid_tokens) if invalid_tokens else sel
        print(f"invalid selection: {bad}. Use 'all', 'none', comma-separated numeric ids, or insight ids prefixed with 'i'.", file=sys.stderr)
        sys.exit(2)

date = datetime.date.today().isoformat()
applied = []
rejected = []

import re as _re
def frontmatter_end_offset(content):
    """Return char offset where YAML frontmatter ends, or 0 if none / malformed."""
    if not content.startswith("---"):
        return 0
    nl = content.find("\n")
    if nl == -1 or content[:nl].strip() != "---":
        return 0
    m = _re.search(r'\n---[ \t]*(\n|$)', content[nl:])
    if not m:
        return 0
    return nl + m.end()

VALID_PATCH_MODES = {"insert_after", "replace", "append_eof"}

for c in validated:
    src = c.get("_source", "correction")
    accept_set = accept_ins_ids if src == "insight" else accept_corr_ids
    if c["id"] not in accept_set:
        rejected.append(c); continue

    target = c["target_file"]
    patch = c.get("patch") or {}
    anchor = patch.get("anchor_text", "") or ""
    new_text = patch.get("new_text", "") or ""
    patch_mode = (c.get("patch_mode") or patch.get("mode") or "").strip().lower()
    if patch_mode not in VALID_PATCH_MODES:
        c["apply_error"] = f"invalid patch_mode at apply: {patch_mode!r}"; rejected.append(c); continue
    if not os.path.isfile(target):
        c["apply_error"] = "target missing at apply time"; rejected.append(c); continue

    try:
        with open(target, "r") as f: content = f.read()
    except Exception as e:
        c["apply_error"] = f"read failed: {e}"; rejected.append(c); continue

    # Insight patches get a distinct provenance comment so future readers can
    # tell which edits originated from unsolicited model insights vs. self-error
    # corrections. Both forms are dedup-checked per (target, session).
    if src == "insight":
        prov_marker = f"<!-- self-improve (insight): session {sid}, {date} -->"
    else:
        prov_marker = f"<!-- self-improve: session {sid}, {date} -->"
    prov = "" if prov_marker in content else f"\n{prov_marker}"
    fm_end = frontmatter_end_offset(content)

    if patch_mode in ("insert_after", "replace"):
        if not anchor:
            c["apply_error"] = f"anchor_text required for {patch_mode}"; rejected.append(c); continue
        anchor_pos = content.find(anchor)
        if anchor_pos < 0:
            c["apply_error"] = "anchor_not_found"; rejected.append(c); continue
        if anchor_pos < fm_end:
            c["apply_error"] = "patch_inside_frontmatter"; rejected.append(c); continue
        if patch_mode == "insert_after":
            replacement = anchor + "\n" + new_text.rstrip() + prov
        else:  # replace
            replacement = new_text.rstrip() + prov
        updated = content[:anchor_pos] + replacement + content[anchor_pos + len(anchor):]
    else:  # append_eof
        sep = "" if content.endswith("\n") else "\n"
        updated = content + sep + new_text.rstrip() + prov + "\n"

    try:
        with open(target, "w") as f: f.write(updated)
        c["applied_at"] = datetime.datetime.utcnow().isoformat() + "Z"
        applied.append(c)
    except Exception as e:
        c["apply_error"] = f"write failed: {e}"; rejected.append(c)

# Update state: dismissed-lessons (for rejected) and edit-frequency (for applied).
# Held under fcntl.flock to serialize concurrent apply/reflect/session-end writers.
import fcntl as _fcntl
os.makedirs(state_dir, exist_ok=True)
_state_lock_f = open(os.path.join(state_dir, ".state.lock"), "a+")
_fcntl.flock(_state_lock_f.fileno(), _fcntl.LOCK_EX)
dismissed_path = os.path.join(state_dir, "dismissed-lessons.json")
freq_path = os.path.join(state_dir, "edit-frequency.json")
try: ds = json.load(open(dismissed_path))
except: ds = {"dismissed": []}
try: fq = json.load(open(freq_path))
except: fq = {"edits": []}

for c in rejected:
    if c.get("apply_error"): continue  # don't dismiss errored applies
    fp = c.get("fingerprint")
    if fp and fp not in ds["dismissed"]: ds["dismissed"].append(fp)

for c in applied:
    fq["edits"].append({
        "ts": c["applied_at"],
        "session_id": sid,
        "target_file": c["target_file"],
        "summary": c.get("summary",""),
        "fingerprint": c.get("fingerprint"),
    })

# Recurrence tracking: keyed by fingerprint (which encodes target+qi_layer+signal_class).
# When the same fingerprint is applied >= 2 times within 30 days, the target gets
# added to needs-rewrite.json by reflect on the second attempt (see reflect script).
recurrence_path = os.path.join(state_dir, "correction-recurrence.json")
try: rec_state = json.load(open(recurrence_path))
except: rec_state = {"entries": {}}
for c in applied:
    fp = c.get("fingerprint")
    if not fp: continue
    entry = rec_state["entries"].get(fp, {"target_file": c["target_file"], "applied_count": 0, "history": []})
    entry["target_file"] = c["target_file"]
    entry["applied_count"] = int(entry.get("applied_count", 0)) + 1
    entry["last_applied_at"] = c["applied_at"]
    entry.setdefault("history", []).append({"ts": c["applied_at"], "session_id": sid})
    # Cap history to last 10 entries to bound file growth.
    entry["history"] = entry["history"][-10:]
    rec_state["entries"][fp] = entry
with open(recurrence_path, "w") as f: json.dump(rec_state, f, indent=2)

with open(dismissed_path, "w") as f: json.dump(ds, f, indent=2)
with open(freq_path, "w") as f: json.dump(fq, f, indent=2)

decisions = {
    "session_id": sid,
    "decided_at": datetime.datetime.utcnow().isoformat() + "Z",
    "selection": sel,
    "applied": applied,
    "rejected": rejected,
}
with open(os.path.join(sdir, "decisions.json"), "w") as f:
    json.dump(decisions, f, indent=2)

print(f"applied: {len(applied)}  rejected/dismissed: {len([c for c in rejected if not c.get('apply_error')])}  errors: {len([c for c in rejected if c.get('apply_error')])}")
needs_human = (vc.get("needs_human", []) or []) + (vi.get("needs_human", []) or [])
if needs_human:
    print(f"needs_human: {len(needs_human)}  (not auto-applied)")
    for nh in needs_human:
        tgt = nh.get('target_file') or nh.get('target_file_suggestion','?')
        reason = nh.get('reason') or nh.get('needs_human_reason') or nh.get('summary','')
        kind_tag = f" (insight, kind={nh.get('kind','create')})" if nh.get('kind') else ""
        print(f"  [needs_human] {tgt} — {reason}{kind_tag}")
for c in applied:
    label = f"I{c['id']}" if c.get("_source") == "insight" else str(c['id'])
    print(f"  [applied {label}] {c['target_file']} — {c.get('summary','')}")
for c in rejected:
    label = f"I{c['id']}" if c.get("_source") == "insight" else str(c['id'])
    if c.get("apply_error"):
        print(f"  [error {label}]   {c['target_file']} — {c['apply_error']}")
    else:
        print(f"  [dismissed {label}] {c['target_file']} — {c.get('summary','')}")
PY

RC=$?
si_log "Apply sid=$SID sel=$SEL rc=$RC"
exit $RC
