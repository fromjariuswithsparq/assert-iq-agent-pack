#!/bin/bash
# E2E: Uninstall cleanup verification (zero orphans)

PASSED=0
FAILED=0

test_bootstrap_cleanup_paths_v17_verdicts() {
    if grep -q "\.assert-iq/verdicts" scripts/bootstrap.sh; then
        echo "✅ E2E-9: verdicts in cleanup array"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_bootstrap_cleanup_paths_v17_analysis() {
    if grep -q "\.assert-iq/analysis" scripts/bootstrap.sh; then
        echo "✅ E2E-10: analysis in cleanup array"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_bootstrap_cleanup_paths_v17_regression() {
    if grep -q "\.assert-iq/tests/_qi/regression" scripts/bootstrap.sh; then
        echo "✅ E2E-11: regression in cleanup array"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_bootstrap_cleanup_tree_roots() {
    if bash -n scripts/bootstrap.sh > /dev/null 2>&1; then
        echo "✅ E2E-12: bootstrap.sh syntax valid"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

test_orphan_paths_not_in_gitignore() {
    if [ -f .assert-iq/verdicts/.gitignore ]; then
        echo "✅ E2E-13: Verdict .gitignore present"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

# Both branches previously incremented PASSED, so this assertion could never
# fail — it reported success whether or not snapshots were actually ignored.
# Memory snapshots can contain client-proprietary content, so a real check
# matters here.
# Assert the real invariant (is the path actually ignored?) rather than grepping
# one specific .gitignore file — the rule may legitimately live in the root
# .gitignore or a nested one.
test_snapshots_not_tracked() {
    if git check-ignore -q .assert-iq/dreaming/.snapshots/probe.tar.gz 2>/dev/null; then
        echo "✅ E2E-14: Memory snapshots are git-ignored"
        ((PASSED++))
    else
        echo "❌ E2E-14 FAILED: .assert-iq/dreaming/.snapshots/ is not git-ignored (memory tarballs would be committed)"
        ((FAILED++))
    fi
}

test_archive_not_tracked() {
    if grep -q "archive/" .assert-iq/verdicts/.gitignore; then
        echo "✅ E2E-15: Verdict archive gitignored"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

echo "=== E2E: Uninstall Cleanup Verification ==="
test_bootstrap_cleanup_paths_v17_verdicts
test_bootstrap_cleanup_paths_v17_analysis
test_bootstrap_cleanup_paths_v17_regression
test_bootstrap_cleanup_tree_roots
test_orphan_paths_not_in_gitignore
test_snapshots_not_tracked
test_archive_not_tracked

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"

if [ $FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
