#!/usr/bin/env bash
# Assert.IQ bootstrap E2E test driver.
# Runs the orthogonal 23-case matrix from the approved plan against
# scripts/bootstrap.sh + install.sh, in disposable git fixtures, with
# isolated $HOME so user-scope writes are sandboxed.
#
# Usage:
#   bash tests/_qi/automated/e2e-bootstrap.sh [--keep] [pattern]
#     --keep     keep fixture dirs on exit for inspection
#     pattern    only run cases whose label matches the regex
#
# Each case is a function `case_NN_label`. Returns: PASS / FAIL / SKIP.

set -u

PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
KEEP=0
PATTERN=""
for arg in "$@"; do
  case "$arg" in
    --keep) KEEP=1 ;;
    *) PATTERN="$arg" ;;
  esac
done

# Color
red()   { printf '\033[31m%s\033[0m' "$*"; }
grn()   { printf '\033[32m%s\033[0m' "$*"; }
ylw()   { printf '\033[33m%s\033[0m' "$*"; }

CASES_PASS=0
CASES_FAIL=0
CASES_SKIP=0
declare -a FAIL_LOG=()

# ---- Fixture management ----------------------------------------------------
mkfixture() {
  # Creates a sandboxed workspace + isolated $HOME. Echoes "WS:HOME".
  local ws home
  ws="$(mktemp -d "${TMPDIR:-/tmp}/aiq-ws.XXXXXX")"
  home="$(mktemp -d "${TMPDIR:-/tmp}/aiq-home.XXXXXX")"
  ( cd "$ws" && git init -q && git config user.email t@t && git config user.name t \
    && git commit --allow-empty -q -m init )
  echo "$ws:$home"
}

cleanup_fixture() {
  local pair="$1"
  [[ $KEEP -eq 1 ]] && { echo "  (kept: $pair)"; return; }
  local ws="${pair%:*}" home="${pair#*:}"
  rm -rf "$ws" "$home"
}

# Run bootstrap with isolated HOME + workspace. Captures stdout/stderr.
# Args: pair, then bootstrap args
run_boot() {
  local pair="$1"; shift
  local ws="${pair%:*}" home="${pair#*:}"
  HOME="$home" bash "$PACK/scripts/bootstrap.sh" --workspace="$ws" "$@" </dev/null 2>&1
}

# Run install.sh from within a copy of the pack (since it operates on its
# own directory, not on a workspace). Returns pair "PACK_COPY:HOME".
mk_pack_copy() {
  local copy home
  copy="$(mktemp -d "${TMPDIR:-/tmp}/aiq-pack.XXXXXX")"
  home="$(mktemp -d "${TMPDIR:-/tmp}/aiq-home.XXXXXX")"
  # Copy enough of the pack to support install.sh: root + .github + .claude + hooks + scripts
  # But skip .git so it doesn't try to git-anything weird.
  # pipefail: surface any tar failure (unreadable file, permissions) instead
  # of silently producing an empty $copy that makes downstream asserts misleading.
  if ! ( set -o pipefail; cd "$PACK" && tar -cf - --exclude='.git' --exclude='node_modules' . | ( cd "$copy" && tar -xf - ) ); then
    echo "  mk_pack_copy: tar pipe failed (copy=$copy)" >&2
    return 1
  fi
  echo "$copy:$home"
}

# ---- Assertion helpers -----------------------------------------------------
fail() {
  local case_label="$1"; shift
  local msg="$*"
  FAIL_LOG+=("  $(red FAIL) $case_label: $msg")
  CASES_FAIL=$((CASES_FAIL+1))
}

assert_file_exists()   { [[ -e "$2" ]] || { fail "$1" "expected to exist: $2"; return 1; }; return 0; }
assert_file_missing()  { [[ ! -e "$2" ]] || { fail "$1" "expected missing: $2"; return 1; }; return 0; }
assert_dir_exists()    { [[ -d "$2" ]] || { fail "$1" "expected dir: $2"; return 1; }; return 0; }
assert_dir_missing()   { [[ ! -d "$2" ]] || { fail "$1" "expected dir missing: $2"; return 1; }; return 0; }
assert_contains()      { grep -Fq "$3" "$2" 2>/dev/null || { fail "$1" "expected '$3' in $2"; return 1; }; return 0; }
assert_not_contains()  { ! grep -Fq "$3" "$2" 2>/dev/null || { fail "$1" "expected NOT '$3' in $2"; return 1; }; return 0; }
assert_equal_sha()     {
  local label="$1" a="$2" b="$3"
  local sa sb
  sa="$(shasum -a 256 "$a" | awk '{print $1}')"
  sb="$(shasum -a 256 "$b" | awk '{print $1}')"
  [[ "$sa" == "$sb" ]] || { fail "$label" "sha mismatch: $a vs $b"; return 1; }
  return 0
}

