#!/bin/bash
# Documentation Integrity Validator
# Ensures all Assert.IQ documentation is consistent, linked, and complete.

# WHY NOT ((PASSED++)):
# Under `set -e` an arithmetic command's exit status is the FALSEness of its
# value, and `((PASSED++))` evaluates to the PRE-increment value. The very first
# 0 -> 1 increment therefore returns 0 -> exit status 1 -> `set -e` kills the
# script. This validator silently ran 1 of its 18 checks and exited 1 on every
# platform until this was fixed. Use VAR=$((VAR+1)), which always returns 0.
set -e

PASSED=0
FAILED=0

echo "=== Documentation Integrity Validation ==="
echo ""

# Check 1: README.assert-iq.md exists and has v1.7.0 section
echo -n "Check 1: README.assert-iq.md has Calibration section... "
if grep -q "Calibration & Reproducibility (v1.7.0+)" README.assert-iq.md; then
    echo "✅"
    PASSED=$((PASSED+1))
else
    echo "❌"
    FAILED=$((FAILED+1))
fi

# Check 2: qi-foundation.instructions.md has Decision Confidence section
echo -n "Check 2: qi-foundation.instructions.md updated with Decision Confidence... "
if grep -q "Decision Confidence Calibration & Reproducibility (v1.7.0+)" .github/instructions/qi-foundation.instructions.md; then
    echo "✅"
    PASSED=$((PASSED+1))
else
    echo "❌"
    FAILED=$((FAILED+1))
fi

# Check 3: qi-oracle.instructions.md has Oracle Verdicts section
echo -n "Check 3: qi-oracle.instructions.md updated with Oracle Verdicts... "
if grep -q "Oracle Verdicts & Calibration Integration (v1.7.0+)" .github/instructions/qi-oracle.instructions.md; then
    echo "✅"
    PASSED=$((PASSED+1))
else
    echo "❌"
    FAILED=$((FAILED+1))
fi

# Check 4: qi-signal-emission.instructions.md has Verdict Recording section
echo -n "Check 4: qi-signal-emission.instructions.md updated with Verdict Recording... "
if grep -q "Verdict Recording Requirements (v1.7.0+)" .github/instructions/qi-signal-emission.instructions.md; then
    echo "✅"
    PASSED=$((PASSED+1))
else
    echo "❌"
    FAILED=$((FAILED+1))
fi

# Check 5: All 3 core skills have verdict recording sections
echo -n "Check 5: risk-assess-pr has Verdict Recording section... "
if grep -q "Verdict Recording (v1.7.0+)" .github/skills/risk-assess-pr/SKILL.md; then
    echo "✅"
    PASSED=$((PASSED+1))
else
    echo "❌"
    FAILED=$((FAILED+1))
fi

echo -n "Check 6: release-confidence has Verdict Recording section... "
if grep -q "Verdict Recording (v1.7.0+)" .github/skills/release-confidence/SKILL.md; then
    echo "✅"
    PASSED=$((PASSED+1))
else
    echo "❌"
    FAILED=$((FAILED+1))
fi

echo -n "Check 7: analyze-escaped-defect has Verdict Linkage section... "
if grep -q "Verdict Linkage & Calibration (v1.7.0+)" .github/skills/analyze-escaped-defect/SKILL.md; then
    echo "✅"
    PASSED=$((PASSED+1))
else
    echo "❌"
    FAILED=$((FAILED+1))
fi

# Check 8: VERDICT_INTEGRATION_GUIDE exists
echo -n "Check 8: VERDICT_INTEGRATION_GUIDE.md exists... "
if [ -f .assert-iq/VERDICT_INTEGRATION_GUIDE.md ]; then
    echo "✅"
    PASSED=$((PASSED+1))
else
    echo "❌"
    FAILED=$((FAILED+1))
fi

# Check 9: VERSION is well-formed. Deliberately version-AGNOSTIC: this check
# used to hardcode "1.7.0-alpha1", so it started failing the moment the pack
# shipped 2.0.0 and stayed red through every release after -- a stale assertion
# reporting a defect in itself, not in the pack.
PACK_VERSION="$(head -n1 VERSION 2>/dev/null | tr -d '[:space:]')"
echo -n "Check 9: VERSION is well-formed semver ($PACK_VERSION)... "
if printf '%s' "$PACK_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
    echo "✅"
    PASSED=$((PASSED+1))
else
    echo "❌"
    FAILED=$((FAILED+1))
fi

# Check 10: the CHANGELOG documents the version currently in VERSION -- either
# as a released heading or still under [Unreleased] mid-cycle.
echo -n "Check 10: CHANGELOG.md documents $PACK_VERSION (or [Unreleased])... "
if grep -qE "^## \[($(printf '%s' "$PACK_VERSION" | sed 's/\./\\./g')|Unreleased)\]" CHANGELOG.md; then
    echo "✅"
    PASSED=$((PASSED+1))
else
    echo "❌"
    FAILED=$((FAILED+1))
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
