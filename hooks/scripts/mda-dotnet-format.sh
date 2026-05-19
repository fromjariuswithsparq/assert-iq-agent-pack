#!/bin/bash
# PostToolUse hook: run `dotnet format` on edited C#/XAML files in the MDA solution.
# Fires in the background so it never blocks the agent; logs to ~/.agents/hooks/logs/.

set +e

# Always return success immediately so the agent is never blocked.
trap 'echo "{\"continue\":true}"' EXIT

if [ -t 0 ]; then exit 0; fi
raw=$(cat)
[ -z "$raw" ] && exit 0

# Parse with python3 (reliable on macOS) — fail silent on bad JSON.
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

# Only react to file-mutating tools.
case "$TOOL" in
    replace_string_in_file|multi_replace_string_in_file|create_file|edit_notebook_file) ;;
    *) exit 0 ;;
esac

# Only act on .cs files inside the MDA solution tree.
[[ "$FILE" == /Users/PTV6JHD/MDA/src/*.cs ]] || exit 0

# Skip generated files.
case "$FILE" in
    */obj/*|*/bin/*|*.g.cs|*.designer.cs|*.Designer.cs) exit 0 ;;
esac

SLN="/Users/PTV6JHD/MDA/src/UPS.GPMS.PanDAS.Client.sln"
LOG_DIR="$HOME/.agents/hooks/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/dotnet-format.log"

{
    echo "---- $(date -u +%FT%TZ) format: $FILE"
    dotnet format "$SLN" --include "$FILE" --no-restore --verbosity quiet 2>&1
    echo "---- exit=$?"
} >>"$LOG" 2>&1 &
disown 2>/dev/null || true

exit 0