run_case() {
  local label="$1" fn="$2"
  if [[ -n "$PATTERN" && ! "$label" =~ $PATTERN ]]; then return; fi
  local before_fail=$CASES_FAIL
  printf '  %-55s ' "$label"
  if "$fn"; then
    if [[ $CASES_FAIL -gt $before_fail ]]; then
      printf '%s\n' "$(red FAIL)"
    else
      printf '%s\n' "$(grn PASS)"
      CASES_PASS=$((CASES_PASS+1))
    fi
  else
    printf '%s\n' "$(red FAIL)"
    CASES_FAIL=$((CASES_FAIL+1))
  fi
}

# ============================================================================
# CASES
# ============================================================================

case_01_pod_committed_install() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  assert_file_exists 01 "$ws/.assert-iq/.install-manifest.json"
  assert_dir_exists  01 "$ws/.github/skills"
  assert_dir_exists  01 "$ws/.github/agents"
  assert_dir_exists  01 "$ws/.claude/agents"
  assert_file_exists 01 "$ws/CLAUDE.md"
  assert_file_exists 01 "$ws/AGENTS.md"
  assert_file_exists 01 "$ws/.github/copilot-instructions.md"
  assert_dir_exists  01 "$ws/.github/instructions"
  assert_file_exists 01 "$ws/.claude/skills"
  assert_file_exists 01 "$ws/.claude/settings.json"
  cleanup_fixture "$pair"
}

case_02_pod_committed_uninstall() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  run_boot "$pair" --uninstall --yes >/dev/null
  assert_file_missing 02 "$ws/.assert-iq/.install-manifest.json"
  assert_dir_missing  02 "$ws/.github/skills"
  assert_dir_missing  02 "$ws/.github/agents"
  assert_dir_missing  02 "$ws/.claude"
  assert_file_missing 02 "$ws/CLAUDE.md"
  assert_file_missing 02 "$ws/AGENTS.md"
  cleanup_fixture "$pair"
}

case_03_pod_trial_install() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=trial --yes >/dev/null
  assert_file_exists 03 "$ws/.assert-iq/.install-manifest.json"
  assert_file_exists 03 "$ws/.git/info/exclude"
  assert_contains    03 "$ws/.git/info/exclude" "assert-iq trial mode"
  assert_contains    03 "$ws/.git/info/exclude" ".github/skills"
  cleanup_fixture "$pair"
}

case_04_trial_graduate() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=trial --yes >/dev/null
  run_boot "$pair" --graduate >/dev/null
  assert_file_exists 04 "$ws/.assert-iq/.install-manifest.json"
  assert_dir_exists  04 "$ws/.github/skills"
  # After graduate: managed block stays (holds always-on backup-glob
  # exclusions) but per-path trial entries are gone.
  if [[ -f "$ws/.git/info/exclude" ]]; then
    assert_not_contains 04 "$ws/.git/info/exclude" ".github/skills"
    assert_contains     04 "$ws/.git/info/exclude" "*.assert-iq.pre-install"
  fi
  # Manifest mode field flipped
  if command -v jq >/dev/null 2>&1; then
    local m; m="$(jq -r .mode "$ws/.assert-iq/.install-manifest.json")"
    [[ "$m" == "committed" ]] || fail 04 "manifest mode=$m, expected committed"
  fi
  cleanup_fixture "$pair"
}

case_05_trial_uninstall() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=trial --yes >/dev/null
  run_boot "$pair" --uninstall --yes >/dev/null
  assert_file_missing 05 "$ws/.assert-iq/.install-manifest.json"
  assert_dir_missing  05 "$ws/.github/skills"
  if [[ -f "$ws/.git/info/exclude" ]]; then
    assert_not_contains 05 "$ws/.git/info/exclude" "assert-iq trial mode"
  fi
  cleanup_fixture "$pair"
}

case_06_solo_install() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}" home="${pair#*:}"
  run_boot "$pair" --preset=solo --mode=committed --yes >/dev/null
  assert_dir_exists  06 "$ws/.github/skills"          # workspace
  assert_file_exists 06 "$home/.claude/CLAUDE.md"      # user
  assert_file_missing 06 "$ws/CLAUDE.md"               # NOT in workspace under solo
  cleanup_fixture "$pair"
}

case_07_solo_uninstall_with_user() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}" home="${pair#*:}"
  run_boot "$pair" --preset=solo --mode=committed --yes >/dev/null
  run_boot "$pair" --uninstall --user --yes >/dev/null
  assert_file_missing 07 "$home/.claude/CLAUDE.md"
  assert_dir_missing  07 "$ws/.github/skills"
  cleanup_fixture "$pair"
}

