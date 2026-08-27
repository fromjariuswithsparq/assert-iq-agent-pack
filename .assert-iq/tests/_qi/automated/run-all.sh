#!/bin/bash
# ============================================================================
# Run the full Assert.IQ pack test suite.
# ============================================================================
# Usage (from anywhere):
#   bash .assert-iq/tests/_qi/automated/run-all.sh
#
# Ordering matters: the dependency preflight runs FIRST, because a missing
# Python makes downstream tests report misleading failures ("malformed JSON"
# when the interpreter is simply absent).
#
# e2e-agent-parity.sh is reported SEPARATELY from the regression gate. It is a
# strict forcing function for cross-harness agent drift and is expected to fail
# until the Copilot orchestrator question is settled. Its status is printed but
# does not mask regressions in the rest of the suite.
#
# Exit codes:
#   0 = all regression tests passed (parity may still be divergent — see output)
#   1 = at least one regression test failed
# ============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
cd "$REPO_ROOT"

# Shared helpers: resolves a usable Python 3 (python3 -> python -> py -3).
. "$SCRIPT_DIR/lib/aiq-test-lib.sh"

PARITY="e2e-agent-parity.sh"
PREFLIGHT="unit-test-dependencies.sh"

pass=0
fail=0
failed_names=()

run_one() {
  local file="$1" name
  name="$(basename "$file")"
  # .py tests run under the RESOLVED interpreter: `python3` does not exist on
  # Windows even when Python is installed correctly.
  if case "$name" in *.py) aiq_py "$file" ;; *) bash "$file" ;; esac >/dev/null 2>&1; then
    printf '  PASS  %s\n' "$name"
    pass=$((pass + 1))
  else
    printf '  FAIL  %s\n' "$name"
    fail=$((fail + 1))
    failed_names+=("$name")
  fi
}

echo "════════════════════════════════════════════════════════════════"
echo " Assert.IQ pack test suite"
echo " repo: $REPO_ROOT"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "── Preflight ──"
if bash "$SCRIPT_DIR/$PREFLIGHT"; then
  echo ""
else
  echo ""
  echo "✗ Dependency preflight FAILED. Fix the environment before trusting"
  echo "  any result below — missing tools surface as bogus assertion failures."
  echo ""
  exit 1
fi

echo "── Regression suite ──"
for f in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/*.py; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  case "$name" in
    run-all.sh|"$PARITY"|"$PREFLIGHT") continue ;;
  esac
  run_one "$f"
done

echo ""
echo "── Cross-harness parity (reported separately) ──"
if bash "$SCRIPT_DIR/$PARITY" >/dev/null 2>&1; then
  parity_status="IN PARITY"
else
  parity_status="DIVERGENT — run: bash .assert-iq/tests/_qi/automated/$PARITY"
fi
echo "  $parity_status"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " Regression: $pass passed, $fail failed"
echo " Parity:     $parity_status"
echo "════════════════════════════════════════════════════════════════"

if [ $fail -ne 0 ]; then
  printf ' failing: %s\n' "${failed_names[*]}"
  exit 1
fi
exit 0
