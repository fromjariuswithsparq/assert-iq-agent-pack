#!/bin/bash
# Integration: Dream cycle provenance tracking

set -e
PASSED=0
FAILED=0

PROVENANCE_FILE=".assert-iq/dreaming/provenance.json"
SNAPSHOTS_DIR=".assert-iq/dreaming/.snapshots"

test_provenance_exists() {
    if [ -f "$PROVENANCE_FILE" ]; then
        echo "✅ Test 1: Provenance log exists"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 1 FAILED: Missing provenance file"
        ((FAILED++))
        return 1
    fi
}

test_provenance_valid_json() {
    if jq . "$PROVENANCE_FILE" > /dev/null 2>&1; then
        echo "✅ Test 2: Provenance JSON is valid"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 2 FAILED: Invalid JSON"
        ((FAILED++))
        return 1
    fi
}

test_provenance_has_schema() {
    if jq -e '.schema_version and .dream_cycles' "$PROVENANCE_FILE" > /dev/null 2>&1; then
        echo "✅ Test 3: Provenance has schema_version and dream_cycles"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 3 FAILED: Missing schema fields"
        ((FAILED++))
        return 1
    fi
}

test_snapshots_directory_exists() {
    if [ -d "$SNAPSHOTS_DIR" ]; then
        echo "✅ Test 4: Snapshots directory exists"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 4 FAILED: Missing snapshots dir"
        ((FAILED++))
        return 1
    fi
}

test_snapshots_directory_writable() {
    if [ -w "$SNAPSHOTS_DIR" ]; then
        echo "✅ Test 5: Snapshots directory is writable"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 5 FAILED: Snapshots dir not writable"
        ((FAILED++))
        return 1
    fi
}

echo "=== Integration: Dream Provenance ==="
test_provenance_exists || true
test_provenance_valid_json || true
test_provenance_has_schema || true
test_snapshots_directory_exists || true
test_snapshots_directory_writable || true

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"
[ $FAILED -eq 0 ]