case_08_solo_uninstall_no_user() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}" home="${pair#*:}"
  run_boot "$pair" --preset=solo --mode=committed --yes >/dev/null
  run_boot "$pair" --uninstall --yes >/dev/null
  assert_dir_missing  08 "$ws/.github/skills"
  assert_file_exists  08 "$home/.claude/CLAUDE.md"   # user file preserved
  cleanup_fixture "$pair"
}

case_09_portable_install() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}" home="${pair#*:}"
  run_boot "$pair" --preset=portable --mode=committed --yes >/dev/null
  # Skills user-globally, not in workspace
  assert_dir_exists  09 "$home/.agents/skills"
  assert_dir_exists  09 "$home/.claude/skills"
  assert_dir_missing 09 "$ws/.github/skills"
  # Workspace footprint: chat agents + manifest, nothing else
  assert_dir_exists  09 "$ws/.github/agents"
  assert_dir_exists  09 "$ws/.claude/agents"
  assert_file_exists 09 "$ws/.assert-iq/.install-manifest.json"
  assert_file_missing 09 "$ws/CLAUDE.md"
  assert_file_missing 09 "$ws/AGENTS.md"
  assert_file_missing 09 "$ws/.github/copilot-instructions.md"
  assert_dir_missing 09 "$ws/.github/instructions"
  assert_dir_missing 09 "$ws/.vscode"
  assert_dir_missing 09 "$ws/hooks"
  assert_file_missing 09 "$ws/.claude/settings.json"
  cleanup_fixture "$pair"
}

case_10_portable_uninstall_user() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}" home="${pair#*:}"
  run_boot "$pair" --preset=portable --mode=committed --yes >/dev/null
  run_boot "$pair" --uninstall --user --yes >/dev/null
  assert_dir_missing  10 "$home/.agents/skills"
  assert_dir_missing  10 "$home/.claude/skills"
  assert_file_missing 10 "$ws/.assert-iq/.install-manifest.json"
  cleanup_fixture "$pair"
}

case_11_skills_scope_both_install() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}" home="${pair#*:}"
  run_boot "$pair" --preset=pod --mode=committed --skills-scope=both --yes >/dev/null
  assert_dir_exists 11 "$ws/.github/skills"
  assert_dir_exists 11 "$home/.agents/skills"
  assert_dir_exists 11 "$home/.claude/skills"
  cleanup_fixture "$pair"
}

case_12_skills_scope_both_uninstall_user() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}" home="${pair#*:}"
  run_boot "$pair" --preset=pod --mode=committed --skills-scope=both --yes >/dev/null
  run_boot "$pair" --uninstall --user --yes >/dev/null
  assert_dir_missing 12 "$ws/.github/skills"
  assert_dir_missing 12 "$home/.agents/skills"
  assert_dir_missing 12 "$home/.claude/skills"
  cleanup_fixture "$pair"
}

case_13_skills_scope_user_install() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}" home="${pair#*:}"
  run_boot "$pair" --preset=pod --mode=committed --skills-scope=user --yes >/dev/null
  assert_dir_exists  13 "$home/.agents/skills"
  assert_dir_exists  13 "$home/.claude/skills"
  assert_dir_missing 13 "$ws/.github/skills"
  assert_file_missing 13 "$ws/.claude/skills"   # symlink should NOT exist
  cleanup_fixture "$pair"
}

case_14_skills_scope_user_uninstall_user() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}" home="${pair#*:}"
  run_boot "$pair" --preset=pod --mode=committed --skills-scope=user --yes >/dev/null
  run_boot "$pair" --uninstall --user --yes >/dev/null
  assert_dir_missing 14 "$home/.agents/skills"
  assert_dir_missing 14 "$home/.claude/skills"
  cleanup_fixture "$pair"
}

case_15_dry_run() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  # Install first so manifest exists, then dry-run uninstall (the only place
  # --dry-run is honored).
  run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  local before_sha
  before_sha="$(find "$ws" -type f | sort | xargs shasum -a 256 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  run_boot "$pair" --uninstall --dry-run --yes >/dev/null
  local after_sha
  after_sha="$(find "$ws" -type f | sort | xargs shasum -a 256 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  [[ "$before_sha" == "$after_sha" ]] || fail 15 "dry-run changed filesystem"
  assert_file_exists 15 "$ws/.assert-iq/.install-manifest.json"
  cleanup_fixture "$pair"
}

