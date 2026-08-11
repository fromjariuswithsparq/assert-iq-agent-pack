#!/bin/bash
# Unit tests for verdict schema validation

PASSED=0
FAILED=0

SCHEMA_FILE=".assert-iq/signal-schema.json"

test_schema_loads() {
    if jq . "$SCHEMA_FILE" > /dev/null 2>&1; then
        echo "✅ Test 1: Schema loads without JSON parse errors"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 1 FAILED: Schema has JSON syntax errors"
        ((FAILED++))
        return 1
    fi
}

test_verdict_object_exists() {
    if jq -e '.properties.verdict' "$SCHEMA_FILE" > /dev/null 2>&1; then
        echo "✅ Test 2: Verdict object exists in schema"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 2 FAILED: No verdict object in schema"
        ((FAILED++))
        return 1
    fi
}

test_verdict_required_fields() {
    # Check for required verdict fields
    local required_fields=("verdict_id" "verdict_type" "verdict_band" "verdict_score" "layer_scores" "issued_at")
    local all_present=true
    
    for field in "${required_fields[@]}"; do
        if ! jq -e ".properties.verdict.properties.${field}" "$SCHEMA_FILE" > /dev/null 2>&1; then
            echo "  Missing field: $field"
            all_present=false
        fi
    done
    
    if $all_present; then
        echo "✅ Test 3: All required verdict fields present"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 3 FAILED: Some required fields missing"
        ((FAILED++))
        return 1
    fi
}

test_verdict_band_enum() {
    if jq -e '.properties.verdict.properties.verdict_band | select(.enum | length > 0)' "$SCHEMA_FILE" > /dev/null 2>&1; then
        echo "✅ Test 4: Verdict band has enum constraint"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 4 FAILED: Verdict band missing enum"
        ((FAILED++))
        return 1
    fi
}

test_verdict_score_range() {
    if jq -e '.properties.verdict.properties.verdict_score | select(.minimum == 0.0 and .maximum == 1.0)' "$SCHEMA_FILE" > /dev/null 2>&1; then
        echo "✅ Test 5: Verdict score has 0.0-1.0 range constraint"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 5 FAILED: Verdict score range incorrect"
        ((FAILED++))
        return 1
    fi
}

# Run all tests
echo "=== Verdict Schema Unit Tests ==="
test_schema_loads || true
test_verdict_object_exists || true
test_verdict_required_fields || true
test_verdict_band_enum || true
test_verdict_score_range || true

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"

if [ $FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
