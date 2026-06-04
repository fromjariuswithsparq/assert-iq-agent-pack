#!/usr/bin/env bash
# Assert.IQ hooks E2E driver.
# Verifies that hook scripts:
#   - route writes to the workspace install (./hooks/) when SKILL_IMPROVE_ROOT
#     points there (workspace install)
#   - route writes to ~/.agents/hooks/ (user install) when SKILL_IMPROVE_ROOT
#     points there
#   - emit valid {"continue":true} envelopes
#   - dedup duplicate fires of the same (sid, event) within the window
#   - honor SKILL_IMPROVE_DISABLED=1 (no-op)
#   - honor config.enabled=false (no-op when SKILL_IMPROVE_DISABLED unset)
#   - render hooks.json with __PACK_ROOT__ correctly substituted at install time
#
# Usage:
#   bash tests/_qi/automated/e2e-hooks.sh [--keep] [pattern]
set -u

PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
KEEP=0
PATTERN=""
for arg in "$@"; do
  case "$arg" in
    --keep) KEEP=1 ;;
    *) PATTERN="$arg" ;;
  esac
done

red() { printf '\033[31m%s\033[0m' "$*"; }
grn() { printf '\033[32m%s\033[0m' "$*"; }
ylw() { printf '\033[33m%s\033[0m' "$*"; }

CASES_PASS=0
CASES_FAIL=0
declare -a FAIL_LOG=()

# ---- fixtures --------------------------------------------------------------
mkfixture() {
  local ws home
  ws="$(mktemp -d "${TMPDIR:-/tmp}/aiq-hk-ws.XXXXXX")"
  home="$(mktemp -d "${TMPDIR:-/tmp}/aiq-hk-home.XXXXXX")"
  ( cd "$ws" && git init -q && git config user.email t@t && git config user.name t \
    && git commit --allow-empty -q -m init )
  echo "$ws:$home"
}

cleanup_fixture() {
  local pair="$1"
  [[ $KEEP -eq 1 ]] && { echo "  (kept: $pair)"; return; }
  local ws="${pair%:*}" home="${pair#*:}"
  rm -rf "$ws" "$home"
}

run_boot() {
  local pair="$1"; shift
  local ws="${pair%:*}" home="${pair#*:}"
  HOME="$home" bash "$PACK/scripts/bootstrap.sh" --workspace="$ws" "$@" </dev/null 2>&1
}

# Run a hook script with a fake stdin envelope. Args: pair script_relpath sid extra_env
# extra_env is a string like "FOO=bar BAZ=1" — passed verbatim to env.
run_hook() {
  local pair="$1" script_rel="$2" sid="$3"; shift 3
  local extra_env="${1:-}"
  local ws="${pair%:*}" home="${pair#*:}"
  local payload="{\"session_id\":\"$sid\",\"hook_event_name\":\"test\"}"
  # shellcheck disable=SC2086
  HOME="$home" env $extra_env bash "$ws/$script_rel" <<<"$payload" 2>&1
}

# Run hook from user-global install location.
run_user_hook() {
  local pair="$1" script_rel="$2" sid="$3"; shift 3
  local extra_env="${1:-}"
  local ws="${pair%:*}" home="${pair#*:}"
  local payload="{\"session_id\":\"$sid\",\"hook_event_name\":\"test\"}"
  # shellcheck disable=SC2086
  HOME="$home" env $extra_env bash "$home/.agents/hooks/$script_rel" <<<"$payload" 2>&1
}

# ---- assertions ------------------------------------------------------------
fail() {
  local label="$1"; shift
  FAIL_LOG+=("  $(red FAIL) $label: $*")
  CASES_FAIL=$((CASES_FAIL+1))
}
ok_file()    { [[ -e "$2" ]] || { fail "$1" "expected to exist: $2"; return 1; }; return 0; }
ok_dir()     { [[ -d "$2" ]] || { fail "$1" "expected dir: $2"; return 1; }; return 0; }
ok_missing() { [[ ! -e "$2" ]] || { fail "$1" "expected missing: $2"; return 1; }; return 0; }
ok_contains() { grep -Fq "$3" "$2" 2>/dev/null || { fail "$1" "expected '$3' in $2"; return 1; }; return 0; }
ok_not_contains() { ! grep -Fq "$3" "$2" 2>/dev/null || { fail "$1" "expected NOT '$3' in $2"; return 1; }; return 0; }

