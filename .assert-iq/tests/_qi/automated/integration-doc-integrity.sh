#!/usr/bin/env bash
# ============================================================================
# INTEGRATION: run scripts/validate-documentation-integrity.sh as a gate.
# ============================================================================
# WHY THIS WRAPPER EXISTS
#
# The validator lives in scripts/, and run-all.sh only discovers tests inside
# .assert-iq/tests/_qi/automated/. So nothing ever ran it, and it rotted twice
# over without anyone noticing:
#
#   1. `set -e` plus `((PASSED++))` made it exit 1 after its FIRST check. It
#      reported "Check 1 ... OK" and stopped -- 1 of 10 checks, on every
#      platform, for as long as the file existed.
#   2. Check 9 hardcoded VERSION == "1.7.0-alpha1", so it went red the moment
#      the pack shipped 2.0.0 and stayed red -- a stale assertion reporting a
#      defect in itself rather than in the pack.
#
# A checker nobody runs is not a checker. This wrapper puts it in the regression
# gate so both failure modes surface immediately.
#
# PORTABILITY: bash 3.2. Runs from the repo root regardless of cwd.
# ============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/validate-documentation-integrity.sh"

echo "=== INTEGRATION: documentation integrity validator ==="
echo ""

if [ ! -f "$VALIDATOR" ]; then
    echo "FAIL missing $VALIDATOR"
    echo ""
    echo "=== Results: 0 PASS, 1 FAIL ==="
    exit 1
fi

# The validator asserts on paths relative to the repo root.
cd "$REPO_ROOT" || exit 1

out="$(bash "$VALIDATOR" 2>&1)"
rc=$?
printf '%s\n' "$out" | sed 's/^/  /'

# Guard against the silent-truncation failure mode specifically: a run that
# exits 0 but only emitted a check or two would otherwise look like a pass.
checks="$(printf '%s\n' "$out" | grep -cE '^Check [0-9]+:')"
echo ""
if [ "$rc" -ne 0 ]; then
    echo "FAIL validator exited $rc"
    echo ""
    echo "=== Results: 0 PASS, 1 FAIL ==="
    exit 1
fi
if [ "${checks:-0}" -lt 5 ]; then
    echo "FAIL validator emitted only ${checks:-0} check line(s) -- it exited 0 but"
    echo "     stopped early (the classic 'set -e' + ((VAR++)) truncation)."
    echo ""
    echo "=== Results: 0 PASS, 1 FAIL ==="
    exit 1
fi

echo "PASS validator ran $checks checks and all passed"
echo ""
echo "=== Results: 1 PASS, 0 FAIL ==="
exit 0
