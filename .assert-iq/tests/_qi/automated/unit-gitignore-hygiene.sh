#!/bin/bash
# ============================================================================
# UNIT: .gitignore hygiene for pack-shipped ignore files
# ============================================================================
# WHY THIS EXISTS
#
# Trial mode hides the pack from git by listing every installed path in
# .git/info/exclude. But git resolves ignore rules by PRECEDENCE, and a
# .gitignore deeper in the tree outranks .git/info/exclude. So a negation
# (`!pattern`) inside a pack-shipped .gitignore silently RE-INCLUDES that file
# and defeats trial mode entirely.
#
# That is not hypothetical. These shipped with catch-alls plus negations:
#
#   .assert-iq/agent-runs/.gitignore        ->  *  + !.gitignore + !index.json
#   .assert-iq/business-metrics/.gitignore  ->  *.json + !baseline.json + ...
#
# and after `bootstrap --mode=trial` those four files showed up in `git status`
# in the host repo, even though all four were correctly listed in
# .git/info/exclude. `git check-ignore -v` named the negation as the winning
# rule. Fix: express only what should be ignored (additive patterns), never
# "everything except X".
#
# Rule enforced: no negation patterns in any .gitignore the pack installs into
# a target workspace. The pack's OWN root .gitignore is exempt -- it is never
# copied into a workspace, so it cannot fight a host repo's exclude file.
#
# PORTABILITY: bash 3.2 safe. Run from the repo root.
# ============================================================================

PASSED=0
FAILED=0

pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

echo "=== UNIT: .gitignore hygiene (pack-shipped ignore files) ==="
echo ""

# Only files under .assert-iq/ get copied into a target workspace.
found=0
offenders=""
while IFS= read -r gi; do
  [ -n "$gi" ] || continue
  found=$((found + 1))
  negations="$(grep -n '^[[:space:]]*!' "$gi" 2>/dev/null)"
  if [ -n "$negations" ]; then
    offenders="$offenders
  $gi"
    while IFS= read -r n; do
      [ -n "$n" ] && offenders="$offenders
      $n"
    done <<< "$negations"
  fi
done <<< "$(find .assert-iq -name '.gitignore' 2>/dev/null | sort)"

if [ "$found" -eq 0 ]; then
  fail "no pack-shipped .gitignore files found under .assert-iq/ (did the layout change?)"
else
  if [ -z "$offenders" ]; then
    pass "no negation patterns in $found pack-shipped .gitignore file(s)"
  else
    fail "negation pattern(s) found - these defeat trial mode:$offenders"
    echo "      A deeper .gitignore outranks .git/info/exclude, so '!file' re-includes"
    echo "      the file and it appears in git status after --mode=trial."
    echo "      Express what SHOULD be ignored instead of 'everything except X'."
  fi
fi

# The two files that actually regressed: assert their real behaviour, not just
# the absence of a '!'. Seed files must stay trackable in committed mode while
# generated artifacts stay ignored.
if git rev-parse --git-dir >/dev/null 2>&1; then
  seed_ok=1
  for f in .assert-iq/agent-runs/index.json \
           .assert-iq/agent-runs/.gitignore \
           .assert-iq/business-metrics/baseline.json \
           .assert-iq/business-metrics/.gitignore; do
    [ -e "$f" ] || continue
    if git check-ignore -q "$f" 2>/dev/null; then
      fail "seed file is ignored in the pack repo (committed mode would lose it): $f"
      seed_ok=0
    fi
  done
  [ "$seed_ok" -eq 1 ] && pass "seed files remain trackable (committed mode intact)"

  gen_ok=1
  for f in .assert-iq/agent-runs/probe-20260101-000000.specialist-outputs.json \
           .assert-iq/business-metrics/reports/probe.html; do
    if ! git check-ignore -q "$f" 2>/dev/null; then
      fail "generated artifact is NOT ignored: $f"
      gen_ok=0
    fi
  done
  [ "$gen_ok" -eq 1 ] && pass "generated artifacts still ignored (runs + reports)"
else
  fail "not inside a git work tree; cannot verify ignore behaviour"
fi

echo ""
echo "=== Results: $PASSED PASS, $FAILED FAIL ==="
[ $FAILED -eq 0 ] && exit 0 || exit 1
