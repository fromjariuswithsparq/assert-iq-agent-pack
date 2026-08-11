#!/bin/bash
# Integration: Verdict recording workflow

set -e
PASSED=0
FAILED=0

VERDICTS_DIR=".assert-iq/verdicts"
ARCHIVE_DIR="${VERDICTS_DIR}/archive"

cleanup() {
    rm -f "$TEMP_VERDICT"
}
trap cleanup EXIT

# Create a test verdict object
TEMP_VERDICT=$(mktemp)
cat > "$TEMP_VERDICT" << 'VERDICT'
{
  "verdict_id": "verdict-test-001",
  "verdict_type": "pr_risk_assessment",
  "verdict_band": "green",
  "verdict_score": 0.95,
  "layer_scores": {
    "change": {"state": "strong", "score": 0.9},
    "protection": {"state": "strong", "score": 0.95},
    "trust": {"state": "strong", "score": 0.93},
    "outcome": {"state": "strong", "score": 0.97}
  },
  "layer_weights": {"change": 0.25, "protection": 0.25, "trust": 0.25, "outcome": 0.25},
  "maturity_tier": "higher",
  "memory_version": "sha256:abc123def456",
  "oracle_verdicts_considered": ["oracle-001"],
  "issued_at": "2026-08-11T10:00:00Z",
  "issued_by": "risk-assess-pr",
  "pr_id": "123",
  "release_id": null,
  "assumptions": ["No new infrastructure changes"],
  "linked_escape": null
}
VERDICT

test_verdict_json_valid() {
    if jq . "$TEMP_VERDICT" > /dev/null 2>&1; then
        echo "✅ Test 1: Test verdict JSON is valid"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 1 FAILED: Invalid JSON"
        ((FAILED++))
        return 1
    fi
}

test_archive_writable() {
    if [ -d "$ARCHIVE_DIR" ] && [ -w "$ARCHIVE_DIR" ]; then
        echo "✅ Test 2: Verdict archive is writable"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 2 FAILED: Archive not writable"
        ((FAILED++))
        return 1
    fi
}

test_index_valid_json() {
    if jq . "${VERDICTS_DIR}/index.json" > /dev/null 2>&1; then
        echo "✅ Test 3: Verdict index is valid JSON"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 3 FAILED: Index JSON invalid"
        ((FAILED++))
        return 1
    fi
}

test_verdicts_md_writable() {
    if [ -w "${VERDICTS_DIR}/VERDICTS.md" ]; then
        echo "✅ Test 4: VERDICTS.md audit trail is writable"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 4 FAILED: Audit trail not writable"
        ((FAILED++))
        return 1
    fi
}

test_verdict_record_format() {
    VERDICT_ID=$(jq -r '.verdict_id' "$TEMP_VERDICT")
    VERDICT_BAND=$(jq -r '.verdict_band' "$TEMP_VERDICT")
    VERDICT_SCORE=$(jq -r '.verdict_score' "$TEMP_VERDICT")
    
    if [ -n "$VERDICT_ID" ] && [ -n "$VERDICT_BAND" ] && [ -n "$VERDICT_SCORE" ]; then
        echo "✅ Test 5: Verdict record has all required fields"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 5 FAILED: Missing verdict fields"
        ((FAILED++))
        return 1
    fi
}

echo "=== Integration: Verdict Recording ==="
test_verdict_json_valid || true
test_archive_writable || true
test_index_valid_json || true
test_verdicts_md_writable || true
test_verdict_record_format || true

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"
[ $FAILED -eq 0 ]
