#!/bin/bash
# Shared helpers for skill-improve hooks (bash side).
# Sourced by other scripts; not executed directly.

# Resolve hook root from env var (set by hooks.json wrapper based on install
# scope). Default = $HOME/.agents/hooks for backwards compatibility / user
# installs that don't go through the wrapper.
SKILL_IMPROVE_ROOT="${SKILL_IMPROVE_ROOT:-$HOME/.agents/hooks}"
SKILL_IMPROVE_CONFIG="$SKILL_IMPROVE_ROOT/config/skill-improve.config.json"
SKILL_IMPROVE_LOG="$SKILL_IMPROVE_ROOT/logs/skill-improve.log"
SKILL_IMPROVE_SESSIONS="$SKILL_IMPROVE_ROOT/sessions"
SKILL_IMPROVE_STATE="$SKILL_IMPROVE_ROOT/state"
# Export so child python processes (heredocs without explicit argv) can resolve
# the same paths via os.environ.
export SKILL_IMPROVE_ROOT SKILL_IMPROVE_CONFIG SKILL_IMPROVE_LOG SKILL_IMPROVE_SESSIONS SKILL_IMPROVE_STATE

mkdir -p "$SKILL_IMPROVE_ROOT/logs" "$SKILL_IMPROVE_SESSIONS" "$SKILL_IMPROVE_STATE" 2>/dev/null

# Always emit {"continue":true} on exit so the agent is never blocked.
si_emit_continue() {
    echo '{"continue":true}'
}

# Log a diagnostic line. Silent on failure.
si_log() {
    printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >> "$SKILL_IMPROVE_LOG" 2>/dev/null
}

# si_with_state_lock <python_code>
#   Run the given Python code under an exclusive fcntl.flock on $STATE/.state.lock.
#   The code receives `state_dir` (str) in its globals; it may read/modify/write
#   any of the shared state files (dismissed-lessons.json, edit-frequency.json,
#   correction-recurrence.json, needs-rewrite.json) safely.
#   The lock is released when the python interpreter exits.
si_with_state_lock() {
    local code="$1"
    python3 - "$SKILL_IMPROVE_STATE" "$code" <<'PY'
import sys, os, fcntl
state_dir, code = sys.argv[1], sys.argv[2]
os.makedirs(state_dir, exist_ok=True)
lock_path = os.path.join(state_dir, ".state.lock")
_lf = open(lock_path, "a+")
fcntl.flock(_lf.fileno(), fcntl.LOCK_EX)
exec(code, {"__name__": "__locked__", "state_dir": state_dir})
PY
}

# Check whether the system is enabled (config flag + env var).
si_enabled() {
    [ "${SKILL_IMPROVE_DISABLED:-0}" = "1" ] && return 1
    python3 - <<PY 2>/dev/null
import json, sys
try:
    with open("$SKILL_IMPROVE_CONFIG") as f: c = json.load(f)
    sys.exit(0 if c.get("enabled", True) else 1)
except Exception:
    sys.exit(0)
PY
}

# Read the raw stdin JSON envelope into the variable name passed as $1.
# Sets it to empty string if stdin is a TTY or empty.
si_read_stdin() {
    local __var="$1"
    if [ -t 0 ]; then printf -v "$__var" '%s' ''; return 0; fi
    local raw
    raw=$(cat)
    printf -v "$__var" '%s' "$raw"
}

# Extract a session id from an envelope JSON ($1). Falls back to a stable hash of cwd+date if missing.
si_session_id() {
    local raw="$1"
    python3 - "$raw" <<'PY' 2>/dev/null
import json, sys, hashlib, os, datetime
raw = sys.argv[1] if len(sys.argv) > 1 else ""
sid = ""
try:
    d = json.loads(raw)
    sid = d.get("session_id") or d.get("sessionId") or ""
except Exception:
    pass
if not sid:
    h = hashlib.sha256((os.getcwd() + datetime.date.today().isoformat()).encode()).hexdigest()[:16]
    sid = "anon-" + h
print(sid)
PY
}

# Path to this session's directory; creates it.
si_session_dir() {
    local sid="$1"
    local dir="$SKILL_IMPROVE_SESSIONS/$sid"
    mkdir -p "$dir" 2>/dev/null
    printf '%s' "$dir"
}

