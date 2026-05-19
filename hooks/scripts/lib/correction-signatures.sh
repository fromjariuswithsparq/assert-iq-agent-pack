#!/bin/bash
# Correction-signature heuristics. Sourced by skill-improve-session-end.sh.
# Provides: si_scan_assistant_text, si_scan_tool_log.

# Read correction regex list from config into a single ERE alternation.
si_assistant_text_pattern() {
    python3 - <<PY 2>/dev/null
import json
try:
    with open("$SKILL_IMPROVE_CONFIG") as f: c = json.load(f)
    pats = c.get("correction_signatures", {}).get("assistant_text_regex", [])
    print("|".join(pats))
except Exception:
    print("")
PY
}

# Scan a transcript file ($1) for assistant correction markers. Emits JSON array on stdout.
si_scan_assistant_text() {
    local transcript="$1"
    [ -f "$transcript" ] || { echo "[]"; return; }
    python3 - "$transcript" <<'PY' 2>/dev/null
import json, re, sys, os
path = sys.argv[1]
cfg_path = os.path.expanduser("~/.agents/hooks/config/skill-improve.config.json")
patterns = []  # list of (compiled_regex, weight, raw_pattern)
try:
    with open(cfg_path) as f: c = json.load(f)
    raw = c.get("correction_signatures", {}).get("assistant_text_regex", [])
    for entry in raw:
        if isinstance(entry, str):
            patterns.append((re.compile(entry, re.IGNORECASE), "weak", entry))
        elif isinstance(entry, dict) and entry.get("pattern"):
            w = entry.get("weight", "weak")
            if w not in ("strong", "weak"): w = "weak"
            patterns.append((re.compile(entry["pattern"], re.IGNORECASE), w, entry["pattern"]))
except Exception:
    patterns = []

hits = []
try:
    with open(path, "r", errors="ignore") as f:
        for i, line in enumerate(f, 1):
            line_s = line.strip()
            if not line_s: continue
            text = ""
            role = ""
            try:
                rec = json.loads(line_s)
                if isinstance(rec, dict):
                    role = (rec.get("role") or rec.get("type") or rec.get("message", {}).get("role") or "").lower()
                    content = rec.get("content") or rec.get("message", {}).get("content") or rec.get("text") or ""
                    if isinstance(content, list):
                        text = " ".join([str(p.get("text", "") if isinstance(p, dict) else p) for p in content])
                    else:
                        text = str(content)
            except Exception:
                text = line_s
            if role and role not in ("assistant", "agent", "model"):
                continue
            for rx, weight, raw_pat in patterns:
                m = rx.search(text)
                if m:
                    hits.append({"line": i, "snippet": text[:240], "weight": weight, "pattern": raw_pat, "match": m.group(0)[:80]})
                    break  # at most one hit per transcript line (avoid double-counting)
except Exception:
    pass
print(json.dumps(hits))
PY
}

