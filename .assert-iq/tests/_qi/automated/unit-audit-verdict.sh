#!/bin/bash
# Unit tests for audit-verdict script

set -e

PASSED=0
FAILED=0

AUDIT_SCRIPT=".assert-iq/analysis/audit-verdict.sh"
VERDICTS_DIR=".assert-iq/verdicts"
TEMP_DIR=$(mktemp -d)

trap "rm -rf $TEMP_DIR" EXIT

test_script_exists() {
    if [ -x "$AUDIT_SCRIPT" ]; then
        echo "✅ Test 1: Audit verdict script exists and is executable"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 1 FAILED: Script not found or not executable"
        ((FAILED++))
        return 1
    fi
}

test_verdicts_directory_exists() {
    if [ -d "$VERDICTS_DIR" ]; then
        echo "✅ Test 2: Verdicts directory exists"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 2 FAILED: Verdicts directory missing"
        ((FAILED++))
        return 1
    fi
}

test_archive_structure() {
    if [ -d "$VERDICTS_DIR/archive" ]; then
        echo "✅ Test 3: Verdict archive directory exists"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 3 FAILED: Archive directory missing"
        ((FAILED++))
        return 1
    fi
}

test_index_file_exists() {
    if [ -f "$VERDICTS_DIR/index.json" ]; then
        echo "✅ Test 4: Verdict index file exists"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 4 FAILED: Index file missing"
        ((FAILED++))
        return 1
    fi
}

test_verdicts_md_exists() {
    if [ -f "$VERDICTS_DIR/VERDICTS.md" ]; then
        echo "✅ Test 5: VERDICTS.md audit trail exists"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 5 FAILED: Audit trail file missing"
        ((FAILED++))
        return 1
    fi
}

# Run all tests
echo "=== Audit Verdict Unit Tests ==="
test_script_exists || true
test_verdicts_directory_exists || true
test_archive_structure || true
test_index_file_exists || true
test_verdicts_md_exists || true

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"

if [ $FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
