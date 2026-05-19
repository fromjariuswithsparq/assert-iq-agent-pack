#!/bin/bash
# PostToolUse hook: append a compact record of each tool call to
# sessions/<id>/tool-log.jsonl. Heavy analysis happens at session end.
# Must be cheap and never block.

set +e
trap 'echo "{\"continue\":true}"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/json-utils.sh
. "$SCRIPT_DIR/lib/json-utils.sh"

si_enabled || exit 0
if [ -t 0 ]; then exit 0; fi

SI_RAW=$(cat)
[ -z "$SI_RAW" ] && exit 0

SID="$(si_session_id "$SI_RAW")"
SDIR="$(si_session_dir "$SID")"

python3 - "$SI_RAW" "$SDIR" <<'PY' 2>/dev/null
import json, sys, os, datetime

raw, sdir = sys.argv[1], sys.argv[2]
try:
    d = json.loads(raw)
except Exception:
    sys.exit(0)

tool = d.get("tool_name") or d.get("toolName") or ""
ti = d.get("tool_input") or d.get("toolArgs") or {}
tr = d.get("tool_response") or d.get("toolResponse") or {}

# Best-effort file extraction.
file = ""
if isinstance(ti, dict):
    file = ti.get("filePath") or ti.get("file_path") or ti.get("path") or ""
    # multi_replace nested array
    if not file and isinstance(ti.get("replacements"), list) and ti["replacements"]:
        first = ti["replacements"][0]
        if isinstance(first, dict):
            file = first.get("filePath") or first.get("file_path") or ""

# Error flag — best effort across response shapes.
err = False
if isinstance(tr, dict):
    if tr.get("error") or tr.get("isError") or tr.get("is_error"): err = True
    msg = tr.get("message") or tr.get("content") or ""
    if isinstance(msg, str) and ("error" in msg.lower() or "failed" in msg.lower()) and len(msg) < 400:
        err = True
elif isinstance(tr, str) and ("error" in tr.lower() or "failed" in tr.lower()):
    err = True

rec = {
    "ts": datetime.datetime.utcnow().isoformat() + "Z",
    "tool": tool,
    "file": file,
    "error": err,
}

# Customization invocation: when a customization file (skill/instruction/prompt/agent)
# in scope this session is read, flag it. Used at session-end to compute
# invoked-customizations.json so attribution can prioritize them.
if tool == "read_file" and file:
    loaded_path = os.path.join(sdir, "loaded-customizations.json")
    try:
        with open(loaded_path) as f:
            loaded = json.load(f)
        # tolerate both new + legacy field names; entries may be plain paths or {"path":...} dicts.
        loaded_entries = loaded.get("customization_files") or loaded.get("skill_files") or []
        loaded_paths = set()
        for entry in loaded_entries:
            if isinstance(entry, str):
                loaded_paths.add(entry)
            elif isinstance(entry, dict) and entry.get("path"):
                loaded_paths.add(entry["path"])
        if file in loaded_paths:
            rec["customization_invoked"] = True
    except Exception:
        pass

# Capture a tiny snippet of the input for str_replace ops — useful for self-rewrite detection.
# VS Code: replace_string_in_file / multi_replace_string_in_file
# Claude Code: Edit / MultiEdit
if tool in ("replace_string_in_file", "multi_replace_string_in_file", "Edit", "MultiEdit") and isinstance(ti, dict):
    snippet = ti.get("newString") or ti.get("new_string") or ""
    if isinstance(snippet, str) and snippet:
        rec["new_snippet_hash"] = abs(hash(snippet)) % (10**10)

out = os.path.join(sdir, "tool-log.jsonl")
with open(out, "a") as f:
    f.write(json.dumps(rec) + "\n")
PY

exit 0
