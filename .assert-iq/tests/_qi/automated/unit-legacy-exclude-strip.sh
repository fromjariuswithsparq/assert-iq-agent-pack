#!/bin/bash
# UNIT: uninstall must remove an UNMARKED Assert.IQ block from .git/info/exclude.
#
# WHY THIS EXISTS
#
# strip_exclude_block only ever matched the exact managed marker pair
# (`# >>> assert-iq trial mode (managed) >>>` … `<<<`). Installs predating
# those markers -- and agents that hand-rolled the block from the bootstrap
# skill's prose instead of running the script -- wrote a section with a
# human-worded header and no delimiters. Uninstall could not see it, printed
# "No Assert.IQ managed block found -- nothing to remove", and exited 0.
#
# The block stayed, so `.github/`, `.vscode/` and `.claude/` remained excluded
# forever. The user's OWN files at those paths -- a GitHub Actions workflow --
# were then silently invisible to git long after the pack was gone. Found on a
# real project: an uninstalled workspace where `git check-ignore` still
# reported .github/workflows/ci.yml as ignored.
#
# The removal is allowlist-driven, so the other half of the contract matters
# just as much: entries the USER put in the same file must survive.

# NOT APPLICABLE ON WINDOWS (exit 2).
#
# This is the only test in the suite that EXECUTES scripts/bootstrap.sh rather
# than grepping it, and bootstrap.sh deliberately REFUSES to run under
# MSYS/Git Bash: it exits 2 and tells the user to run bootstrap.ps1 instead,
# because MSYS process creation makes a full install take 9+ minutes.
#
# So on Windows the install and uninstall this test depends on never happen,
# and 4 of its 11 assertions fail against an exclude file nothing ever touched.
# That is a false alarm about a real feature -- the same shape of bug the pack
# keeps fixing (P5/P6 telling consumers their install was broken;
# /assert-iq-tailor blaming a missing check-environment.sh).
#
# Forcing it with AIQ_ALLOW_MSYS=1 is not the answer either: the test drives
# two installs and two uninstalls, which is 30+ minutes of MSYS process churn
# for a code path Windows users are explicitly told not to take.
#
# Exit 2 = "not applicable", the same three-valued convention
# e2e-agent-parity.sh uses off-pack. run-all.sh reports it as SKIP, NOT as a
# pass -- a run that never checked must never be reported as green.
#
# Windows coverage for the same behaviour belongs in a bootstrap.ps1 twin.
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    echo "=== UNIT: legacy .git/info/exclude block removal ==="
    echo "⏭️  SKIP — not applicable on Windows (MSYS)."
    echo "   This test executes scripts/bootstrap.sh, which refuses to run here"
    echo "   by design (exit 2; use bootstrap.ps1 — MSYS installs take 9+ min)."
    echo "   Nothing is wrong with the pack or this checkout."
    echo "   Run it on macOS/Linux/WSL for real coverage."
    exit 2
    ;;
esac

_AIQ_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_AIQ_LIB_DIR/../../../.." && pwd)"
PASSED=0
FAILED=0

ws=""
cleanup() { [ -n "$ws" ] && rm -rf "$ws"; }
trap cleanup EXIT

make_ws() {
  ws="$(mktemp -d)"
  ( cd "$ws" && git init -q . && echo x > f && git add -A \
      && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
}

# The exact shape found in the wild, plus user-owned lines on both sides.
write_legacy_exclude() {
  cat > "$ws/.git/info/exclude" <<'X'
# git ls-files --others --exclude-from=.git/info/exclude
# Lines that start with '#' are comments.

# my own local ignores
scratch/
*.local

# --- Assert.IQ / Quality Intelligence pack (installed in trial mode) ---
# Local-only tooling, deliberately kept out of the published repo.
# To publish it later: scripts/bootstrap.sh --graduate, then remove these lines.
.assert-iq/
.github/
.claude/
.vscode/
AGENTS.md
CLAUDE.md
# MY comment directly beneath the pack entries
my-notes/
X
}

check() { # desc, condition-result
  if [ "$2" -eq 0 ]; then
    echo "✅ $1"; PASSED=$((PASSED+1))
  else
    echo "❌ $1"; FAILED=$((FAILED+1))
  fi
}

echo "=== UNIT: legacy .git/info/exclude block removal ==="

make_ws
bash "$REPO_ROOT/scripts/bootstrap.sh" --mode=trial --yes --workspace="$ws" >/dev/null 2>&1 \
  || ( cd "$ws" && bash "$REPO_ROOT/scripts/bootstrap.sh" --mode=trial --yes >/dev/null 2>&1 )
write_legacy_exclude
( cd "$ws" && bash "$REPO_ROOT/scripts/bootstrap.sh" --uninstall --yes ) >"$ws/out.txt" 2>&1

excl="$ws/.git/info/exclude"

grep -q "Assert.IQ" "$excl"; check "Assert.IQ header removed" $((1 - $?))
grep -qE '^\.assert-iq/$|^AGENTS\.md$|^CLAUDE\.md$' "$excl"; check "pack path entries removed" $((1 - $?))

grep -q '^scratch/$' "$excl"; check "user entry above the block survived" $?
grep -q '^\*\.local$' "$excl"; check "second user entry survived" $?
grep -q '^my-notes/$' "$excl"; check "user entry below the block survived" $?
grep -q 'MY comment directly beneath' "$excl"; check "user comment adjacent to pack entries survived" $?
grep -q 'git ls-files --others' "$excl"; check "git's own default header survived" $?

# The whole point: the user's own paths are visible to git again.
( cd "$ws" && git check-ignore -q .github/workflows/ci.yml ); check ".github/ no longer ignored" $((1 - $?))
( cd "$ws" && git check-ignore -q .vscode/settings.json ); check ".vscode/ no longer ignored" $((1 - $?))

grep -qi "nothing to remove" "$ws/out.txt"; check "does NOT report 'nothing to remove'" $((1 - $?))

# A file with no Assert.IQ content must be left byte-identical.
make_ws
printf '# mine\nfoo/\nbar/\n' > "$ws/.git/info/exclude"
before="$(cat "$ws/.git/info/exclude")"
bash "$REPO_ROOT/scripts/bootstrap.sh" --mode=trial --yes --workspace="$ws" >/dev/null 2>&1 \
  || ( cd "$ws" && bash "$REPO_ROOT/scripts/bootstrap.sh" --mode=trial --yes >/dev/null 2>&1 )
( cd "$ws" && bash "$REPO_ROOT/scripts/bootstrap.sh" --uninstall --yes ) >/dev/null 2>&1
after="$(cat "$ws/.git/info/exclude")"
[ "$before" = "$after" ]; check "an exclude file with no pack content is untouched" $?

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"
[ $FAILED -eq 0 ]