# Scan tool-log.jsonl for behavioral signals. Emits JSON array on stdout.
si_scan_tool_log() {
    local log="$1"
    [ -f "$log" ] || { echo "[]"; return; }
    python3 - "$log" <<'PY' 2>/dev/null
import json, sys, os
path = sys.argv[1]
cfg_path = os.path.expanduser("~/.agents/hooks/config/skill-improve.config.json")
try:
    with open(cfg_path) as f: c = json.load(f)
    tp = c.get("correction_signatures", {}).get("tool_patterns", {})
    reread_w = int(tp.get("reread_window_turns", 3))
    selfedit_w = int(tp.get("self_edit_window_turns", 2))
except Exception:
    reread_w, selfedit_w = 3, 2

entries = []
try:
    with open(path, "r", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                entries.append(json.loads(line))
            except Exception:
                pass
except Exception:
    pass

hits = []

# Pattern A: re-read of the same file shortly after a different op on it.
reads = {}  # file -> list of indices where it was read
edits = {}  # file -> list of indices where it was edited
for idx, e in enumerate(entries):
    f = e.get("file") or ""
    t = e.get("tool") or ""
    if not f: continue
    # VS Code: read_file / replace_string_in_file / multi_replace_string_in_file / create_file
    # Claude Code: Read / Edit / MultiEdit / Write
    if t in ("read_file", "Read"):
        reads.setdefault(f, []).append(idx)
    elif t in ("replace_string_in_file", "multi_replace_string_in_file", "create_file", "Edit", "MultiEdit", "Write"):
        edits.setdefault(f, []).append(idx)

# Helper: count unique non-target files touched between two tool-log indices.
# If the agent did substantive other work between an edit and a re-read /
# self-rewrite, the behavioral signal is much weaker (likely natural workflow,
# not a self-correction). Threshold: >=2 distinct other files → downgrade to weak.
def _intervening_other_files(start_idx, end_idx, target_f):
    others = set()
    for k in range(start_idx + 1, end_idx):
        if k < 0 or k >= len(entries): continue
        of = (entries[k] or {}).get("file") or ""
        if of and of != target_f:
            others.add(of)
    return len(others)

# Re-read after edit (within window): possible "had to verify after writing"
for f, eidxs in edits.items():
    ridxs = reads.get(f, [])
    for ei in eidxs:
        for ri in ridxs:
            if 0 < (ri - ei) <= reread_w:
                w = "weak" if _intervening_other_files(ei, ri, f) >= 2 else "behavioral"
                hits.append({"type": "reread_after_edit", "file": f, "edit_idx": ei, "read_idx": ri, "weight": w})
                break

# Pattern B: str_replace on a file the agent just wrote (rewrite of own output).
for f, eidxs in edits.items():
    for i in range(len(eidxs) - 1):
        if 0 < (eidxs[i+1] - eidxs[i]) <= selfedit_w:
            w = "weak" if _intervening_other_files(eidxs[i], eidxs[i+1], f) >= 2 else "behavioral"
            hits.append({"type": "self_rewrite", "file": f, "first_idx": eidxs[i], "second_idx": eidxs[i+1], "weight": w})

# Pattern C: failed tool result (non-zero / error flag) followed by retry on same file.
for idx, e in enumerate(entries):
    if e.get("error") and idx + 1 < len(entries):
        nxt = entries[idx + 1]
        if nxt.get("file") == e.get("file") and e.get("file"):
            hits.append({"type": "retry_after_error", "file": e.get("file"), "idx": idx, "weight": "behavioral"})

print(json.dumps(hits))
PY
}

# Scan a transcript file ($1) for proactive-insight markers — unsolicited
# observations the model makes about latent flaws ("consider X", "would be
# safer to Y", etc). Separate from si_scan_assistant_text by design: no
# self-error trail, only an outward-facing observation.
#
# When proactive_insights.require_file_reference is true (default), only counts
# hits whose assistant turn ALSO mentions a path-like token. The token is
# attached to each hit as `file_ref` so downstream can use it to suggest a
# target. Emits JSON array on stdout.
si_scan_proactive_insights() {
    local transcript="$1"
    [ -f "$transcript" ] || { echo "[]"; return; }
    python3 - "$transcript" <<'PY' 2>/dev/null
import json, re, sys, os
path = sys.argv[1]
cfg_path = os.path.expanduser("~/.agents/hooks/config/skill-improve.config.json")
patterns = []
require_file = True
try:
    with open(cfg_path) as f: c = json.load(f)
    pi = c.get("proactive_insights", {}) or {}
    if not pi.get("enabled", True):
        print("[]"); sys.exit(0)
    require_file = bool(pi.get("require_file_reference", True))
    raw = pi.get("proactive_insight_regex", []) or []
    for entry in raw:
        if isinstance(entry, dict) and entry.get("pattern"):
            w = entry.get("weight", "weak")
            if w not in ("strong", "weak"): w = "weak"
            patterns.append((re.compile(entry["pattern"], re.IGNORECASE), w, entry["pattern"]))
except Exception:
    patterns = []

file_rx = re.compile(r"(?:[\w./~-]+\.(?:md|cs|ts|tsx|js|jsx|py|yml|yaml|sh|ps1|json|cshtml|xaml|sql|rb|go|rs|java|kt))|(?:~?/[\w./-]+/[\w./-]+)")

hits = []
try:
    with open(path, "r", errors="ignore") as f:
        for i, line in enumerate(f, 1):
            line_s = line.strip()
            if not line_s: continue
            text = ""
            role = ""
            try:
                rec = json.loads(line_s)
                if isinstance(rec, dict):
                    role = (rec.get("role") or rec.get("type") or rec.get("message", {}).get("role") or "").lower()
                    content = rec.get("content") or rec.get("message", {}).get("content") or rec.get("text") or ""
                    if isinstance(content, list):
                        text = " ".join([str(p.get("text", "") if isinstance(p, dict) else p) for p in content])
                    else:
                        text = str(content)
            except Exception:
                text = line_s
            if role and role not in ("assistant", "agent", "model"):
                continue
            file_match = file_rx.search(text)
            file_ref = file_match.group(0) if file_match else ""
            if require_file and not file_ref:
                continue
            for rx, weight, raw_pat in patterns:
                m = rx.search(text)
                if m:
                    hits.append({
                        "line": i,
                        "snippet": text[:240],
                        "weight": weight,
                        "pattern": raw_pat,
                        "match": m.group(0)[:80],
                        "file_ref": file_ref,
                    })
                    break
except Exception:
    pass
print(json.dumps(hits))
PY
}
