#!/bin/bash
# UNIT: a re-run must never destroy tailored client config or user edits.
#
# qi-trace: work-item="TODO(qi-trace): unresolved" acceptance-criteria="TODO"
#   layer=protection-strength generated-by=assert-iq review-required=true
#   risk-tier=high
#
# WHY THIS EXISTS
#
# A workspace tailored with /assert-iq-tailor was upgraded several times in a
# row. The first upgrade merged the tailoring in correctly; the second read
# "unchanged since the last run" as "unedited pack content" and copied the
# template over config.yaml, governance.md, maturity-profile.md and
# business-metrics/baseline.json -- no prompt, no backup. The loss surfaced
# only when the team graduated the pack and committed the template defaults.
# Found on a real project. The same audit found that an explicit overwrite left
# nothing to restore either: the pre-install backup is written once, before the
# pack arrived, and the --upgrade overwrite paths never wrote one at all.
#
# Contract pinned here, for bootstrap.sh and (when pwsh is on PATH)
# bootstrap.ps1:
#   1. a bulk overwrite (CONFLICT_BULK_CHOICE=O) keeps tailored client config
#      -- it three-way merges against the base cache, so the tailoring survives
#   2. with no base cache, a bulk overwrite still keeps client config
#   3. any file the re-run DOES overwrite leaves a timestamped
#      *.assert-iq.pre-overwrite-* copy holding the user's version
#   4. those snapshots are kept out of git by the managed exclude block
#   5. two upgrades in a row keep tailoring: a file the first upgrade merged is
#      never "unedited" to the second (the silent wipe actually seen in the
#      field), with and without the base cache

_AIQ_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_AIQ_LIB_DIR/../../../.." && pwd)"
PASSED=0
FAILED=0
# bootstrap.sh refuses Git Bash/MSYS by default; this test still covers it.
export AIQ_ALLOW_MSYS=1

ws=""
cleanup() { [ -n "$ws" ] && rm -rf "$ws"; }
trap cleanup EXIT

check() { # desc, condition-result
  if [ "$2" -eq 0 ]; then
    echo "✅ $1"; PASSED=$((PASSED+1))
  else
    echo "❌ $1"; FAILED=$((FAILED+1))
  fi
}