case_16_ask_mode_no_tty() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  # Stdin not a TTY by default in scripts; pass --mode=ask explicitly
  run_boot "$pair" --preset=pod --mode=ask --yes < /dev/null >/dev/null
  assert_file_exists 16 "$ws/.assert-iq/.install-manifest.json"
  if command -v jq >/dev/null 2>&1; then
    local m; m="$(jq -r .mode "$ws/.assert-iq/.install-manifest.json")"
    [[ "$m" == "committed" ]] || fail 16 "ask-mode no-TTY fallback: mode=$m, expected committed"
  fi
  cleanup_fixture "$pair"
}

case_17_invalid_preset() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  local out rc
  out="$(run_boot "$pair" --preset=bogus --yes 2>&1)" && rc=0 || rc=$?
  [[ $rc -ne 0 ]] || fail 17 "expected non-zero exit; got 0"
  assert_file_missing 17 "$ws/.assert-iq/.install-manifest.json"
  cleanup_fixture "$pair"
}

case_18_invalid_skills_scope() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  local rc
  run_boot "$pair" --preset=pod --skills-scope=bogus --yes >/dev/null 2>&1 && rc=0 || rc=$?
  [[ $rc -ne 0 ]] || fail 18 "expected non-zero exit; got 0"
  assert_file_missing 18 "$ws/.assert-iq/.install-manifest.json"
  cleanup_fixture "$pair"
}

case_19_idempotent_reinstall() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  # Exclude the install manifest: it embeds a fresh installed_at timestamp
  # on every run by design. Everything else must hash-equal across runs.
  local before; before="$(find "$ws" -type f -not -path '*/.assert-iq/.install-manifest.json' -not -path '*/.git/*' | sort | xargs shasum -a 256 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  local after; after="$(find "$ws" -type f -not -path '*/.assert-iq/.install-manifest.json' -not -path '*/.git/*' | sort | xargs shasum -a 256 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  [[ "$before" == "$after" ]] || fail 19 "filesystem changed on reinstall"
  cleanup_fixture "$pair"
}

case_20_conflict_keep_user_file() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  # Pre-seed a user-owned CLAUDE.md
  echo "user content $(date +%s%N)" > "$ws/CLAUDE.md"
  local user_sha; user_sha="$(shasum -a 256 "$ws/CLAUDE.md" | awk '{print $1}')"
  # Non-interactive (--yes, no TTY) MUST take the safe path: keep user file
  # untouched, no backup needed, no overwrite. Verifies bootstrap never
  # silently clobbers user files on automated runs.
  run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  local after_sha; after_sha="$(shasum -a 256 "$ws/CLAUDE.md" | awk '{print $1}')"
  [[ "$after_sha" == "$user_sha" ]] || fail 20 "user file mutated by --yes (sha $after_sha != $user_sha)"
  assert_file_missing 20 "$ws/CLAUDE.md.assert-iq.pre-install"
  cleanup_fixture "$pair"
}

case_21_uninstall_restores_backup() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  echo "user content $(date +%s%N)" > "$ws/CLAUDE.md"
  local user_sha; user_sha="$(shasum -a 256 "$ws/CLAUDE.md" | awk '{print $1}')"
  # Force overwrite so a backup IS taken, then verify uninstall restores it.
  CONFLICT_BULK_CHOICE=O run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  run_boot "$pair" --uninstall --yes >/dev/null
  assert_file_exists 21 "$ws/CLAUDE.md"
  local restored_sha; restored_sha="$(shasum -a 256 "$ws/CLAUDE.md" | awk '{print $1}')"
  [[ "$restored_sha" == "$user_sha" ]] || fail 21 "restored sha != original ($restored_sha vs $user_sha)"
  cleanup_fixture "$pair"
}

case_22_install_sh_install() {
  local pair; pair="$(mk_pack_copy)"
  local copy="${pair%:*}" home="${pair#*:}"
  HOME="$home" bash "$copy/install.sh" >/dev/null 2>&1
  # Symlink/dir created
  [[ -L "$copy/.claude/skills" || -d "$copy/.claude/skills" ]] || fail 22 ".claude/skills not created"
  assert_file_exists 22 "$copy/.claude/settings.json"
  # Re-run is idempotent
  HOME="$home" bash "$copy/install.sh" >/dev/null 2>&1 || fail 22 "reinstall failed"
  cleanup_fixture "$pair"
}

case_23_install_sh_preserves_user_keys() {
  local pair; pair="$(mk_pack_copy)"
  local copy="${pair%:*}" home="${pair#*:}"
  # Pre-seed settings.json with a user key
  mkdir -p "$copy/.claude"
  cat > "$copy/.claude/settings.json" << 'JSON'
{
  "userKey": "preserve-me",
  "anotherKey": {"nested": true}
}
JSON
  HOME="$home" bash "$copy/install.sh" >/dev/null 2>&1
  assert_contains 23 "$copy/.claude/settings.json" "preserve-me"
  HOME="$home" bash "$copy/install.sh" --uninstall >/dev/null 2>&1
  assert_contains 23 "$copy/.claude/settings.json" "preserve-me"
  # And the symlink should be gone
  [[ ! -L "$copy/.claude/skills" && ! -e "$copy/.claude/skills" ]] || fail 23 ".claude/skills not removed"
  cleanup_fixture "$pair"
}

