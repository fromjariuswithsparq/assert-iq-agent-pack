#!/usr/bin/env bash
# Assert.IQ environment check (macOS / Linux / WSL).
#
# Run this BEFORE installing. It reports every requirement the pack needs, what
# it found, and the exact fix when something is missing -- so a bad environment
# surfaces here instead of as a confusing failure mid-install.
#
#   bash scripts/check-environment.sh
#
# Windows users: run scripts\check-environment.ps1 instead. This script still
# works under Git Bash and will tell you what to use, but the pack's Windows
# path is PowerShell end to end.
#
# Exit codes: 0 = ready to install, 1 = at least one hard requirement missing.
# Warnings never fail the run: they mark reduced functionality, not a blocker.
#
# PORTABILITY: bash 3.2 (macOS /bin/bash) -- no mapfile, no `local -n`,
# no ${var,,}, no associative arrays.
set -u

PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

HARD_FAIL=0
WARN=0

if [ -t 1 ]; then
  C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_D=$'\033[90m'; C_0=$'\033[0m'
else
  C_G=""; C_Y=""; C_R=""; C_D=""; C_0=""
fi

pass() { printf '  %s[PASS]%s %-26s %s\n' "$C_G" "$C_0" "$1" "$2"; }
warn() {
  WARN=$((WARN+1))
  printf '  %s[WARN]%s %-26s %s\n' "$C_Y" "$C_0" "$1" "$2"
  [ -n "${3:-}" ] && printf '         %sfix: %s%s\n' "$C_D" "$3" "$C_0"
  return 0
}
fail() {
  HARD_FAIL=$((HARD_FAIL+1))
  printf '  %s[FAIL]%s %-26s %s\n' "$C_R" "$C_0" "$1" "$2"
  [ -n "${3:-}" ] && printf '         %sfix: %s%s\n' "$C_D" "$3" "$C_0"
  return 0
}

printf '\nAssert.IQ environment check\npack: %s\n\n' "$PACK"

# ---- 1. Platform + shell -------------------------------------------------
UNAME="$(uname -s 2>/dev/null || echo unknown)"
case "$UNAME" in
  Darwin)            PLATFORM="macOS" ;;
  Linux)             PLATFORM="Linux" ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM="Windows (Git Bash/MSYS)" ;;
  *)                 PLATFORM="$UNAME" ;;
esac

# bash 3.2 is the floor: it is what macOS still ships as /bin/bash.
BASH_MAJOR="${BASH_VERSINFO[0]:-0}"
BASH_MINOR="${BASH_VERSINFO[1]:-0}"
if [ "$BASH_MAJOR" -gt 3 ] || { [ "$BASH_MAJOR" -eq 3 ] && [ "$BASH_MINOR" -ge 2 ]; }; then
  pass "bash" "${BASH_VERSION%%(*} on $PLATFORM (3.2+ required)"
else
  fail "bash" "${BASH_VERSION:-unknown} is older than 3.2" "install a newer bash"
fi

# ---- 2. Windows-under-bash: point at the PowerShell path ----------------
case "$UNAME" in
  MINGW*|MSYS*|CYGWIN*)
    warn "installer choice" \
         "you are on Windows; the bash installers are the wrong path here" \
         "run 'pwsh -File scripts/check-environment.ps1' then 'pwsh -File scripts/bootstrap.ps1' (Windows PowerShell 5.1 also works: swap pwsh for powershell). MSYS process creation makes install.sh / bootstrap.sh take 9+ minutes per install (they copy and hash ~1000 files one process at a time); the .ps1 versions do the same work in about a minute."
    ;;
esac

# ---- 3. git -------------------------------------------------------------
if command -v git >/dev/null 2>&1; then
  pass "git" "$(git --version | sed 's/git version //')"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    pass "git work tree" "current directory is inside a repo"
  else
    warn "git work tree" "not inside a git repo" \
         "cd into the repo you want the pack installed in before running bootstrap (--mode=trial needs .git/info/exclude)"
  fi
else
  case "$UNAME" in
    Darwin) fail "git" "not found on PATH" "xcode-select --install" ;;
    *)      fail "git" "not found on PATH" "apt install git / dnf install git" ;;
  esac
fi

# ---- 4. Python 3 --------------------------------------------------------
# Probe by EXECUTING. `python3` is reliable on macOS/Linux but not on Windows,
# and this script is also runnable under Git Bash, so use the same contract as
# the rest of the pack: python3 -> python -> py -3.
PY_CMD=""
PY_VER=""
for cand in python3 python; do
  command -v "$cand" >/dev/null 2>&1 || continue
  v="$("$cand" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)" || continue
  case "$v" in
    3.*) PY_CMD="$cand"; PY_VER="$v"; break ;;
  esac
done
if [ -z "$PY_CMD" ] && command -v py >/dev/null 2>&1; then
  v="$(py -3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)" || v=""
  [ -n "$v" ] && { PY_CMD="py -3"; PY_VER="$v"; }
fi
if [ -n "$PY_CMD" ]; then
  pass "Python 3" "$PY_VER via '$PY_CMD'"
else
  case "$UNAME" in
    Darwin) pyfix="xcode-select --install (or brew install python@3.12)" ;;
    MINGW*|MSYS*|CYGWIN*) pyfix="winget install Python.Python.3.12 -- note a 'python3' that prints a Microsoft Store hint is a stub, not an interpreter" ;;
    *) pyfix="apt install python3 / dnf install python3" ;;
  esac
  warn "Python 3" "no working interpreter (tried python3, python, py -3)" \
       "$pyfix -- needed for calibration, memory sanity checks and verdict recording; install and Dreaming hooks work without it"
