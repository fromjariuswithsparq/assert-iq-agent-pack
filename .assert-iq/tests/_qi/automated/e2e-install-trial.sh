#!/bin/bash
# E2E: Verify installed v1.7.0 features in workspace

PASSED=0
FAILED=0

# Test in current workspace where pack is installed
test_v17_verdict_infrastructure() {
    if [ -d .assert-iq/verdicts ]; then
        echo "✅ E2E-1: Verdicts directory present"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_v17_provenance() {
    if [ -f .assert-iq/dreaming/provenance.json ]; then
        echo "✅ E2E-2: Provenance log present"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_v17_analysis_tools() {
    if [ -f .assert-iq/analysis/calibration.py ]; then
        echo "✅ E2E-3: Analysis tools present"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_v17_regression_tests() {
    if [ -f .assert-iq/tests/_qi/regression/golden-corpus.jsonl ]; then
        echo "✅ E2E-4: Regression tests present"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_v17_config_blocks() {
    if grep -q "verdicts:" .assert-iq/config.yaml; then
        echo "✅ E2E-5: Config blocks present"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_v16_oracle_intact() {
    if [ -d .assert-iq/oracles ]; then
        echo "✅ E2E-6: Oracle layer intact"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_v16_memory_intact() {
    if [ -d .assert-iq/memory ]; then
        echo "✅ E2E-7: Memory store intact"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_archive_gitignored() {
    if [ -f .assert-iq/verdicts/.gitignore ]; then
        echo "✅ E2E-8: Verdict archive protection present"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

echo "=== E2E: Workspace Installation Verification ==="
test_v17_verdict_infrastructure
test_v17_provenance
test_v17_analysis_tools
test_v17_regression_tests
test_v17_config_blocks
test_v16_oracle_intact
test_v16_memory_intact
test_archive_gitignored

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"

if [ $FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