# ---- Markdown-merge cases (v1.3.0) ----------------------------------------

case_24_merge_fresh() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  mkdir -p "$ws/.github"
  printf '# Team rules\n- 4-space indent\n' > "$ws/.github/copilot-instructions.md"
  CONFLICT_BULK_CHOICE=M run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  assert_file_exists 24 "$ws/.github/copilot-instructions.md"
  assert_contains 24 "$ws/.github/copilot-instructions.md" "<!-- assert-iq:begin"
  assert_contains 24 "$ws/.github/copilot-instructions.md" "<!-- assert-iq:end -->"
  assert_contains 24 "$ws/.github/copilot-instructions.md" "# Team rules"
  assert_contains 24 "$ws/.github/copilot-instructions.md" "4-space indent"
  assert_file_exists 24 "$ws/.github/copilot-instructions.md.assert-iq.pre-install"
  cleanup_fixture "$pair"
}

case_25_merge_idempotent() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  mkdir -p "$ws/.github"
  printf '# Team rules\n- 4-space indent\n' > "$ws/.github/copilot-instructions.md"
  CONFLICT_BULK_CHOICE=M run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  local first_sha; first_sha="$(shasum -a 256 "$ws/.github/copilot-instructions.md" | awk '{print $1}')"
  CONFLICT_BULK_CHOICE=M run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  local second_sha; second_sha="$(shasum -a 256 "$ws/.github/copilot-instructions.md" | awk '{print $1}')"
  [[ "$first_sha" == "$second_sha" ]] || fail 25 "merge not idempotent ($first_sha vs $second_sha)"
  # Marker block should appear exactly once.
  local n_begin; n_begin="$(grep -c "<!-- assert-iq:begin" "$ws/.github/copilot-instructions.md" 2>/dev/null || echo 0)"
  [[ "$n_begin" == "1" ]] || fail 25 "expected 1 begin marker, found $n_begin"
  cleanup_fixture "$pair"
}

case_26_merge_uninstall_round_trip() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  mkdir -p "$ws/.github"
  printf '# Team rules\n- 4-space indent\n' > "$ws/.github/copilot-instructions.md"
  local user_sha; user_sha="$(shasum -a 256 "$ws/.github/copilot-instructions.md" | awk '{print $1}')"
  CONFLICT_BULK_CHOICE=M run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  run_boot "$pair" --uninstall --yes >/dev/null
  assert_file_exists 26 "$ws/.github/copilot-instructions.md"
  local restored_sha; restored_sha="$(shasum -a 256 "$ws/.github/copilot-instructions.md" | awk '{print $1}')"
  [[ "$restored_sha" == "$user_sha" ]] || fail 26 "round-trip sha mismatch ($restored_sha vs $user_sha)"
  cleanup_fixture "$pair"
}

case_27_merge_allowlist_isolation() {
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  # Pre-seed a user .claude/settings.json with a unique key.
  mkdir -p "$ws/.claude"
  cat > "$ws/.claude/settings.json" << 'JSON'
{ "userKeyZ": "keep-me" }
JSON
  CONFLICT_BULK_CHOICE=M run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  assert_file_exists 27 "$ws/.claude/settings.json"
  # JSON deep-merge should preserve the user key — NOT inject markdown markers.
  assert_contains     27 "$ws/.claude/settings.json" "keep-me"
  assert_not_contains 27 "$ws/.claude/settings.json" "<!-- assert-iq:begin"
  cleanup_fixture "$pair"
}

case_28_committed_excludes_backup_globs() {
  # Always-on contract: even in committed mode, .git/info/exclude must
  # carry the backup-glob lines so *.assert-iq.pre-install never leaks
  # into git status.
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  mkdir -p "$ws/.github"
  printf '# Team rules\n' > "$ws/.github/copilot-instructions.md"
  CONFLICT_BULK_CHOICE=M run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  assert_file_exists 28 "$ws/.git/info/exclude"
  assert_contains    28 "$ws/.git/info/exclude" "*.assert-iq.pre-install"
  assert_contains    28 "$ws/.git/info/exclude" "*.assert-iq.uninstall-saved"
  # Confirm the backup file actually exists on disk and is hidden by the
  # exclusion: git check-ignore --no-index should report it ignored.
  assert_file_exists 28 "$ws/.github/copilot-instructions.md.assert-iq.pre-install"
  ( cd "$ws" && git check-ignore --no-index --quiet ".github/copilot-instructions.md.assert-iq.pre-install" ) \
    || fail 28 "backup file not git-ignored despite exclude entry"
  cleanup_fixture "$pair"
}