fi

# ---- 5. jq -------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  pass "jq" "$(jq --version)"
else
  case "$UNAME" in
    Darwin) jqfix="brew install jq" ;;
    *)      jqfix="apt install jq / dnf install jq" ;;
  esac
  warn "jq" "not found" \
       "$jqfix -- optional for a fresh install (bootstrap.sh degrades), but 'bootstrap.sh --upgrade' REQUIRES it"
fi

# ---- 6. Line endings this checkout will hand bash ----------------------
# A checkout made on Windows with core.autocrlf=true carries CRLF shell
# scripts. Git Bash tolerates them; bash on macOS/Linux/WSL does not.
if command -v git >/dev/null 2>&1 && git -C "$PACK" rev-parse --git-dir >/dev/null 2>&1; then
  crlf_count="$(git -C "$PACK" ls-files --eol -- '*.sh' 2>/dev/null | grep -c 'w/crlf' || true)"
  crlf_count="${crlf_count:-0}"
  if [ "$crlf_count" -gt 0 ] 2>/dev/null; then
    case "$UNAME" in
      MINGW*|MSYS*|CYGWIN*)
        warn "shell line endings" "$crlf_count .sh file(s) are CRLF in this checkout" \
             "harmless under Git Bash, fatal if the same checkout is used from WSL/macOS. Fix: git add --renormalize . && git checkout -- ." ;;
      *)
        fail "shell line endings" "$crlf_count .sh file(s) are CRLF; bash will refuse them" \
             "git add --renormalize . && git checkout -- ." ;;
    esac
  else
    pass "shell line endings" "shell scripts are LF"
  fi
fi

# ---- 7. Symlink capability --------------------------------------------
probe="$(mktemp -d "${TMPDIR:-/tmp}/aiq-lnk.XXXXXX")"
if ln -s "$probe" "$probe/link" 2>/dev/null; then
  pass "symlinks" ".claude/skills and .kiro/skills will be live symlinks to ../.github/skills"
else
  # Two symlinks now, not one. A stale COPY is worse than it sounds: the skill
  # tree keeps working, it just silently serves the version from install time.
  # That was hit for real -- three skills were edited, the copy was not
  # refreshed, and Kiro kept rejecting the pre-edit files with no clue why.
  warn "symlinks" "cannot create symlinks on this filesystem" \
       "the installer COPIES .github/skills to .claude/skills and .kiro/skills instead; re-run the installer after editing any skill or those copies go stale"
fi
rm -rf "$probe"

# ---- 7b. Kiro (third harness) ------------------------------------------
# Advisory only. Kiro is optional, so its absence is not a warning -- but when
# it IS present the tester needs to know about workspace trust, because Kiro
# disables hook execution in an untrusted folder SILENTLY. Dreaming then looks
# broken with nothing in any log the user would think to read.
if command -v kiro >/dev/null 2>&1 || [ -d "$HOME/.kiro" ]; then
  pass "kiro" "Kiro detected — .kiro/steering, agents, skills and hooks will install"
  printf '         note: after installing, TRUST the workspace in Kiro. It disables hook\n'
  printf '               execution in untrusted folders SILENTLY, so Dreaming looks dead.\n'
fi

# ---- 8. Installed-pack sanity (only if already installed) -------------
SETTINGS="$PACK/.claude/settings.json"
MANIFEST="$PACK/.assert-iq/.install-manifest.json"
if [ -f "$SETTINGS" ]; then
  if [ -n "$PY_CMD" ]; then
    shape="$($PY_CMD - "$SETTINGS" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("INVALID_JSON"); raise SystemExit
groups = (d.get("hooks") or {}).get("SessionStart")
if not groups:
    print("NO_SESSIONSTART")
elif "hooks" not in groups[0]:
    print("FLAT_HANDLER")
else:
    print("OK:" + str(groups[0]["hooks"][0].get("shell")))
PY
)"
    case "$shape" in
      OK:*)            pass "Claude hooks" "matcher-group shape, shell=${shape#OK:}" ;;
      FLAT_HANDLER)    fail "Claude hooks" "handlers sit directly in the event array (Copilot shape)" \
                            "Claude Code silently ignores a flat handler. Re-run install.sh / bootstrap.sh to render the matcher-group shape." ;;
      NO_SESSIONSTART) warn "Claude hooks" "settings.json has no SessionStart hook" "re-run the installer to wire Dreaming" ;;
      INVALID_JSON)    fail "Claude hooks" ".claude/settings.json is not valid JSON" "fix or delete the file, then re-run the installer" ;;
      *)               warn "Claude hooks" "could not inspect .claude/settings.json" "" ;;
    esac
  else
    warn "Claude hooks" "cannot inspect settings.json without Python" "install Python 3 (see above)"
  fi
elif [ -f "$MANIFEST" ]; then
  warn "Claude hooks" "pack installed but .claude/settings.json is absent" "re-run the installer"
else
  pass "install state" "pack not installed here yet (expected before first install)"
fi

printf '\n'
if [ "$HARD_FAIL" -gt 0 ]; then
  printf '%sNot ready: %d blocking issue(s), %d warning(s).%s\n' "$C_R" "$HARD_FAIL" "$WARN" "$C_0"
  exit 1
fi
if [ "$WARN" -gt 0 ]; then
  printf '%sReady to install, with %d warning(s) above (reduced functionality only).%s\n' "$C_Y" "$WARN" "$C_0"
else
  printf '%sReady to install.%s\n' "$C_G" "$C_0"
fi
exit 0
