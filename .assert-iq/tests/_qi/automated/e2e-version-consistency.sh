#!/bin/bash
# E2E: Version consistency checks

PASSED=0
FAILED=0

test_version_file() {
    if [ -f VERSION ]; then
        echo "✅ E2E-16: VERSION file exists"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_version_is_alpha1() {
    if grep -q "1.7.0-alpha1" VERSION; then
        echo "✅ E2E-17: VERSION is 1.7.0-alpha1"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_changelog_has_alpha_entry() {
    if grep -q "1.7.0-alpha1" CHANGELOG.md; then
        echo "✅ E2E-18: CHANGELOG has v1.7.0-alpha1 entry"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_changelog_documents_features() {
    if grep -q "Decision Confidence Calibration" CHANGELOG.md; then
        echo "✅ E2E-19: CHANGELOG documents new features"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

echo "=== E2E: Version Consistency ==="
test_version_file
test_version_is_alpha1
test_changelog_has_alpha_entry
test_changelog_documents_features

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"

if [ $FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