run_case() {
  local label="$1" fn="$2"
  if [[ -n "$PATTERN" && ! "$label" =~ $PATTERN ]]; then return; fi
  local before=$CASES_FAIL
  printf '  %-60s ' "$label"
  if "$fn"; then
    if [[ $CASES_FAIL -gt $before ]]; then printf '%s\n' "$(red FAIL)"
    else printf '%s\n' "$(grn PASS)"; CASES_PASS=$((CASES_PASS+1)); fi
  else
    printf '%s\n' "$(red FAIL)"; CASES_FAIL=$((CASES_FAIL+1))
  fi
}

# ============================================================================
# CASES
# ============================================================================

# Workspace install — paths and rendered hooks.json.
case_01_workspace_install_layout() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=committed --hooks=workspace --yes >/dev/null
  ok_file 01 "$ws/hooks/hooks.json" || true
  ok_file 01 "$ws/hooks/scripts/lib/json-utils.sh" || true
  ok_file 01 "$ws/hooks/config/skill-improve.config.json" || true
  ok_dir  01 "$ws/hooks/sessions" || true
  # Wrapper resolves __PACK_ROOT__ to the workspace path.
  ok_contains 01 "$ws/hooks/hooks.json" "$ws" || true
  ok_contains 01 "$ws/hooks/hooks.json" "SKILL_IMPROVE_ROOT" || true
  cleanup_fixture "$pair"
}

# User install — paths and rendered hooks.json point at $HOME/.agents/hooks.
case_02_user_install_layout() {
  local pair; pair="$(mkfixture)"
  local home="${pair#*:}"
  run_boot "$pair" --preset=portable --mode=committed --hooks=user --yes >/dev/null
  ok_file 02 "$home/.agents/hooks/hooks.json" || true
  ok_file 02 "$home/.agents/hooks/scripts/lib/json-utils.sh" || true
  ok_file 02 "$home/.agents/hooks/config/skill-improve.config.json" || true
  ok_dir  02 "$home/.agents/hooks/sessions" || true
  # Wrapper resolves __PACK_ROOT__ to $HOME/.agents (so $R/hooks resolves at runtime).
  ok_contains 02 "$home/.agents/hooks/hooks.json" "$home/.agents" || true
  ok_contains 02 "$home/.agents/hooks/hooks.json" "SKILL_IMPROVE_ROOT" || true
  cleanup_fixture "$pair"
}

# SessionStart writes session dir + loaded-customizations under workspace install.
case_03_workspace_session_start_writes_local() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}" home="${pair#*:}"
  run_boot "$pair" --preset=pod --mode=committed --hooks=workspace --yes >/dev/null
  local out
  out=$(SKILL_IMPROVE_ROOT="$ws/hooks" run_hook "$pair" "hooks/scripts/skill-improve-session-start.sh" "sid-A")
  echo "$out" | grep -q '"continue":true' || { fail 03 "missing continue envelope: $out"; cleanup_fixture "$pair"; return 1; }
  ok_dir  03 "$ws/hooks/sessions/sid-A" || true
  ok_file 03 "$ws/hooks/sessions/sid-A/loaded-customizations.json" || true
  ok_missing 03 "$home/.agents/hooks/sessions/sid-A" || true
  cleanup_fixture "$pair"
}

