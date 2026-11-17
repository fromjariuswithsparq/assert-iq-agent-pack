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

# BOTH INSTALLERS, ONE HALF PER PLATFORM.
#
# The fix shipped on both platforms in v2.3.0 -- _strip_legacy_block in
# bootstrap.sh, Remove-LegacyBlockLines in bootstrap.ps1 -- but this test only
# ever drove the bash half, and reported NOT APPLICABLE (exit 2) on Windows.
# So the PowerShell implementation, the one Windows users actually run, was
# unguarded: a refactor could have broken it and nothing would have gone red.
#
# It is now parameterized over the installer, the same shape as
# unit-overwrite-snapshot.sh, and AIQ_TEST_INSTALLERS narrows the run:
#
#   macOS / Linux / WSL   sh   (plus the ps1 half if pwsh is on PATH)
#   Windows (Git Bash)    ps1  (run-all.sh sets AIQ_TEST_INSTALLERS=ps1)
#
# The sh half is excluded on Windows by DEFAULT rather than by refusal:
# bootstrap.sh deliberately exits 2 under MSYS and tells the user to run
# bootstrap.ps1, because MSYS process creation makes a full install take
# 9+ minutes -- and this test drives two installs and two uninstalls. Forcing
# it with AIQ_TEST_INSTALLERS="sh ps1" works (AIQ_ALLOW_MSYS is exported
# below) but costs 30+ minutes for a code path Windows users are told not to
# take.

_AIQ_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_AIQ_LIB_DIR/../../../.." && pwd)"
PASSED=0
FAILED=0
# Only consulted if a maintainer deliberately forces the sh half under MSYS.
export AIQ_ALLOW_MSYS=1

ws=""
cleanup() { [ -n "$ws" ] && rm -rf "$ws" "$ws.out"; }
trap cleanup EXIT

# Windows-native path for pwsh under Git Bash; unchanged elsewhere.
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

# LINE ENDINGS ARE NOT EVIDENCE.
#
# bootstrap.ps1 writes the exclude file with [Environment]::NewLine, so on
# Windows every line ends CRLF while git's own default header and the fixture
# below are LF. An anchored `grep '^scratch/$'` then fails on a line that is
# present and correct. That misfire happened during review of this very test
# and read exactly like data loss. Match against a CR-stripped copy instead.
norm() { tr -d '\r' < "$1"; }

make_ws() {
  [ -n "$ws" ] && rm -rf "$ws" "$ws.out"
  ws="$(mktemp -d)"
  ( cd "$ws" && git init -q . && echo x > f && git add -A \
      && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
}

run_install() { # <which>
  if [ "$1" = sh ]; then
    bash "$REPO_ROOT/scripts/bootstrap.sh" --mode=trial --yes --workspace="$ws" </dev/null >/dev/null 2>&1 \
      || ( cd "$ws" && bash "$REPO_ROOT/scripts/bootstrap.sh" --mode=trial --yes </dev/null >/dev/null 2>&1 )
  else
    pwsh -NoProfile -File "$(native "$REPO_ROOT/scripts/bootstrap.ps1")" \
      -Mode trial -Yes -Workspace "$(native "$ws")" </dev/null >/dev/null 2>&1
  fi
}

run_uninstall() { # <which> <stdout-file>
  if [ "$1" = sh ]; then
    ( cd "$ws" && bash "$REPO_ROOT/scripts/bootstrap.sh" --uninstall --yes ) </dev/null >"$2" 2>&1
  else
    pwsh -NoProfile -File "$(native "$REPO_ROOT/scripts/bootstrap.ps1")" \
      -Uninstall -Yes -Workspace "$(native "$ws")" </dev/null >"$2" 2>&1
  fi
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

exercise() { # <which>
  local which="$1"
  echo ""
  echo "--- bootstrap.$which ---"

  make_ws
  run_install "$which"
  write_legacy_exclude
  run_uninstall "$which" "$ws.out"

  local excl="$ws/.git/info/exclude"

  norm "$excl" | grep -q "Assert.IQ"; check "[$which] Assert.IQ header removed" $((1 - $?))
  norm "$excl" | grep -qE '^\.assert-iq/$|^AGENTS\.md$|^CLAUDE\.md$'
  check "[$which] pack path entries removed" $((1 - $?))

  norm "$excl" | grep -q '^scratch/$'; check "[$which] user entry above the block survived" $?
  norm "$excl" | grep -q '^\*\.local$'; check "[$which] second user entry survived" $?
  norm "$excl" | grep -q '^my-notes/$'; check "[$which] user entry below the block survived" $?
  norm "$excl" | grep -q 'MY comment directly beneath'
  check "[$which] user comment adjacent to pack entries survived" $?
  norm "$excl" | grep -q 'git ls-files --others'; check "[$which] git's own default header survived" $?

  # The whole point: the user's own paths are visible to git again.
  ( cd "$ws" && git check-ignore -q .github/workflows/ci.yml )
  check "[$which] .github/ no longer ignored" $((1 - $?))
  ( cd "$ws" && git check-ignore -q .vscode/settings.json )
  check "[$which] .vscode/ no longer ignored" $((1 - $?))

  norm "$ws.out" | grep -qi "nothing to remove"
  check "[$which] does NOT report 'nothing to remove'" $((1 - $?))

  # A file with no Assert.IQ content must come back with its own content and
  # nothing else.
  #
  # Compared CR-stripped, because the two installers differ here and only one
  # of them can be byte-exact: bootstrap.ps1 rewrites the whole file through
  # [Environment]::NewLine when it appends the managed block, so an LF exclude
  # file comes back CRLF (at INSTALL time -- uninstall is not the mutator).
  # Verified harmless: git strips the trailing CR when reading exclude files,
  # so `foo/` still matches, and .git/info/exclude is untracked, so nothing
  # diffs. Asserting byte-equality here would fail the ps1 half over a
  # difference with no consequence, which is the same false alarm this test
  # was rewritten to stop producing.
  make_ws
  printf '# mine\nfoo/\nbar/\n' > "$ws/.git/info/exclude"
  local before after
  before="$(norm "$ws/.git/info/exclude")"
  run_install "$which"
  run_uninstall "$which" /dev/null
  after="$(norm "$ws/.git/info/exclude")"
  [ "$before" = "$after" ]; check "[$which] an exclude file with no pack content is untouched" $?
}

echo "=== UNIT: legacy .git/info/exclude block removal ==="

# Default halves per platform; AIQ_TEST_INSTALLERS overrides (see header).
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) _default_installers="ps1" ;;
  *)                    _default_installers="sh ps1" ;;
esac

ran=0
for which in ${AIQ_TEST_INSTALLERS:-$_default_installers}; do
  if [ "$which" = ps1 ] && ! command -v pwsh >/dev/null 2>&1; then
    echo "⏭️  pwsh not on PATH -- bootstrap.ps1 half skipped"
    continue
  fi
  exercise "$which"
  ran=$((ran + 1))
done

echo ""
if [ "$ran" -eq 0 ]; then
  # Nothing ran. On Windows that means no PowerShell host, and bootstrap.sh is
  # refused here by design -- so there is no half left to drive. Report NOT
  # APPLICABLE (exit 2), which run-all.sh prints as SKIP. A run that never
  # checked must never be reported as green.
  echo "⏭️  SKIP — no usable installer half on this platform."
  echo "   Nothing is wrong with the pack or this checkout."
  exit 2
fi

echo "Results: $PASSED PASS, $FAILED FAIL"
[ $FAILED -eq 0 ]
