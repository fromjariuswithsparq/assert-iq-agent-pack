#\!/usr/bin/env bash
# Assert.IQ Dreaming E2E driver (bash).
# Verifies the waking loop + gate + sandbox:
#   - dream-record-session increments state.json and appends a dated log line
#   - dream-gate stays closed below thresholds, opens at >= min_sessions AND time
#   - AIQ_DREAMING_DISABLED=1 is a no-op
#   - all scripts emit a valid {"continue":true} envelope
#   - the optional service enforces the memory write-sandbox (PermissionError)
#
# Usage: bash tests/_qi/automated/e2e-dreaming.sh [--keep]
set -u

PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
KEEP=0
for arg in "$@"; do case "$arg" in --keep) KEEP=1 ;; esac; done

grn() { printf '\033[32m%s\033[0m' "$*"; }
red() { printf '\033[31m%s\033[0m' "$*"; }
PASS=0; FAIL=0; declare -a FAILED=()
ok()   { PASS=$((PASS+1)); printf '  %s %s\n' "$(grn PASS)" "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED+=("$1"); printf '  %s %s\n' "$(red FAIL)" "$1"; }

MEM="$(mktemp -d "${TMPDIR:-/tmp}/aiq-dream.XXXXXX")"
mkdir -p "$MEM/.dream" "$MEM/logs" "$MEM/topics"
printf '{\n  "last_dream_utc": null,\n  "sessions_since_dream": 0\n}\n' > "$MEM/.dream/state.json"
cleanup() { [[ $KEEP -eq 1 ]] && { echo "(kept: $MEM)"; return; }; rm -rf "$MEM"; }
trap cleanup EXIT

export AIQ_PACK_ROOT="$PACK"
export AIQ_MEMORY_DIR="$MEM"
REC="$PACK/.assert-iq/dreaming/scripts/dream-record-session.sh"
GATE="$PACK/.assert-iq/dreaming/scripts/dream-gate.sh"

echo "== recorder increments counter + appends log =="
for i in 1 2 3 4 5; do
  out="$(echo "{\"session_id\":\"s$i\"}" | AIQ_DREAM_MIN_SESSIONS=5 bash "$REC")"
  [[ "$out" == '{"continue":true}' ]] || bad "recorder envelope on run $i (got: $out)"
done
count="$(python3 -c "import json;print(json.load(open('$MEM/.dream/state.json'))['sessions_since_dream'])")"
[[ "$count" == "5" ]] && ok "counter reached 5" || bad "counter expected 5, got $count"
[[ -n "$(find "$MEM/logs" -name '*.md' -print -quit)" ]] && ok "daily log written" || bad "no daily log"

echo "== gate closed below threshold =="
# reset to 3 sessions
python3 -c "import json;p='$MEM/.dream/state.json';d=json.load(open(p));d['sessions_since_dream']=3;json.dump(d,open(p,'w'))"
out="$(echo '{}' | AIQ_DREAM_MIN_SESSIONS=5 bash "$GATE")"
echo "$out" | grep -q systemMessage && bad "gate fired at 3 sessions" || ok "gate closed at 3 sessions"

echo "== gate opens at threshold (never dreamed => time gate satisfied) =="
python3 -c "import json;p='$MEM/.dream/state.json';d=json.load(open(p));d['sessions_since_dream']=5;json.dump(d,open(p,'w'))"
out="$(echo '{}' | AIQ_DREAM_MIN_SESSIONS=5 bash "$GATE")"
echo "$out" | grep -q systemMessage && ok "gate opened at 5 sessions" || bad "gate did not open at 5 (got: $out)"

echo "== gate time-gated when recently dreamed =="
python3 -c "import json,datetime;p='$MEM/.dream/state.json';d={'last_dream_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sessions_since_dream':9};json.dump(d,open(p,'w'))"
out="$(echo '{}' | AIQ_DREAM_MIN_SESSIONS=5 AIQ_DREAM_MIN_HOURS=24 bash "$GATE")"
echo "$out" | grep -q systemMessage && bad "gate fired despite recent dream (time gate)" || ok "gate held by time gate"

echo "== kill-switch no-op =="
out="$(echo '{}' | AIQ_DREAMING_DISABLED=1 bash "$GATE")"
[[ "$out" == '{"continue":true}' ]] && ok "AIQ_DREAMING_DISABLED honored" || bad "kill-switch not honored (got: $out)"

echo "== service enforces memory write-sandbox =="
SB="$(python3 - "$PACK" "$MEM" <<'PY'
import importlib.util, sys, pathlib
pack, mem = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("dsvc", pathlib.Path(pack)/".assert-iq/dreaming/service/dreaming_service.py")
m = importlib.util.module_from_spec(spec); sys.modules["dsvc"] = m; spec.loader.exec_module(m)
cfg = m.DreamConfig(project_root=pathlib.Path(mem).parent, memory_rel=pathlib.Path(mem).name)
cyc = m.DreamCycle(cfg, client=None)
try:
    cyc._apply({"files": {"../../escape.md": "pwned"}})
    print("NO_ERROR")
except PermissionError:
    print("BLOCKED")
except Exception as e:
    print("OTHER:" + type(e).__name__)
PY
)"
[[ "$SB" == "BLOCKED" ]] && ok "write outside memory/ refused" || bad "sandbox not enforced (got: $SB)"

echo ""
printf 'Dreaming E2E: %s passed, %s failed\n' "$(grn $PASS)" "$([[ $FAIL -gt 0 ]] && red $FAIL || echo 0)"
[[ $FAIL -eq 0 ]] || { printf 'Failures:\n'; printf '  - %s\n' "${FAILED[@]}"; exit 1; }