case_29_trial_skip_worktree_hides_tracked_merge() {
  # Trial mode + tracked merge target → file is marked --skip-worktree
  # so git status no longer reports the merged-in marker block.
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  mkdir -p "$ws/.github"
  printf '# Team rules\n' > "$ws/.github/copilot-instructions.md"
  ( cd "$ws" && git add .github/copilot-instructions.md && git commit -q -m seed )
  CONFLICT_BULK_CHOICE=M run_boot "$pair" --preset=pod --mode=trial --yes >/dev/null
  # File on disk now contains the marker block.
  assert_contains 29 "$ws/.github/copilot-instructions.md" "<!-- assert-iq:begin"
  # ...but git status sees nothing for it.
  local porcelain; porcelain="$( cd "$ws" && git status --porcelain -- .github/copilot-instructions.md )"
  [[ -z "$porcelain" ]] || fail 29 "git status not silent for skip-worktree path: $porcelain"
  # Index flag confirms skip-worktree.
  ( cd "$ws" && git ls-files -v -- .github/copilot-instructions.md | grep -q '^S ' ) \
    || fail 29 "expected --skip-worktree flag (S) on tracked merge target"
  cleanup_fixture "$pair"
}

case_30_uninstall_clears_skip_worktree_and_backups() {
  # Trial install on a tracked file → uninstall must clear --skip-worktree,
  # restore the original byte-for-byte, remove the backup file, and leave
  # `git status` clean.
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  mkdir -p "$ws/.github"
  printf '# Team rules\n' > "$ws/.github/copilot-instructions.md"
  local seed_sha; seed_sha="$(shasum -a 256 "$ws/.github/copilot-instructions.md" | awk '{print $1}')"
  ( cd "$ws" && git add .github/copilot-instructions.md && git commit -q -m seed )
  CONFLICT_BULK_CHOICE=M run_boot "$pair" --preset=pod --mode=trial --yes >/dev/null
  run_boot "$pair" --uninstall --yes >/dev/null
  # Original restored.
  assert_file_exists  30 "$ws/.github/copilot-instructions.md"
  local restored_sha; restored_sha="$(shasum -a 256 "$ws/.github/copilot-instructions.md" | awk '{print $1}')"
  [[ "$restored_sha" == "$seed_sha" ]] || fail 30 "restored sha differs from seed"
  # Backup gone.
  assert_file_missing 30 "$ws/.github/copilot-instructions.md.assert-iq.pre-install"
  # No skip-worktree flag remains.
  if ( cd "$ws" && git ls-files -v 2>/dev/null | grep -q '^S '); then
    fail 30 "leftover --skip-worktree flag after uninstall"
  fi
  # git status clean.
  local porcelain; porcelain="$( cd "$ws" && git status --porcelain )"
  [[ -z "$porcelain" ]] || fail 30 "git status not clean after uninstall: $porcelain"
  cleanup_fixture "$pair"
}

case_31_uninstall_preserves_unrelated_skip_worktree() {
  # Regression: uninstall must NOT clear --skip-worktree flags the user set
  # on unrelated paths before the bootstrap ever ran.
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  # Seed an unrelated tracked file with a user-managed skip-worktree flag.
  printf '{}\n' > "$ws/tasks.json"
  ( cd "$ws" && git add tasks.json && git commit -q -m seed-tasks )
  ( cd "$ws" && git update-index --skip-worktree -- tasks.json )
  # Sanity: pre-existing flag is set.
  ( cd "$ws" && git ls-files -v -- tasks.json | grep -q '^S ' ) \
    || fail 31 "test setup: failed to set pre-existing --skip-worktree on tasks.json"
  run_boot "$pair" --preset=pod --mode=trial --yes >/dev/null
  run_boot "$pair" --uninstall --yes >/dev/null
  # User's unrelated flag must survive the uninstall.
  ( cd "$ws" && git ls-files -v -- tasks.json | grep -q '^S ' ) \
    || fail 31 "uninstall cleared user's pre-existing --skip-worktree on tasks.json"
  # And tasks.json itself must be untouched (still {}).
  local sha; sha="$(shasum -a 256 "$ws/tasks.json" | awk '{print $1}')"
  local expect; expect="$(printf '{}\n' | shasum -a 256 | awk '{print $1}')"
  [[ "$sha" == "$expect" ]] || fail 31 "tasks.json content changed during install/uninstall"
  cleanup_fixture "$pair"
}

