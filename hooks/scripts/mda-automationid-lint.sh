#!/bin/bash
# PostToolUse hook: lint edited .xaml for interactive elements missing AutomationId.
# Findings are written to a log AND surfaced to the agent via `systemMessage` so
# missing IDs are caught before they reach review.

set +e

FINDINGS=""
emit() {
    if [ -n "$FINDINGS" ]; then
        # Escape for JSON: backslashes, quotes, newlines.
        local msg
        msg=$(printf '%s' "$FINDINGS" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null)
        [ -z "$msg" ] && msg='"AutomationId lint reported issues."'
        printf '{"continue":true,"systemMessage":%s}\n' "$msg"
    else
        echo '{"continue":true}'
    fi
}
trap emit EXIT

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

[[ "$FILE" == /Users/PTV6JHD/MDA/src/*.xaml ]] || exit 0
case "$FILE" in
    */obj/*|*/bin/*) exit 0 ;;
esac
[ -f "$FILE" ] || exit 0

LOG_DIR="$HOME/.agents/hooks/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/automationid-lint.log"

FINDINGS=$(python3 - "$FILE" <<'PY' 2>/dev/null
import re, sys, pathlib
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace")
# Interactive controls per views instructions + common MAUI controls.
INTERACTIVE = {
    "Button","ImageButton","Entry","Editor","SearchBar","Picker","DatePicker",
    "TimePicker","CheckBox","Switch","Stepper","Slider","RadioButton",
    "RefreshView","ListView","CollectionView","CarouselView","TabbedPage",
    "SwipeView",
}
issues = []
# Match opening tags; allow namespace prefix (e.g. <ctrl:CustomButton ...>).
for m in re.finditer(r"<([A-Za-z_][\w.]*:)?([A-Za-z_]\w*)\b([^>]*?)(/?)>", text):
    tag = m.group(2)
    attrs = m.group(3) or ""
    if tag not in INTERACTIVE:
        continue
    if re.search(r'\bAutomationId\s*=', attrs):
        continue
    line = text.count("\n", 0, m.start()) + 1
    issues.append(f"  L{line}: <{tag}> missing AutomationId")
if issues:
    print(f"AutomationId lint — {path.name}:")
    print("\n".join(issues))
PY
)

if [ -n "$FINDINGS" ]; then
    {
        echo "---- $(date -u +%FT%TZ) $FILE"
        echo "$FINDINGS"
    } >>"$LOG"
fi

exit 0
