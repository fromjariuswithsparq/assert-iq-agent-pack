#!/bin/bash
# PostToolUse hook: when a file under UPS.GPMS.PanDAS.Client.UnitTests/ is edited,
# run `dotnet test` for that project in the background. Output goes to a log so
# the user (and agent on next turn) can inspect pass/fail.

set +e
trap 'echo "{\"continue\":true}"' EXIT

if [ -t 0 ]; then exit 0; fi
raw=$(cat)
[ -z "$raw" ] && exit 0

read -r TOOL FILE < <(python3 - "$raw" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.loads(sys.argv[1])
except Exception:
    print(" "); sys.exit(0)
tool = d.get("tool_name") or d.get("toolName") or ""
ti = d.get("tool_input") or d.get("toolArgs") or {}
fp = ti.get("filePath") or ti.get("file_path") or ti.get("path") or ""
print(f"{tool} {fp}")
PY
)

case "$TOOL" in
    replace_string_in_file|multi_replace_string_in_file|create_file|edit_notebook_file) ;;
    *) exit 0 ;;
esac

# Only when a UnitTests file is touched.
[[ "$FILE" == */UPS.GPMS.PanDAS.Client.UnitTests/*.cs ]] || exit 0
case "$FILE" in
    */obj/*|*/bin/*) exit 0 ;;
esac

PROJ="/Users/PTV6JHD/MDA/src/UPS.GPMS.PanDAS.Client.UnitTests"
LOG_DIR="$HOME/.agents/hooks/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/affected-tests.log"
LOCK="$LOG_DIR/affected-tests.lock"

# Coalesce concurrent triggers — if a run is already in flight, skip.
if ! ( set -o noclobber; echo $$ > "$LOCK" ) 2>/dev/null; then
    exit 0
fi

# Try to scope to the test class matching the edited file (e.g. Foo.cs → Foo).
CLASS=$(basename "$FILE" .cs)
FILTER=""
if [[ "$CLASS" == *Tests || "$CLASS" == *Test ]]; then
    FILTER="--filter FullyQualifiedName~.${CLASS}."
fi

(
    {
        echo "---- $(date -u +%FT%TZ) trigger: $FILE"
        echo "---- filter: ${FILTER:-<all>}"
        # shellcheck disable=SC2086
        dotnet test "$PROJ" --nologo --verbosity minimal $FILTER 2>&1
        echo "---- exit=$?"
    } >>"$LOG" 2>&1
    rm -f "$LOCK"
) &
disown 2>/dev/null || true

exit 0
