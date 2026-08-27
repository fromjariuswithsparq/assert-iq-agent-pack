#!/bin/bash
# ============================================================================
# Shared helpers for the Assert.IQ pack test suite.
# ============================================================================
# PORTABILITY CONTRACT — this file and every test that sources it must run on:
#   * macOS   /bin/bash 3.2   (no mapfile, no `local -n`, no ${x,,})
#   * Linux   bash 4/5
#   * Windows Git Bash (MSYS2) bash 5
#
# Two environment problems this solves:
#
# 1. PYTHON. `python3` is not a reliable name.
#    - macOS/Linux: `python3` exists.
#    - Windows: the Microsoft Store ships a `python3` STUB that resolves on
#      PATH, prints an install hint and exits non-zero. Worse, the python.org
#      installer provides `python.exe` but NO `python3.exe`. So a machine can
#      have a perfectly good Python 3 that `python3` cannot reach.
#    We therefore probe candidates by EXECUTING them, not by `command -v`.
#
# 2. JQ. The suite used to require jq as a second external dependency. Every
#    use was simple JSON validation / key lookup, all expressible with the
#    Python we already require. jq is gone; do not reintroduce it.
# ============================================================================

AIQ_PY_BIN=""
AIQ_PY_PREARGS=""

# Resolve a working Python 3 into AIQ_PY_BIN (+ AIQ_PY_PREARGS). Returns 1 if
# none found. Must actually run the interpreter: presence on PATH proves
# nothing on Windows.
aiq_resolve_python() {
    [ -n "$AIQ_PY_BIN" ] && return 0
    local cand
    for cand in python3 python; do
        command -v "$cand" >/dev/null 2>&1 || continue
        if "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
            AIQ_PY_BIN="$cand"; AIQ_PY_PREARGS=""; return 0
        fi
    done
    # Windows py launcher, last because it is Windows-only.
    if command -v py >/dev/null 2>&1; then
        if py -3 -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
            AIQ_PY_BIN="py"; AIQ_PY_PREARGS="-3"; return 0
        fi
    fi
    return 1
}

# Run the resolved interpreter. Unquoted AIQ_PY_PREARGS is deliberate: it is
# either empty or the single token -3.
aiq_py() {
    aiq_resolve_python || return 127
    "$AIQ_PY_BIN" $AIQ_PY_PREARGS "$@"
}

aiq_python_label() {
    if aiq_resolve_python; then
        printf '%s %s' "$AIQ_PY_BIN" "$AIQ_PY_PREARGS"
    else
        printf 'none'
    fi
}

# --- JSON helpers (jq replacements) -----------------------------------------
# NOTE: paths are passed as argv, never interpolated into the -c source. Under
# MSYS, POSIX paths in argv are translated to Windows paths for native
# executables, but text inside a -c string literal is NOT, so an embedded
# /c/Users/... reaches native Python unconverted and open() fails.

# aiq_json_valid <file>   — file parses as JSON
aiq_json_valid() {
    aiq_py -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$1" >/dev/null 2>&1
}

# aiq_json_valid_stdin    — stdin parses as JSON
aiq_json_valid_stdin() {
    aiq_py -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1
}

# aiq_json_has <file> <dotted.path>  — key exists and is not null/false (jq -e)
aiq_json_has() {
    aiq_py -c '
import json, sys
cur = json.load(open(sys.argv[1], encoding="utf-8"))
for part in sys.argv[2].split("."):
    if not part:
        continue
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        sys.exit(1)
sys.exit(0 if cur is not None and cur is not False else 1)
' "$1" "$2" >/dev/null 2>&1
}

# aiq_json_has_stdin <dotted.path>
aiq_json_has_stdin() {
    aiq_py -c '
import json, sys
cur = json.load(sys.stdin)
for part in sys.argv[1].split("."):
    if not part:
        continue
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        sys.exit(1)
sys.exit(0 if cur is not None and cur is not False else 1)
' "$1" >/dev/null 2>&1
}

# aiq_json_get <file> <dotted.path>  — print the value ("" + rc1 if absent)
aiq_json_get() {
    aiq_py -c '
import json, sys
cur = json.load(open(sys.argv[1], encoding="utf-8"))
for part in sys.argv[2].split("."):
    if not part:
        continue
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        sys.exit(1)
print(cur if not isinstance(cur, bool) else str(cur).lower())
' "$1" "$2" 2>/dev/null
}

# aiq_json_test <file> <python expr over `d`>  — for assertions jq expressed
# with select(); e.g. "len(d['a'].get('enum',[])) > 0"
aiq_json_test() {
    aiq_py -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if eval(sys.argv[2]) else 1)
' "$1" "$2" >/dev/null 2>&1
}

# aiq_json_pretty <file>  — replacement for `python3 -m json.tool <file>`
aiq_json_pretty() {
    aiq_py -m json.tool "$1" >/dev/null 2>&1
}