# User install — same script invoked with user-level SKILL_IMPROVE_ROOT writes
# into $HOME/.agents/hooks/sessions/, not the workspace.
case_04_user_session_start_writes_user() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}" home="${pair#*:}"
  run_boot "$pair" --preset=portable --mode=committed --hooks=user --yes >/dev/null
  local out
  out=$(SKILL_IMPROVE_ROOT="$home/.agents/hooks" run_user_hook "$pair" "scripts/skill-improve-session-start.sh" "sid-B")
  echo "$out" | grep -q '"continue":true' || { fail 04 "missing continue envelope: $out"; cleanup_fixture "$pair"; return 1; }
  ok_dir  04 "$home/.agents/hooks/sessions/sid-B" || true
  ok_file 04 "$home/.agents/hooks/sessions/sid-B/loaded-customizations.json" || true
  ok_missing 04 "$ws/hooks/sessions/sid-B" || true
  cleanup_fixture "$pair"
}

# track-telemetry no-ops cleanly (continues, no error).
case_05_post_tool_telemetry_continues() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=committed --hooks=workspace --yes >/dev/null
  local out
  # Real PostToolUse envelope shape — minimal fields only.
  out=$(SKILL_IMPROVE_ROOT="$ws/hooks" AZURE_MCP_COLLECT_TELEMETRY=false bash "$ws/hooks/scripts/track-telemetry.sh" \
        <<<'{"session_id":"sid-T","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{}}' 2>&1)
  echo "$out" | grep -q '"continue":true' || { fail 05 "expected continue:true, got: $out"; cleanup_fixture "$pair"; return 1; }
  cleanup_fixture "$pair"
}

# skill-improve-detect appends one entry to tool-log.jsonl.
case_06_post_tool_detect_appends_log() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=committed --hooks=workspace --yes >/dev/null
  SKILL_IMPROVE_ROOT="$ws/hooks" bash "$ws/hooks/scripts/skill-improve-detect.sh" \
    <<<'{"session_id":"sid-D","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' >/dev/null 2>&1
  ok_file 06 "$ws/hooks/sessions/sid-D/tool-log.jsonl" || true
  local lines; lines=$(wc -l < "$ws/hooks/sessions/sid-D/tool-log.jsonl" 2>/dev/null || echo 0)
  [[ "$lines" -ge 1 ]] || fail 06 "tool-log.jsonl has 0 lines"
  cleanup_fixture "$pair"
}

# Stop hook writes a log entry to skill-improve.log.
case_07_stop_writes_log() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=committed --hooks=workspace --yes >/dev/null
  SKILL_IMPROVE_ROOT="$ws/hooks" bash "$ws/hooks/scripts/skill-improve-session-end.sh" \
    <<<'{"session_id":"sid-S","hook_event_name":"Stop"}' >/dev/null 2>&1
  ok_file 07 "$ws/hooks/logs/skill-improve.log" || true
  ok_contains 07 "$ws/hooks/logs/skill-improve.log" "Stop sid=sid-S" || true
  cleanup_fixture "$pair"
}

# config.enabled=false → all scripts no-op (no session dir, no log entry).
case_08_config_disabled_noop() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=committed --hooks=workspace --yes >/dev/null
  # Disable via config.
  python3 -c "import json; p='$ws/hooks/config/skill-improve.config.json'; c=json.load(open(p)); c['enabled']=False; json.dump(c, open(p,'w'), indent=2)"
  SKILL_IMPROVE_ROOT="$ws/hooks" bash "$ws/hooks/scripts/skill-improve-session-start.sh" \
    <<<'{"session_id":"sid-OFF","hook_event_name":"SessionStart"}' >/dev/null 2>&1
  ok_missing 08 "$ws/hooks/sessions/sid-OFF" || true
  cleanup_fixture "$pair"
}

# SKILL_IMPROVE_DISABLED=1 → all scripts no-op.
case_09_env_disabled_noop() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=committed --hooks=workspace --yes >/dev/null
  SKILL_IMPROVE_ROOT="$ws/hooks" SKILL_IMPROVE_DISABLED=1 bash "$ws/hooks/scripts/skill-improve-session-start.sh" \
    <<<'{"session_id":"sid-ENVOFF","hook_event_name":"SessionStart"}' >/dev/null 2>&1
  ok_missing 09 "$ws/hooks/sessions/sid-ENVOFF" || true
  cleanup_fixture "$pair"
}

