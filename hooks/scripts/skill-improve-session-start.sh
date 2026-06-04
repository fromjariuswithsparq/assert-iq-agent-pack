#!/bin/bash
# SessionStart hook: snapshot which SKILL.md / instructions.md files exist
# under the configured roots so we can later attribute corrections to them.
# Never blocks; logs to ~/.agents/hooks/logs/skill-improve.log.

set +e
trap 'echo "{\"continue\":true}"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/json-utils.sh
. "$SCRIPT_DIR/lib/json-utils.sh"

si_enabled || exit 0

si_read_stdin SI_RAW
si_dedup_or_exit "SessionStart" "$SI_RAW"
SID="$(si_session_id "$SI_RAW")"
SDIR="$(si_session_dir "$SID")"

python3 - "$SI_RAW" "$SDIR" <<'PY' 2>/dev/null
import json, os, sys, glob, fnmatch, datetime

raw, sdir = sys.argv[1], sys.argv[2]
cfg_path = os.environ.get("SKILL_IMPROVE_CONFIG") or os.path.expanduser("~/.agents/hooks/config/skill-improve.config.json")
try:
    with open(cfg_path) as f: c = json.load(f)
except Exception:
    c = {}

# Prefer customization_* keys; fall back to legacy skill_* keys for back-compat.
roots = [os.path.expanduser(r) for r in (c.get("customization_roots") or c.get("skill_roots") or [])]
patterns = c.get("customization_file_patterns") or c.get("skill_file_patterns") or ["SKILL.md", "*.instructions.md", "*.prompt.md", "copilot-instructions.md", "AGENTS.md"]

found = []
for root in roots:
    if not os.path.isdir(root): continue
    for dirpath, _, files in os.walk(root):
        # Skip noisy / generated dirs.
        if any(seg in dirpath for seg in (os.sep + ".git" + os.sep, os.sep + "node_modules" + os.sep, os.sep + "bin" + os.sep, os.sep + "obj" + os.sep)):
            continue
        for fn in files:
            for p in patterns:
                if fnmatch.fnmatch(fn, p):
                    try:
                        full = os.path.join(dirpath, fn)
                        st = os.stat(full)
                        found.append({"path": full, "size": st.st_size, "mtime": st.st_mtime})
                    except Exception:
                        pass
                    break

# Pull transcript_path / source if present in the envelope.
transcript = ""
source = ""
try:
    d = json.loads(raw) if raw else {}
    transcript = d.get("transcript_path") or d.get("transcriptPath") or ""
    source = d.get("source") or ""
except Exception:
    pass

out = {
    "session_id": os.path.basename(sdir),
    "captured_at": datetime.datetime.utcnow().isoformat() + "Z",
    "transcript_path": transcript,
    "source": source,
    "cwd": os.getcwd(),
    "customization_files": found,
}
with open(os.path.join(sdir, "loaded-customizations.json"), "w") as f:
    json.dump(out, f, indent=2)
PY

si_log "SessionStart sid=$SID dir=$SDIR"
exit 0
