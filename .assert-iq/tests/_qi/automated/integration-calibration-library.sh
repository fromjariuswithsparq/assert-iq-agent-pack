#!/bin/bash
# Integration: Calibration library availability

set -e
PASSED=0
FAILED=0

CALIBRATION_PY=".assert-iq/analysis/calibration.py"
MEMORY_SANITY_PY=".assert-iq/analysis/memory-sanity.py"
AUDIT_VERDICT_SH=".assert-iq/analysis/audit-verdict.sh"

test_calibration_exists() {
    if [ -x "$CALIBRATION_PY" ]; then
        echo "✅ Test 1: calibration.py exists and is executable"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 1 FAILED: calibration.py missing or not executable"
        ((FAILED++))
        return 1
    fi
}

test_memory_sanity_exists() {
    if [ -x "$MEMORY_SANITY_PY" ]; then
        echo "✅ Test 2: memory-sanity.py exists and is executable"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 2 FAILED: memory-sanity.py missing or not executable"
        ((FAILED++))
        return 1
    fi
}

test_audit_verdict_exists() {
    if [ -x "$AUDIT_VERDICT_SH" ]; then
        echo "✅ Test 3: audit-verdict.sh exists and is executable"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 3 FAILED: audit-verdict.sh missing or not executable"
        ((FAILED++))
        return 1
    fi
}

test_calibration_python_syntax() {
    if python3 -m py_compile "$CALIBRATION_PY" 2>/dev/null; then
        echo "✅ Test 4: calibration.py has valid Python syntax"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 4 FAILED: Invalid Python syntax"
        ((FAILED++))
        return 1
    fi
}

test_memory_sanity_python_syntax() {
    if python3 -m py_compile "$MEMORY_SANITY_PY" 2>/dev/null; then
        echo "✅ Test 5: memory-sanity.py has valid Python syntax"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 5 FAILED: Invalid Python syntax"
        ((FAILED++))
        return 1
    fi
}

echo "=== Integration: Calibration Library ==="
test_calibration_exists || true
test_memory_sanity_exists || true
test_audit_verdict_exists || true
test_calibration_python_syntax || true
test_memory_sanity_python_syntax || true

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"
[ $FAILED -eq 0 ]
