#!/usr/bin/env bash
# ============================================================================
# UNIT: install.sh must merge .claude/settings.json idempotently, with or
# without jq.
# ============================================================================
# WHY THIS EXISTS
#
# The settings merge used to be jq-only, with this fallback:
#
#     if [[ -f "$SETTINGS_DST" ]]; then
#       fail "jq not installed and .claude/settings.json already exists"
#
# So on any machine without jq the installer worked exactly ONCE: the first run
# copied the file, and every re-run aborted. That is stock macOS -- it ships
# Python 3 but not jq -- while the README advertises the installer as
# "Re-runnable". The merge now prefers Python (resolved by execution:
# python3 -> python -> py -3) and falls back to jq.
#
# Contract pinned here:
#   1. fresh install writes a Claude-shaped (matcher-group) settings.json
#   2. re-running merges: the hooks key is replaced, other keys survive
#   3. re-running with jq unavailable still merges
#   4. with NO usable JSON tool, it fails loudly and leaves the file BYTE-FOR-
#      BYTE untouched -- never a partial write
#
# PORTABILITY: bash 3.2 (macOS /bin/bash). No mapfile, no ${var,,}, no
# associative arrays, and no `((VAR++))` -- under `set -e` that returns the
# PRE-increment value as its exit status, so the first 0->1 aborts the script.
# ============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
. "$SCRIPT_DIR/lib/aiq-test-lib.sh"

PASS=0
FAIL=0

# install.sh refuses to run under Git Bash/MSYS because its OUTPUT is wrong for
# Windows (bash-shell Claude config + MSYS pack root). This suite tests the POSIX
# merge logic on purpose, so opt in explicitly.
export AIQ_ALLOW_MSYS=1

ok()  { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

echo "=== UNIT: install.sh settings.json merge ==="
echo ""

if ! aiq_resolve_python; then
    echo "SKIP no working Python 3; cannot verify the merge contract"
    exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aiq-merge.XXXXXX")"
PACK="$WORK/pack"
SHIM="$WORK/shim"
mkdir -p "$PACK" "$SHIM"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Disposable copy of the pack: install.sh operates on its own directory.
if ! ( cd "$REPO_ROOT" && tar -cf - --exclude='.git' --exclude='node_modules' . ) \
     | ( cd "$PACK" && tar -xf - ); then
    bad "could not copy the pack into $PACK"
    echo ""
    echo "=== Results: $PASS PASS, $FAIL FAIL ==="
    exit 1
fi

SETTINGS="$PACK/.claude/settings.json"
rm -f "$SETTINGS"
rm -rf "$PACK/.claude/skills"

# A stub that always fails, used to hide a tool from PATH by shadowing it.
# Removing a directory from PATH is not portable enough: on macOS python3 lives
# in /usr/bin next to the coreutils the installer itself needs.
make_shim() {
    printf '#!/bin/sh\nexit 127\n' > "$SHIM/$1"
    chmod +x "$SHIM/$1"
}

sha_of() { aiq_py -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

# ---- 1. fresh install ------------------------------------------------------
if bash "$PACK/install.sh" >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
    shape="$(aiq_py -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
g = (d.get("hooks") or {}).get("SessionStart") or []
print("GROUP" if g and "hooks" in g[0] else "FLAT")
' "$SETTINGS")"
    if [ "$shape" = "GROUP" ]; then
        ok "fresh install writes a matcher-group settings.json"
    else
        bad "fresh install wrote the $shape shape (Claude Code ignores FLAT)"
    fi
else
    bad "fresh install did not produce $SETTINGS"
fi

# ---- 2. re-run merges and preserves other keys ---------------------------
aiq_py -c '
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["permissions"] = {"allow": ["Bash(ls)"]}
json.dump(d, open(p, "w", encoding="utf-8"), indent=2)
' "$SETTINGS"

if bash "$PACK/install.sh" >/dev/null 2>&1; then
    kept="$(aiq_py -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
g = (d.get("hooks") or {}).get("SessionStart") or []
print("YES" if "permissions" in d and g and "hooks" in g[0] else "NO")
' "$SETTINGS")"
    if [ "$kept" = "YES" ]; then
        ok "re-run merges the hooks key and preserves other keys"
    else
        bad "re-run lost the user's other keys or the matcher-group shape"
    fi
else
    bad "re-run failed (installer is not idempotent)"
fi

# ---- 3. re-run with jq hidden -------------------------------------------
make_shim jq
if PATH="$SHIM:$PATH" bash "$PACK/install.sh" >/dev/null 2>&1; then
    kept="$(aiq_py -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print("YES" if "permissions" in d and d.get("hooks") else "NO")
' "$SETTINGS")"
    if [ "$kept" = "YES" ]; then
        ok "re-run merges with jq unavailable (Python path)"
    else
        bad "merge without jq damaged the file"
    fi
else
    bad "re-run failed with jq unavailable -- the jq-only regression is back"
fi

# ---- 4. no usable JSON tool: loud failure, file untouched ---------------
make_shim python3
make_shim python
make_shim py
before="$(sha_of "$SETTINGS")"
set +e
PATH="$SHIM:$PATH" bash "$PACK/install.sh" >/dev/null 2>"$WORK/err.txt"
rc=$?
set -e
after="$(sha_of "$SETTINGS")"
if [ "$rc" -ne 0 ] && [ "$before" = "$after" ]; then
    ok "no JSON tool: exits non-zero and leaves settings.json byte-identical"
elif [ "$rc" -eq 0 ]; then
    bad "no JSON tool: install reported success without merging"
else
    bad "no JSON tool: settings.json was modified despite the failure"
fi
if grep -qi 'json tool\|merge' "$WORK/err.txt" 2>/dev/null; then
    ok "failure message names the missing tool / failed merge"
else
    bad "failure was silent (no actionable message on stderr)"
fi

echo ""
echo "=== Results: $PASS PASS, $FAIL FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
