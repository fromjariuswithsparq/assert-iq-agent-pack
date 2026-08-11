#!/bin/bash
# Documentation Integrity Validator
# Ensures all Assert.IQ documentation is consistent, linked, and complete.

set -e

PASSED=0
FAILED=0

echo "=== Documentation Integrity Validation ==="
echo ""

# Check 1: README.assert-iq.md exists and has v1.7.0 section
echo -n "Check 1: README.assert-iq.md has Calibration section... "
if grep -q "Calibration & Reproducibility (v1.7.0+)" README.assert-iq.md; then
    echo "✅"
    ((PASSED++))
else
    echo "❌"
    ((FAILED++))
fi

# Check 2: qi-foundation.instructions.md has Decision Confidence section
echo -n "Check 2: qi-foundation.instructions.md updated with Decision Confidence... "
if grep -q "Decision Confidence Calibration & Reproducibility (v1.7.0+)" .github/instructions/qi-foundation.instructions.md; then
    echo "✅"
    ((PASSED++))
else
    echo "❌"
    ((FAILED++))
fi

# Check 3: qi-oracle.instructions.md has Oracle Verdicts section
echo -n "Check 3: qi-oracle.instructions.md updated with Oracle Verdicts... "
if grep -q "Oracle Verdicts & Calibration Integration (v1.7.0+)" .github/instructions/qi-oracle.instructions.md; then
    echo "✅"
    ((PASSED++))
else
    echo "❌"
    ((FAILED++))
fi

# Check 4: qi-signal-emission.instructions.md has Verdict Recording section
echo -n "Check 4: qi-signal-emission.instructions.md updated with Verdict Recording... "
if grep -q "Verdict Recording Requirements (v1.7.0+)" .github/instructions/qi-signal-emission.instructions.md; then
    echo "✅"
    ((PASSED++))
else
    echo "❌"
    ((FAILED++))
fi

# Check 5: All 3 core skills have verdict recording sections
echo -n "Check 5: risk-assess-pr has Verdict Recording section... "
if grep -q "Verdict Recording (v1.7.0+)" .github/skills/risk-assess-pr/SKILL.md; then
    echo "✅"
    ((PASSED++))
else
    echo "❌"
    ((FAILED++))
fi

echo -n "Check 6: release-confidence has Verdict Recording section... "
if grep -q "Verdict Recording (v1.7.0+)" .github/skills/release-confidence/SKILL.md; then
    echo "✅"
    ((PASSED++))
else
    echo "❌"
    ((FAILED++))
fi

echo -n "Check 7: analyze-escaped-defect has Verdict Linkage section... "
if grep -q "Verdict Linkage & Calibration (v1.7.0+)" .github/skills/analyze-escaped-defect/SKILL.md; then
    echo "✅"
    ((PASSED++))
else
    echo "❌"
    ((FAILED++))
fi

# Check 8: VERDICT_INTEGRATION_GUIDE exists
echo -n "Check 8: VERDICT_INTEGRATION_GUIDE.md exists... "
if [ -f .assert-iq/VERDICT_INTEGRATION_GUIDE.md ]; then
    echo "✅"
    ((PASSED++))
else
    echo "❌"
    ((FAILED++))
fi

# Check 9: Version file exists and is 1.7.0-alpha1
echo -n "Check 9: VERSION file is 1.7.0-alpha1... "
if [ -f VERSION ] && grep -q "1.7.0-alpha1" VERSION; then
    echo "✅"
    ((PASSED++))
else
    echo "❌"
    ((FAILED++))
fi

# Check 10: CHANGELOG has 1.7.0-alpha1 entry
echo -n "Check 10: CHANGELOG.md documents v1.7.0-alpha1... "
if grep -q "\[1.7.0-alpha1\]" CHANGELOG.md; then
    echo "✅"
    ((PASSED++))
else
    echo "❌"
    ((FAILED++))
fi

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "✅ All documentation integrity checks PASSED"
    exit 0
else
    echo "❌ Some checks failed. See above."
    exit 1
fi
