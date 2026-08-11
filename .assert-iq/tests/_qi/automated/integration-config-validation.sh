#!/bin/bash
# Integration: Configuration and governance validation

set -e
PASSED=0
FAILED=0

CONFIG_FILE=".assert-iq/config.yaml"
GOVERNANCE_FILE=".assert-iq/governance.md"
SIGNAL_SCHEMA=".assert-iq/signal-schema.json"

test_config_exists() {
    if [ -f "$CONFIG_FILE" ]; then
        echo "✅ Test 1: config.yaml exists"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 1 FAILED: Missing config.yaml"
        ((FAILED++))
        return 1
    fi
}

test_config_has_verdicts_block() {
    if grep -q "verdicts:" "$CONFIG_FILE"; then
        echo "✅ Test 2: config.yaml has verdicts block"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 2 FAILED: Missing verdicts block"
        ((FAILED++))
        return 1
    fi
}

test_config_has_calibration_block() {
    if grep -q "calibration:" "$CONFIG_FILE"; then
        echo "✅ Test 3: config.yaml has calibration block"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 3 FAILED: Missing calibration block"
        ((FAILED++))
        return 1
    fi
}

test_governance_has_audit_section() {
    if grep -q "Audit Trail & Reproducibility" "$GOVERNANCE_FILE"; then
        echo "✅ Test 4: governance.md has Audit Trail section"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 4 FAILED: Missing Audit Trail section"
        ((FAILED++))
        return 1
    fi
}

test_signal_schema_has_verdict_object() {
    if jq -e '.properties.verdict' "$SIGNAL_SCHEMA" > /dev/null 2>&1; then
        echo "✅ Test 5: signal-schema.json has verdict object"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 5 FAILED: Missing verdict object"
        ((FAILED++))
        return 1
    fi
}

echo "=== Integration: Config & Governance ==="
test_config_exists || true
test_config_has_verdicts_block || true
test_config_has_calibration_block || true
test_governance_has_audit_section || true
test_signal_schema_has_verdict_object || true

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"
[ $FAILED -eq 0 ]
