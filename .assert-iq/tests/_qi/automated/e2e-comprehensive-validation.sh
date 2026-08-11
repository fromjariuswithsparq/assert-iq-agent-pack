#!/bin/bash
# E2E: Comprehensive v1.7.0 feature validation

PASSED=0
FAILED=0

test_all_unit_tests_pass() {
    if bash .assert-iq/tests/_qi/automated/unit-verdict-schema.sh > /dev/null 2>&1 && \
       bash .assert-iq/tests/_qi/automated/unit-audit-verdict.sh > /dev/null 2>&1; then
        echo "✅ E2E-20: All unit tests pass"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_all_integration_tests_pass() {
    if bash .assert-iq/tests/_qi/automated/integration-verdict-recording.sh > /dev/null 2>&1 && \
       bash .assert-iq/tests/_qi/automated/integration-dream-provenance.sh > /dev/null 2>&1 && \
       bash .assert-iq/tests/_qi/automated/integration-calibration-library.sh > /dev/null 2>&1 && \
       bash .assert-iq/tests/_qi/automated/integration-config-validation.sh > /dev/null 2>&1; then
        echo "✅ E2E-21: All integration tests pass"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_verdict_architecture_complete() {
    if [ -f .assert-iq/verdicts/VERDICTS.md ] && \
       [ -f .assert-iq/verdicts/index.json ] && \
       [ -d .assert-iq/verdicts/archive ]; then
        echo "✅ E2E-22: Verdict sink complete"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_memory_versioning_complete() {
    if [ -f .assert-iq/dreaming/provenance.json ] && \
       [ -d .assert-iq/dreaming/.snapshots ]; then
        echo "✅ E2E-23: Memory versioning infrastructure complete"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_analysis_suite_complete() {
    if [ -f .assert-iq/analysis/calibration.py ] && \
       [ -f .assert-iq/analysis/memory-sanity.py ] && \
       [ -f .assert-iq/analysis/audit-verdict.sh ]; then
        echo "✅ E2E-24: Analysis suite complete"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_configuration_complete() {
    if grep -q "verdicts:" .assert-iq/config.yaml && \
       grep -q "calibration:" .assert-iq/config.yaml && \
       grep -q "memory_sanity:" .assert-iq/config.yaml && \
       grep -q "regression_testing:" .assert-iq/config.yaml && \
       grep -q "dreaming_provenance:" .assert-iq/config.yaml; then
        echo "✅ E2E-25: Configuration blocks complete"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_governance_updated() {
    if grep -q "Audit Trail & Reproducibility" .assert-iq/governance.md; then
        echo "✅ E2E-26: Governance updated with Audit Trail section"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_no_regressions_on_v16() {
    if [ -d .assert-iq/oracles ] && \
       [ -d .assert-iq/memory ] && \
       [ -d .github/skills ]; then
        echo "✅ E2E-27: v1.6.1 features intact (no regressions)"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

echo "=== E2E: Comprehensive Validation ==="
test_all_unit_tests_pass
test_all_integration_tests_pass
test_verdict_architecture_complete
test_memory_versioning_complete
test_analysis_suite_complete
test_configuration_complete
test_governance_updated
test_no_regressions_on_v16

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"

if [ $FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