# Dedup: two SessionStart fires for the same sid within 5s — second logs dedup.
case_10_dedup_suppresses_double_fire() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=committed --hooks=workspace --yes >/dev/null
  local sid="sid-DEDUP-$$"
  SKILL_IMPROVE_ROOT="$ws/hooks" bash "$ws/hooks/scripts/skill-improve-session-start.sh" \
    <<<"{\"session_id\":\"$sid\",\"hook_event_name\":\"SessionStart\"}" >/dev/null 2>&1
  # Immediate second fire within window must be suppressed.
  local second
  second=$(SKILL_IMPROVE_ROOT="$ws/hooks" bash "$ws/hooks/scripts/skill-improve-session-start.sh" \
    <<<"{\"session_id\":\"$sid\",\"hook_event_name\":\"SessionStart\"}" 2>&1)
  echo "$second" | grep -q '"continue":true' || fail 10 "second fire missing continue:true: $second"
  ok_contains 10 "$ws/hooks/logs/skill-improve.log" "dedup SessionStart sid=$sid" || true
  cleanup_fixture "$pair"
}

# Dedup window can be set to 0 to disable dedup (advanced override).
case_11_dedup_disabled_via_env() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=committed --hooks=workspace --yes >/dev/null
  local sid="sid-NODEDUP-$$"
  SKILL_IMPROVE_ROOT="$ws/hooks" SKILL_IMPROVE_DEDUP_WINDOW_SECONDS=0 \
    bash "$ws/hooks/scripts/skill-improve-session-start.sh" \
    <<<"{\"session_id\":\"$sid\",\"hook_event_name\":\"SessionStart\"}" >/dev/null 2>&1
  SKILL_IMPROVE_ROOT="$ws/hooks" SKILL_IMPROVE_DEDUP_WINDOW_SECONDS=0 \
    bash "$ws/hooks/scripts/skill-improve-session-start.sh" \
    <<<"{\"session_id\":\"$sid\",\"hook_event_name\":\"SessionStart\"}" >/dev/null 2>&1
  # No "dedup" line should appear for this sid.
  if grep -q "dedup SessionStart sid=$sid" "$ws/hooks/logs/skill-improve.log" 2>/dev/null; then
    fail 11 "dedup line found despite WINDOW=0"
  fi
  cleanup_fixture "$pair"
}

# Dedup is per-event: SessionStart and Stop for the same sid must both fire.
case_12_dedup_per_event() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=committed --hooks=workspace --yes >/dev/null
  local sid="sid-PER-$$"
  SKILL_IMPROVE_ROOT="$ws/hooks" bash "$ws/hooks/scripts/skill-improve-session-start.sh" \
    <<<"{\"session_id\":\"$sid\",\"hook_event_name\":\"SessionStart\"}" >/dev/null 2>&1
  SKILL_IMPROVE_ROOT="$ws/hooks" bash "$ws/hooks/scripts/skill-improve-session-end.sh" \
    <<<"{\"session_id\":\"$sid\",\"hook_event_name\":\"Stop\"}" >/dev/null 2>&1
  # Stop must NOT have been deduped — its log line should be present.
  ok_contains 12 "$ws/hooks/logs/skill-improve.log" "Stop sid=$sid" || true
  cleanup_fixture "$pair"
}

# Dedup marker file is created on first fire under STATE.
case_13_dedup_marker_created() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=committed --hooks=workspace --yes >/dev/null
  local sid="sid-MARK-$$"
  SKILL_IMPROVE_ROOT="$ws/hooks" bash "$ws/hooks/scripts/skill-improve-session-start.sh" \
    <<<"{\"session_id\":\"$sid\",\"hook_event_name\":\"SessionStart\"}" >/dev/null 2>&1
  # State dir must contain at least one .dedup-* marker.
  local found=0
  for m in "$ws/hooks/state/".dedup-*; do
    [[ -e "$m" ]] && found=1
  done
  [[ $found -eq 1 ]] || fail 13 "no .dedup-* marker created under $ws/hooks/state/"
  cleanup_fixture "$pair"
}

