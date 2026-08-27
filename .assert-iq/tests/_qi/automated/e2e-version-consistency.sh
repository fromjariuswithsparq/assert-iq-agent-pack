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

# Version-agnostic on purpose. This previously hard-asserted "1.7.0-alpha1",
# which silently rotted the moment VERSION moved to 2.x — the check failed for
# being stale rather than for any real inconsistency. Assert the invariant
# instead: VERSION is semver AND the CHANGELOG's newest entry matches it.
test_version_is_semver() {
    local version
    version="$(tr -d ' \t\r\n' < VERSION)"
    if printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then
        echo "✅ E2E-17a: VERSION is valid semver ($version)"
        ((PASSED++))
    else
        echo "❌ E2E-17a FAILED: VERSION is not valid semver ('$version')"
        ((FAILED++))
    fi
}

test_version_matches_changelog_head() {
    local version newest
    version="$(tr -d ' \t\r\n' < VERSION)"
    # Newest RELEASED heading. A leading "## [Unreleased]" section is standard
    # Keep-a-Changelog practice and must not be mistaken for a release, or
    # documenting work-in-progress would fail this check.
    newest="$(grep -oE '^## \[[^]]+\]' CHANGELOG.md \
              | sed 's/^## \[//; s/\]$//' \
              | grep -viE '^unreleased$' \
              | head -1)"
    if [ "$version" = "$newest" ]; then
        echo "✅ E2E-17b: VERSION matches newest CHANGELOG entry ($version)"
        ((PASSED++))
    else
        echo "❌ E2E-17b FAILED: VERSION ('$version') != newest CHANGELOG entry ('$newest')"
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

# Skill/instruction counts are asserted in three live entry-point docs that are
# read every session. They drifted silently (MANIFEST said 27 skills and 5
# instruction files while the repo shipped 30 and 6). Only these precise,
# single-purpose claims are checked — version-history prose elsewhere in the
# READMEs legitimately cites historical counts.
test_doc_counts_match_reality() {
    local skills instr ok=1
    skills=$(find .github/skills -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    instr=$(find .github/instructions -name '*.instructions.md' | wc -l | tr -d ' ')

    grep -q "^\*\*Skill count\*\*: ${skills} " MANIFEST.md \
        || { echo "   MANIFEST.md '**Skill count**' != ${skills}"; ok=0; }
    grep -q "^\*\*Instruction count\*\*: ${instr} " MANIFEST.md \
        || { echo "   MANIFEST.md '**Instruction count**' != ${instr}"; ok=0; }
    grep -q "all ${skills} QI skills" CLAUDE.md \
        || { echo "   CLAUDE.md does not say 'all ${skills} QI skills'"; ok=0; }
    grep -q "^${skills} QI skills under" AGENTS.md \
        || { echo "   AGENTS.md does not say '${skills} QI skills under'"; ok=0; }

    if [ $ok -eq 1 ]; then
        echo "✅ E2E-19b: Doc counts match reality (${skills} skills, ${instr} instruction files)"
        ((PASSED++))
    else
        echo "❌ E2E-19b FAILED: doc counts out of sync with repo contents"
        ((FAILED++))
    fi
}

# The version-history table in README.assert-iq.md must carry a row for the
# CURRENT version.
#
# bump_doc_banners in make-release.sh deliberately leaves version-history rows
# alone -- it must not rewrite historical entries -- so the row describing the
# work being shipped stayed labelled "**Unreleased**" indefinitely. v2.1.0
# published that way: the table's newest row said "Unreleased" while every
# banner on the page said v2.1.0.
#
# Keyed on "a row exists for $VERSION", NOT on "no Unreleased row exists", so an
# Unreleased row is still perfectly legal while work accumulates between
# releases. It only becomes a failure once VERSION names a release the table
# does not describe -- which is exactly release time.
test_version_history_has_current_row() {
    local version
    version="$(tr -d ' \t\r\n' < VERSION)"
    if [ ! -f README.assert-iq.md ]; then
        echo "❌ E2E-17c FAILED: README.assert-iq.md not found"
        FAILED=$((FAILED+1))
        return
    fi
    if grep -qF "| **$version** |" README.assert-iq.md; then
        echo "✅ E2E-17c: version-history table has a row for $version"
        PASSED=$((PASSED+1))
    else
        echo "❌ E2E-17c FAILED: README.assert-iq.md version-history table has no"
        echo "   '| **$version** |' row. If the work is described by an"
        echo "   '**Unreleased**' row, rename it to **$version** (and the matching"
        echo "   <strong> row in README.assert-iq.html), then re-run"
        echo "   scripts/generate-documentation-html.py."
        FAILED=$((FAILED+1))
    fi
}

echo "=== E2E: Version Consistency ==="
test_version_file
test_version_is_semver
test_version_matches_changelog_head
test_version_history_has_current_row
test_changelog_has_alpha_entry
test_changelog_documents_features
test_doc_counts_match_reality

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"

if [ $FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