case_32_install_respects_existing_skip_worktree() {
  # Regression: install must NOT re-mark a path that was already
  # --skip-worktree before the bootstrap ran. Uninstall then must not
  # clear that pre-existing flag either.
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  mkdir -p "$ws/.github"
  printf '# Team rules\n' > "$ws/.github/copilot-instructions.md"
  ( cd "$ws" && git add .github/copilot-instructions.md && git commit -q -m seed )
  ( cd "$ws" && git update-index --skip-worktree -- .github/copilot-instructions.md )
  CONFLICT_BULK_CHOICE=M run_boot "$pair" --preset=pod --mode=trial --yes >/dev/null
  # Sidecar must NOT contain a path the user already had flagged.
  if [[ -f "$ws/.assert-iq/.skip-worktree-paths" ]]; then
    grep -Fxq ".github/copilot-instructions.md" "$ws/.assert-iq/.skip-worktree-paths" \
      && fail 32 "install claimed pre-existing user flag in sidecar"
  fi
  run_boot "$pair" --uninstall --yes >/dev/null
  # Pre-existing flag must still be set.
  ( cd "$ws" && git ls-files -v -- .github/copilot-instructions.md | grep -q '^S ' ) \
    || fail 32 "uninstall cleared pre-existing user --skip-worktree on tracked merge target"
  cleanup_fixture "$pair"
}

case_33_json_merge_clean_roundtrip_no_uninstall_saved() {
  # Regression: when a JSON additive merge target is unedited between
  # install and uninstall, no .uninstall-saved artifact is left behind.
  local pair; pair="$(mkfixture)"
  local ws="${pair%:*}"
  mkdir -p "$ws/.claude"
  printf '{ "userKey": "preserve-me" }\n' > "$ws/.claude/settings.json"
  CONFLICT_BULK_CHOICE=M run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  # Confirm a merge happened (file got pack keys added).
  grep -q '"hooks"' "$ws/.claude/settings.json" \
    || fail 33 "test setup: expected pack to merge keys into .claude/settings.json"
  # Confirm result-sha sidecar recorded the merge target.
  [[ -f "$ws/.assert-iq/.merge-result-shas" ]] \
    || fail 33 "merge-result-shas sidecar was not written"
  grep -Fq ".claude/settings.json" "$ws/.assert-iq/.merge-result-shas" \
    || fail 33 "merge-result-shas sidecar missing entry for .claude/settings.json"
  run_boot "$pair" --uninstall --yes >/dev/null
  # Original restored and NO .uninstall-saved litter left behind.
  assert_file_exists  33 "$ws/.claude/settings.json"
  assert_file_missing 33 "$ws/.claude/settings.json.assert-iq.uninstall-saved"
  grep -q '"userKey"' "$ws/.claude/settings.json" \
    || fail 33 "user key missing after uninstall restore"
  cleanup_fixture "$pair"
}

case_34_install_state_sidecars_hidden_from_git() {
  # Always-on contract: the .assert-iq install-state sidecars
  # (.skip-worktree-paths, .merge-result-shas) are pure local install
  # bookkeeping and must never appear in git status, in any mode.
  local pair ws ignored porcelain
  # --- trial mode ---
  pair="$(mkfixture)"
  ws="${pair%:*}"
  mkdir -p "$ws/.github"
  printf '# Team rules\n' > "$ws/.github/copilot-instructions.md"
  ( cd "$ws" && git add .github/copilot-instructions.md && git commit -q -m seed )
  CONFLICT_BULK_CHOICE=M run_boot "$pair" --preset=pod --mode=trial --yes >/dev/null
  # The merge-result-shas sidecar should exist after install.
  assert_file_exists 34 "$ws/.assert-iq/.merge-result-shas"
  # Both sidecars must be ignored by git.
  ( cd "$ws" && git check-ignore --no-index --quiet ".assert-iq/.merge-result-shas" ) \
    || fail 34 "trial: .assert-iq/.merge-result-shas not git-ignored"
  if [[ -f "$ws/.assert-iq/.skip-worktree-paths" ]]; then
    ( cd "$ws" && git check-ignore --no-index --quiet ".assert-iq/.skip-worktree-paths" ) \
      || fail 34 "trial: .assert-iq/.skip-worktree-paths not git-ignored"
  fi
  porcelain="$( cd "$ws" && git status --porcelain )"
  echo "$porcelain" | grep -q '\.assert-iq/\.skip-worktree-paths' \
    && fail 34 "trial: .skip-worktree-paths leaked into git status"
  echo "$porcelain" | grep -q '\.assert-iq/\.merge-result-shas' \
    && fail 34 "trial: .merge-result-shas leaked into git status"
  cleanup_fixture "$pair"
  # --- committed mode ---
  pair="$(mkfixture)"
  ws="${pair%:*}"
  mkdir -p "$ws/.claude"
  printf '{ "userKey": "preserve-me" }\n' > "$ws/.claude/settings.json"
  CONFLICT_BULK_CHOICE=M run_boot "$pair" --preset=pod --mode=committed --yes >/dev/null
  assert_file_exists 34 "$ws/.assert-iq/.merge-result-shas"
  ( cd "$ws" && git check-ignore --no-index --quiet ".assert-iq/.merge-result-shas" ) \
    || fail 34 "committed: .assert-iq/.merge-result-shas not git-ignored"
  porcelain="$( cd "$ws" && git status --porcelain )"
  echo "$porcelain" | grep -q '\.assert-iq/\.skip-worktree-paths' \
    && fail 34 "committed: .skip-worktree-paths leaked into git status"
  echo "$porcelain" | grep -q '\.assert-iq/\.merge-result-shas' \
    && fail 34 "committed: .merge-result-shas leaked into git status"
  cleanup_fixture "$pair"
}

