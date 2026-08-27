#!/bin/bash
# ============================================================================
# UNIT: Test-harness dependency preflight
# ============================================================================
# WHY THIS EXISTS
#
# The suite depends on external tools it never declared or checked. When they
# are absent the failures are actively misleading rather than obvious, because
# most call sites look like:
#
#   if <json check> > /dev/null 2>&1; then pass; else fail "malformed JSON"; fi
#
# A missing interpreter is reported as "malformed JSON". Failing here, first
# and loudly, separates "your environment is incomplete" from "the pack is
# broken".
#
# PORTABILITY: bash 3.2 compatible (macOS /bin/bash). No mapfile, no `local -n`.
# ============================================================================

_AIQ_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_AIQ_LIB_DIR/lib/aiq-test-lib.sh"

PASSED=0
FAILED=0
MISSING=""

pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

echo "=== UNIT: Test Dependency Preflight ==="
echo ""

# --- bash ------------------------------------------------------------------
# 3.2 is the floor because macOS still ships it as /bin/bash. Tests must not
# use mapfile/readarray, `local -n`, associative arrays, or ${var,,}.
bash_major="${BASH_VERSINFO[0]:-0}"
if [ "$bash_major" -ge 3 ]; then
  pass "bash ${BASH_VERSION} (>= 3.2 required; macOS ships 3.2)"
else
  fail "bash ${BASH_VERSION} is too old; 3.2+ required"
  MISSING="$MISSING bash>=3.2"
fi

# --- a working Python 3 ----------------------------------------------------
# Probe by EXECUTING, not by `command -v`: on Windows the Microsoft Store ships
# a `python3` stub that resolves on PATH but fails on invocation, and the
# python.org installer provides python.exe with no python3.exe at all.
if aiq_resolve_python; then
  pyver="$(aiq_py -c 'import sys; print(".".join(map(str, sys.version_info[:3])))' 2>/dev/null)"
  pass "python 3 resolved as '$(aiq_python_label)' (${pyver})"
  if aiq_py -c 'import json' >/dev/null 2>&1; then
    pass "python json module importable"
  else
    fail "python cannot import json"
    MISSING="$MISSING python-json"
  fi
else
  fail "no working Python 3 found (tried: python3, python, py -3)"
  echo "      macOS/Linux: install python3 (macOS: xcode-select --install)"
  echo "      Windows:     winget install Python.Python.3.12, then open a NEW"
  echo "                   terminal so PATH picks up the interpreter."
  echo "      Note: a 'python3' that prints a Microsoft Store hint is a stub,"
  echo "      not an interpreter — this check executes candidates on purpose."
  MISSING="$MISSING python3"
fi

# --- git -------------------------------------------------------------------
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  pass "git present and cwd is inside a work tree"
else
  fail "git missing, or cwd is not a git work tree (git check-ignore assertions need it)"
  MISSING="$MISSING git"
fi

# --- macOS bash 3.2 portability guard --------------------------------------
# macOS still ships /bin/bash 3.2, and the pack must run there unchanged. These
# constructs are newer and fail hard on 3.2:
#   mapfile / readarray  (4.0+)   local -n  (4.3+)
#   declare -A           (4.0+)   ${var,,}  (4.0+)
# This guard exists because that regression was actually introduced once: new
# tests used mapfile and `local -n`, which would have broken every macOS run
# while passing on Windows and Linux.
b4_hits="$(grep -nE '(mapfile|readarray|local[[:space:]]+-n[[:space:]]|declare[[:space:]]+-A)'              "$_AIQ_LIB_DIR"/*.sh "$_AIQ_LIB_DIR"/lib/*.sh 2>/dev/null            | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'            | grep -v 'unit-test-dependencies.sh' || true)"
if [ -z "$b4_hits" ]; then
  pass "no bash-4-only constructs in the suite (macOS 3.2 safe)"
else
  fail "bash-4-only construct(s) found - these break macOS /bin/bash 3.2:"
  printf '%s
' "$b4_hits" | sed 's/^/        /'
  MISSING="$MISSING bash4-construct"
fi

# --- runtime sinks must exist ---------------------------------------------
# Several suites assert on runtime sinks (the verdict archive, dream snapshots,
# business-impact reports). All three are git-ignored EMPTY directories, so git
# cannot carry them and a fresh clone never has them -- they are created by
# install.sh / install.ps1 / scripts/bootstrap.*.
#
# This used to hard-fail with "run the installer first", which was wrong twice
# over: contributors are told not to install the pack into the pack repo
# itself, and CI checks out a clean tree, so the suite went red on exactly the
# setups it is supposed to protect. They are empty directories, so just create
# them -- cheap, idempotent, git-ignored, and it mutates nothing tracked.
#
# This does NOT paper over an installer that forgets to create them: that is
# asserted where it belongs, against a real install, by case 41 in
# tests/_qi/automated/e2e-bootstrap.{sh,ps1}.
created_dirs=""
for d in .assert-iq/verdicts/archive .assert-iq/dreaming/.snapshots .assert-iq/business-metrics/reports; do
  if [ ! -d "$d" ]; then
    mkdir -p "$d" 2>/dev/null || true
    created_dirs="$created_dirs $d"
  fi
done
still_missing=""
for d in .assert-iq/verdicts/archive .assert-iq/dreaming/.snapshots .assert-iq/business-metrics/reports; do
  [ -d "$d" ] || still_missing="$still_missing $d"
done
if [ -z "$still_missing" ]; then
  if [ -n "$created_dirs" ]; then
    pass "runtime sinks present (created:$created_dirs)"
  else
    pass "runtime sinks present"
  fi
else
  fail "could not create runtime sink(s) (check permissions):$still_missing"
  MISSING="$MISSING runtime-sinks"
fi

# --- jq must NOT be required ----------------------------------------------
# Regression guard. jq used to be a second undeclared dependency; every use was
# simple JSON validation/lookup now handled by the Python helpers in
# lib/aiq-test-lib.sh. Reintroducing jq re-breaks stock macOS and Windows.
# Only real invocations count. Excluded, or the guard flags its own docs and
# the tests that deliberately prove the no-jq path works:
#   * this file
#   * comment lines
#   * `command -v jq` / `which jq` capability PROBES (asking is not depending)
#   * `jq` as an ARGUMENT rather than a command (e.g. `make_shim jq` in
#     unit-install-settings-merge.sh, which hides jq to prove Python can merge)
#   * jq inside a quoted message
# The pattern therefore requires jq at a command position: start of line or
# after a pipe/semicolon/&&/subshell, optionally preceded by `!` or `if`.
jq_hits="$(grep -nE '(^|[|;&(]|\bif |\bthen |\bdo |! )[[:space:]]*jq[[:space:]]+[^"'"'"']' \
             "$_AIQ_LIB_DIR"/*.sh "$_AIQ_LIB_DIR"/lib/*.sh 2>/dev/null \
           | grep -v 'unit-test-dependencies.sh' \
           | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
           | grep -vE 'command -v jq|which jq' || true)"
if [ -n "$jq_hits" ]; then
  fail "a test reintroduced a jq dependency:"
  printf '%s
' "$jq_hits" | sed 's/^/        /'
  MISSING="$MISSING (jq-reintroduced)"
else
  pass "no test requires jq (JSON handled by the Python helpers)"
fi

echo ""
echo "=== Results: $PASSED PASS, $FAILED FAIL ==="

if [ $FAILED -eq 0 ]; then
  echo "✅ All test dependencies satisfied."
  exit 0
fi

echo ""
echo "Missing/broken:$MISSING"
echo "Other failures in this suite may be caused by the above, not by the pack."
exit 1
