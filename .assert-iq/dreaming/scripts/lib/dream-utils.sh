#!/usr/bin/env bash
# Shared helpers for the Assert.IQ Dreaming waking loop (bash side).
# Sourced by dream-record-session.sh and dream-gate.sh; not run directly.

# Pack root is injected by session-events.template.json (CLAUDE_PLUGIN_ROOT
# wins at runtime under Claude Code; the baked __PACK_ROOT__ is the fallback
# for VS Code Copilot). Default to three levels up from this lib dir.
if [ -z "${AIQ_PACK_ROOT:-}" ]; then
  AIQ_PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi
AIQ_MEMORY_DIR="${AIQ_MEMORY_DIR:-$AIQ_PACK_ROOT/.assert-iq/memory}"
AIQ_DREAM_STATE="$AIQ_MEMORY_DIR/.dream/state.json"
AIQ_DREAM_LOCK="$AIQ_MEMORY_DIR/.dream/state.lock"
AIQ_CONFIG="$AIQ_PACK_ROOT/.assert-iq/config.yaml"
export AIQ_PACK_ROOT AIQ_MEMORY_DIR AIQ_DREAM_STATE AIQ_DREAM_LOCK AIQ_CONFIG

mkdir -p "$AIQ_MEMORY_DIR/.dream" "$AIQ_MEMORY_DIR/logs" 2>/dev/null

# Always emit continue so the agent is never blocked.
aiq_emit_continue() { echo '{"continue":true}'; }

# Kill-switch (env) + dreaming.enabled in config (default true).
aiq_enabled() {
  [ "${AIQ_DREAMING_DISABLED:-0}" = "1" ] && return 1
  python3 - "$AIQ_CONFIG" <<'PY' 2>/dev/null
import sys, re
try:
    txt = open(sys.argv[1]).read()
except Exception:
    sys.exit(0)
m = re.search(r'^dreaming:\s*$(.*?)(^\S|\Z)', txt, re.M | re.S)
block = m.group(1) if m else txt
em = re.search(r'^\s+enabled:\s*(true|false)', block, re.M)
sys.exit(1 if (em and em.group(1) == 'false') else 0)
PY
}

# Gate values: env override wins, else best-effort read from config, else default.
aiq_gate_min_hours() {
  if [ -n "${AIQ_DREAM_MIN_HOURS:-}" ]; then printf '%s' "$AIQ_DREAM_MIN_HOURS"; return; fi
  local v; v=$(sed -n 's/.*min_hours_between_dreams:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$AIQ_CONFIG" 2>/dev/null | head -n1)
  printf '%s' "${v:-24}"
}
aiq_gate_min_sessions() {
  if [ -n "${AIQ_DREAM_MIN_SESSIONS:-}" ]; then printf '%s' "$AIQ_DREAM_MIN_SESSIONS"; return; fi
  local v; v=$(sed -n 's/.*min_sessions_between_dreams:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$AIQ_CONFIG" 2>/dev/null | head -n1)
  printf '%s' "${v:-5}"
}

# Run python under an exclusive flock on the dream state lock.
aiq_with_state_lock() {
  local code="$1"
  python3 - "$AIQ_DREAM_STATE" "$AIQ_DREAM_LOCK" "$code" <<'PY'
import sys, os, fcntl
state_path, lock_path, code = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(os.path.dirname(state_path), exist_ok=True)
_lf = open(lock_path, "a+")
fcntl.flock(_lf.fileno(), fcntl.LOCK_EX)
exec(code, {"__name__": "__locked__", "state_path": state_path})
PY
}

# Read stdin envelope (Claude Code passes a JSON envelope; may be empty).
aiq_read_stdin() {
  local __var="$1"; local __data=""
  if [ ! -t 0 ]; then __data="$(cat 2>/dev/null)"; fi
  printf -v "$__var" '%s' "$__data"
}

aiq_session_id() {
  python3 -c "import json,sys
try: d=json.loads(sys.argv[1] or '{}'); print(d.get('session_id') or d.get('sessionId') or 'unknown')
except: print('unknown')" "$1" 2>/dev/null
}

aiq_transcript_path() {
  python3 -c "import json,sys
try: d=json.loads(sys.argv[1] or '{}'); print(d.get('transcript_path') or d.get('transcriptPath') or '')
except: print('')" "$1" 2>/dev/null
}