# ============================================================================
# RUN
# ============================================================================

echo ""
echo "Assert.IQ bootstrap E2E test driver"
echo "Pack:    $PACK"
echo "Pattern: ${PATTERN:-(none)}"
echo ""
echo "Cases:"

run_case "01 pod committed install"                  case_01_pod_committed_install
run_case "02 pod committed uninstall"                case_02_pod_committed_uninstall
run_case "03 pod trial install"                      case_03_pod_trial_install
run_case "04 trial -> graduate"                      case_04_trial_graduate
run_case "05 trial uninstall (no graduate)"          case_05_trial_uninstall
run_case "06 solo install"                           case_06_solo_install
run_case "07 solo uninstall --user"                  case_07_solo_uninstall_with_user
run_case "08 solo uninstall (no --user)"             case_08_solo_uninstall_no_user
run_case "09 portable install"                       case_09_portable_install
run_case "10 portable uninstall --user"              case_10_portable_uninstall_user
run_case "11 skills-scope=both install"              case_11_skills_scope_both_install
run_case "12 skills-scope=both uninstall --user"     case_12_skills_scope_both_uninstall_user
run_case "13 skills-scope=user install"              case_13_skills_scope_user_install
run_case "14 skills-scope=user uninstall --user"     case_14_skills_scope_user_uninstall_user
run_case "15 dry-run uninstall"                      case_15_dry_run
run_case "16 ask-mode no-TTY -> committed"           case_16_ask_mode_no_tty
run_case "17 invalid preset rejected"                case_17_invalid_preset
run_case "18 invalid skills-scope rejected"          case_18_invalid_skills_scope
run_case "19 idempotent reinstall"                   case_19_idempotent_reinstall
run_case "20 conflict creates pre-install backup"    case_20_conflict_keep_user_file
run_case "21 uninstall restores backup"              case_21_uninstall_restores_backup
run_case "22 install.sh install + reinstall"         case_22_install_sh_install
run_case "23 install.sh preserves user keys"         case_23_install_sh_preserves_user_keys
run_case "24 markdown merge fresh"                   case_24_merge_fresh
run_case "25 markdown merge idempotent"              case_25_merge_idempotent
run_case "26 markdown merge uninstall round-trip"    case_26_merge_uninstall_round_trip
run_case "27 merge allowlist isolation (JSON)"       case_27_merge_allowlist_isolation
run_case "28 committed excludes backup-globs"        case_28_committed_excludes_backup_globs
run_case "29 trial skip-worktree on tracked merge"   case_29_trial_skip_worktree_hides_tracked_merge
run_case "30 uninstall clears skip-worktree+backups" case_30_uninstall_clears_skip_worktree_and_backups
run_case "31 preserves unrelated skip-worktree"      case_31_uninstall_preserves_unrelated_skip_worktree
run_case "32 install respects existing skip-worktree" case_32_install_respects_existing_skip_worktree
run_case "33 json merge clean roundtrip no .uninstall-saved" case_33_json_merge_clean_roundtrip_no_uninstall_saved
run_case "34 install state sidecars hidden from git" case_34_install_state_sidecars_hidden_from_git

echo ""
echo "Summary: $(grn $CASES_PASS pass)  $(red $CASES_FAIL fail)  $(ylw $CASES_SKIP skip)"
if (( ${#FAIL_LOG[@]} > 0 )); then
  echo ""
  echo "Failures:"
  for line in "${FAIL_LOG[@]}"; do echo "$line"; done
fi
exit $CASES_FAIL