# Workspace and user installs are isolated from each other (writes don't cross).
case_14_workspace_and_user_isolated() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}" home="${pair#*:}"
  run_boot "$pair" --preset=pod --mode=committed --hooks=workspace --yes >/dev/null
  # Now also install user-global hooks alongside.
  run_boot "$pair" --preset=portable --mode=committed --hooks=user --yes >/dev/null
  # Fire workspace SessionStart — should ONLY write to ws.
  SKILL_IMPROVE_ROOT="$ws/hooks" bash "$ws/hooks/scripts/skill-improve-session-start.sh" \
    <<<'{"session_id":"sid-WS-ONLY","hook_event_name":"SessionStart"}' >/dev/null 2>&1
  ok_dir  14 "$ws/hooks/sessions/sid-WS-ONLY" || true
  ok_missing 14 "$home/.agents/hooks/sessions/sid-WS-ONLY" || true
  # Fire user-level SessionStart (different sid) — should ONLY write to user.
  SKILL_IMPROVE_ROOT="$home/.agents/hooks" bash "$home/.agents/hooks/scripts/skill-improve-session-start.sh" \
    <<<'{"session_id":"sid-USR-ONLY","hook_event_name":"SessionStart"}' >/dev/null 2>&1
  ok_dir  14 "$home/.agents/hooks/sessions/sid-USR-ONLY" || true
  ok_missing 14 "$ws/hooks/sessions/sid-USR-ONLY" || true
  cleanup_fixture "$pair"
}

# Uninstall --user removes ~/.agents/hooks tree entirely.
case_15_user_uninstall_removes_user_hooks() {
  local pair; pair="$(mkfixture)"
  local home="${pair#*:}"
  run_boot "$pair" --preset=portable --mode=committed --hooks=user --yes >/dev/null
  ok_file 15 "$home/.agents/hooks/hooks.json" || true
  run_boot "$pair" --uninstall --user --yes >/dev/null
  ok_missing 15 "$home/.agents/hooks/hooks.json" || true
  ok_missing 15 "$home/.agents/hooks/scripts" || true
  cleanup_fixture "$pair"
}

# ---- runner ----------------------------------------------------------------
echo ""
echo "=== Assert.IQ hooks E2E ==="
echo "Pack: $PACK"
echo ""

run_case "01 workspace install layout"             case_01_workspace_install_layout
run_case "02 user install layout"                  case_02_user_install_layout
run_case "03 workspace SessionStart writes local"  case_03_workspace_session_start_writes_local
run_case "04 user SessionStart writes ~/.agents"   case_04_user_session_start_writes_user
run_case "05 PostToolUse telemetry continues"      case_05_post_tool_telemetry_continues
run_case "06 PostToolUse detect appends log"       case_06_post_tool_detect_appends_log
run_case "07 Stop writes log entry"                case_07_stop_writes_log
run_case "08 config.enabled=false no-op"           case_08_config_disabled_noop
run_case "09 SKILL_IMPROVE_DISABLED=1 no-op"       case_09_env_disabled_noop
run_case "10 dedup suppresses double-fire"         case_10_dedup_suppresses_double_fire
run_case "11 DEDUP_WINDOW_SECONDS=0 disables"      case_11_dedup_disabled_via_env
run_case "12 dedup is per-event"                   case_12_dedup_per_event
run_case "13 dedup marker created under state/"    case_13_dedup_marker_created
run_case "14 workspace/user installs isolated"     case_14_workspace_and_user_isolated
run_case "15 --uninstall --user clears hooks"      case_15_user_uninstall_removes_user_hooks

echo ""
echo "=== Summary ==="
echo "  Pass: $(grn $CASES_PASS)"
echo "  Fail: $(red $CASES_FAIL)"
if (( CASES_FAIL > 0 )); then
  echo ""
  echo "Failures:"
  printf '%s\n' "${FAIL_LOG[@]}"
  exit 1
fi
exit 0