native() { # Windows-native path for pwsh under Git Bash; unchanged elsewhere
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

make_ws() {
  [ -n "$ws" ] && rm -rf "$ws"
  ws="$(mktemp -d)"
  ( cd "$ws" && git init -q . && echo x > f && git add -A \
      && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
}

# run_install <installer> [extra args...] -- non-interactive (stdin is /dev/null)
run_install() {
  local which="$1"; shift
  if [ "$which" = sh ]; then
    ( cd "$ws" && bash "$REPO_ROOT/scripts/bootstrap.sh" --mode=trial "$@" ) </dev/null >"$ws.out" 2>&1
  else
    pwsh -NoProfile -File "$(native "$REPO_ROOT/scripts/bootstrap.ps1")" \
      -Mode trial -Workspace "$(native "$ws")" "$@" </dev/null >"$ws.out" 2>&1
  fi
}

run_upgrade() { # <installer> -- non-interactive upgrade of the current $ws
  if [ "$1" = sh ]; then
    ( cd "$ws" && bash "$REPO_ROOT/scripts/bootstrap.sh" --upgrade ) </dev/null >"$ws.out" 2>&1
  else
    pwsh -NoProfile -File "$(native "$REPO_ROOT/scripts/bootstrap.ps1")" \
      -Upgrade -Workspace "$(native "$ws")" </dev/null >"$ws.out" 2>&1
  fi
}

snapshots_of() { # count of pre-overwrite snapshots next to $1
  ls "$1".assert-iq.pre-overwrite-* 2>/dev/null | wc -l | tr -d ' '
}

TAILOR='# tailored-by-test: keep me'
EDIT='<!-- user edit: keep me -->'

exercise() {
  local which="$1"
  echo ""
  echo "--- bootstrap.$which ---"

  make_ws
  run_install "$which"
  local cfg="$ws/.assert-iq/config.yaml"
  local gov="$ws/.assert-iq/governance.md"
  local skill="$ws/.github/skills/dream/SKILL.md"
  [ -f "$cfg" ] && [ -f "$skill" ]; check "[$which] fresh install laid down config.yaml and a skill" $?

  printf '\n%s\n' "$TAILOR" >> "$cfg"
  printf '\n%s\n' "$TAILOR" >> "$gov"
  printf '\n%s\n' "$EDIT" >> "$skill"

  CONFLICT_BULK_CHOICE=O run_install "$which"
  grep -qF "$TAILOR" "$cfg"; check "[$which] bulk overwrite kept tailored config.yaml (base-cache merge)" $?
  grep -qF "$TAILOR" "$gov"; check "[$which] bulk overwrite kept tailored governance.md" $?

  grep -qF "$EDIT" "$skill"; check "[$which] non-config file WAS overwritten by the bulk choice" $((1 - $?))
  [ "$(snapshots_of "$skill")" -ge 1 ]; check "[$which] overwritten file left a pre-overwrite snapshot" $?
  grep -qF "$EDIT" "$skill".assert-iq.pre-overwrite-* 2>/dev/null; check "[$which] snapshot holds the user's version" $?

  grep -qxF '*.assert-iq.pre-overwrite-*' "$ws/.git/info/exclude"; check "[$which] exclude block hides snapshots" $?
  ( cd "$ws" && git status --porcelain --untracked-files=all | grep -q 'pre-overwrite' )
  check "[$which] snapshots do not show in git status" $((1 - $?))

  # No merge baseline: bulk overwrite must still keep client config.
  rm -rf "$ws/.assert-iq/.base"
  CONFLICT_BULK_CHOICE=O run_install "$which"
  grep -qF "$TAILOR" "$cfg"; check "[$which] with no base cache, bulk overwrite still kept config.yaml" $?
  grep -q 'never bulk-overwritten' "$ws.out"; check "[$which] installer said why it kept client config" $?

  # Back-to-back upgrades. The first merges the tailoring in and records the
  # merged file's sha; the second used to read that match as "unedited" and
  # copy the pack template over it. Run once with the base cache and once
  # without, since each takes a different branch of the "unedited" check.
  local variant
  for variant in base no-base; do
    make_ws
    run_install "$which"
    cfg="$ws/.assert-iq/config.yaml"
    printf '\n%s\n' "$TAILOR" >> "$cfg"
    [ "$variant" = no-base ] && rm -rf "$ws/.assert-iq/.base"
    run_upgrade "$which"
    grep -qF "$TAILOR" "$cfg"; check "[$which/$variant] tailoring survives the 1st upgrade" $?
    run_upgrade "$which"
    grep -qF "$TAILOR" "$cfg"; check "[$which/$variant] tailoring survives the 2nd upgrade" $?
    grep 'config.yaml' "$ws.out" | grep -q 'unedited'
    check "[$which/$variant] 2nd upgrade did not treat merged config.yaml as unedited" $((1 - $?))
  done

  rm -f "$ws.out"
}

echo "=== UNIT: re-run never destroys client config or user edits ==="

# AIQ_TEST_INSTALLERS narrows the run, e.g. "ps1" on Windows: bootstrap.sh
# under Git Bash takes ~9 minutes per install, so its half belongs on macOS/Linux.
for which in ${AIQ_TEST_INSTALLERS:-sh ps1}; do
  if [ "$which" = ps1 ] && ! command -v pwsh >/dev/null 2>&1; then
    echo "⏭️  pwsh not on PATH -- bootstrap.ps1 half skipped"
    continue
  fi
  exercise "$which"
done

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"
[ $FAILED -eq 0 ]