# si_dedup_or_exit <event_name> <raw_envelope>
#   Suppress double-fires of the same hook event for the same session within
#   SKILL_IMPROVE_DEDUP_WINDOW_SECONDS (default 5). VS Code + Claude Code +
#   Insiders can all register the same hooks.json and fire in parallel.
#   Atomic claim via O_EXCL (set -o noclobber). Marker files are pruned by
#   the janitor sweep. Set the env var to 0 to disable dedup entirely.
si_dedup_or_exit() {
    local event="$1" raw="$2"
    local window="${SKILL_IMPROVE_DEDUP_WINDOW_SECONDS:-5}"
    [ "$window" = "0" ] && return 0

    local sid sig marker now mtime hasher
    sid=$(si_session_id "$raw")
    if command -v shasum >/dev/null 2>&1; then
        sig=$(printf '%s-%s' "$sid" "$event" | shasum -a 256 | cut -c1-16)
    elif command -v sha256sum >/dev/null 2>&1; then
        sig=$(printf '%s-%s' "$sid" "$event" | sha256sum | cut -c1-16)
    else
        return 0  # No hasher available; degrade to no dedup.
    fi
    [ -z "$sig" ] && return 0
    marker="$SKILL_IMPROVE_STATE/.dedup-${sig}"

    # Atomic claim via noclobber. If we're first, the file is created and we
    # continue. If another invocation already created it, check age.
    if ( set -o noclobber; : > "$marker" ) 2>/dev/null; then
        return 0
    fi
    now=$(date +%s 2>/dev/null || echo 0)
    mtime=$(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker" 2>/dev/null || echo 0)
    if [ "$((now - mtime))" -lt "$window" ]; then
        si_log "dedup $event sid=$sid (skipped duplicate within ${window}s)"
        echo '{"continue":true}'
        exit 0
    fi
    # Stale marker — refresh by overwriting.
    : > "$marker" 2>/dev/null || true
    return 0
}

# Janitor: prune silent session, trim edit-frequency, rotate log, sweep old session dirs.
# Args: $1 = session_id, $2 = had_corrections (0|1)
# Heavy sweeps gated by janitor_min_interval_hours via state/.last-janitor marker.
si_run_janitor() {
    local sid="$1"
    local had_corr="$2"
    python3 - "$SKILL_IMPROVE_ROOT" "$sid" "$had_corr" <<'PY' 2>/dev/null
import json, os, sys, time, shutil, datetime, glob

root, sid, had_corr = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
cfg_path = os.path.join(root, "config", "skill-improve.config.json")
try:
    with open(cfg_path) as f: cfg = json.load(f)
except Exception:
    cfg = {}
ret = cfg.get("retention", {})
keep_silent = bool(ret.get("keep_silent_sessions", False))
keep_corr_days = int(ret.get("keep_correction_sessions_days", 30))
ef_keep_days = int(ret.get("edit_frequency_keep_days", 14))
log_max = int(ret.get("log_max_lines", 5000))
min_interval_h = int(ret.get("janitor_min_interval_hours", 24))

sessions_dir = os.path.join(root, "sessions")
state_dir = os.path.join(root, "state")
log_path = os.path.join(root, "logs", "skill-improve.log")
marker = os.path.join(state_dir, ".last-janitor")

# Layer 1a: prune this session if silent and not kept.
sdir = os.path.join(sessions_dir, sid)
if os.path.isdir(sdir) and not had_corr and not keep_silent:
    try:
        shutil.rmtree(sdir)
    except Exception:
        pass

# Heavy sweeps only once per N hours.
now = time.time()
last = 0
try:
    last = float(open(marker).read().strip())
except Exception:
    pass
if (now - last) < (min_interval_h * 3600):
    sys.exit(0)

# Layer 1b: rotate log (keep last log_max lines).
try:
    if os.path.isfile(log_path):
        with open(log_path) as f:
            lines = f.readlines()
        if len(lines) > log_max:
            with open(log_path, "w") as f:
                f.writelines(lines[-log_max:])
except Exception:
    pass

# Layer 1c: trim edit-frequency.json older than ef_keep_days.
ef_path = os.path.join(state_dir, "edit-frequency.json")
try:
    with open(ef_path) as f: ef = json.load(f)
    cutoff = datetime.datetime.utcnow() - datetime.timedelta(days=ef_keep_days)
    kept = []
    for e in ef.get("edits", []):
        try:
            ts = datetime.datetime.fromisoformat(e["ts"].replace("Z",""))
            if ts >= cutoff: kept.append(e)
        except Exception:
            kept.append(e)  # keep malformed rather than lose audit
    if len(kept) != len(ef.get("edits", [])):
        ef["edits"] = kept
        with open(ef_path, "w") as f: json.dump(ef, f, indent=2)
except Exception:
    pass

# Layer 2: sweep correction-session dirs older than keep_corr_days.
try:
    cutoff_t = now - keep_corr_days * 86400
    for d in glob.glob(os.path.join(sessions_dir, "*")):
        if not os.path.isdir(d): continue
        try:
            if os.path.getmtime(d) < cutoff_t:
                shutil.rmtree(d)
        except Exception:
            pass
except Exception:
    pass

# Layer 3: prune stale dedup markers (anything older than 1 hour).
try:
    cutoff_dedup = now - 3600
    for m in glob.glob(os.path.join(state_dir, ".dedup-*")):
        try:
            if os.path.getmtime(m) < cutoff_dedup:
                os.unlink(m)
        except Exception:
            pass
except Exception:
    pass

# Update marker.
try:
    with open(marker, "w") as f: f.write(str(now))
except Exception:
    pass
PY
}
