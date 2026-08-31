#!/bin/bash
# ============================================================================
# sync-agents.sh — render Copilot specialist agents from the Claude sources.
# ============================================================================
# WHY THIS EXISTS
#
# `.claude/skills` is a symlink to `.github/skills`, so skills cannot drift.
# Agents have no such link, because the two harnesses use incompatible
# frontmatter schemas:
#
#   Claude Code   tools: Read, Grep, Glob
#   VS Code       tools: ['codebase', 'search', 'usages']
#
# At v2.0 that cost a whole release: the 8-specialist orchestrator was added to
# .claude/agents/ only, so Copilot users silently kept v1.x single-agent
# routing. Hand-maintaining 8 specialists x 2 schemas is what failed; this
# script makes the Claude files the single source of truth and derives the
# Copilot side mechanically.
#
# SCOPE — deliberately limited to the specialists.
#
#   IN  .claude/agents/specialists/*.md  ->  .github/agents/specialists/*.agent.md
#
#   The lead (Assert-IQ) and planner (Assert-IQ-PLAN) are NOT generated. Their
#   prose is genuinely harness-specific — Copilot has handoff buttons and MCP
#   servers (azureDevOps, atlassian) with no Claude equivalent, while the Claude
#   versions talk about invoking subagents. Rendering one from the other would
#   destroy hand-authored, correct content. Their one mechanical concern —
#   whether every shipped skill is routable — is enforced separately by check P3
#   in .assert-iq/tests/_qi/automated/e2e-agent-parity.sh.
#
# USAGE
#   bash scripts/sync-agents.sh           # write/refresh generated files
#   bash scripts/sync-agents.sh --check   # verify they are current (CI/parity)
#
# PORTABILITY: bash 3.2 (macOS /bin/bash). No mapfile, no `local -n`.
# ============================================================================

set -uo pipefail

MODE="write"
case "${1:-}" in
  --check)     MODE="check" ;;
  --print-map) MODE="printmap" ;;
  "")          MODE="write" ;;
  *) echo "usage: $0 [--check|--print-map]" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$ROOT/.claude/agents/specialists"
DST_DIR="$ROOT/.github/agents/specialists"

# --- tool-name mapping ------------------------------------------------------
# Claude Code tool -> VS Code Copilot tool. These Copilot names are the ones
# already in use by .github/agents/Assert-IQ.agent.md, so they are known-good in
# this pack rather than guessed from docs. If a future VS Code release renames
# tools, THIS TABLE is the only place to change.
# Held as DATA, not a case statement, so --print-map can enumerate it. Check P6
# in e2e-agent-parity.sh compares this against the $ToolMap table in
# sync-agents.ps1, so the two implementations cannot silently diverge and emit
# different agents depending on which OS ran the sync.
TOOL_MAP='Read=codebase
Grep=search
Glob=search
Bash=runCommands
Edit=editFiles
Write=editFiles
WebFetch=fetch
WebSearch=fetch
Agent=agent/runSubagent'

map_tool() {
  local _line
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    case "$_line" in
      "$1="*) printf '%s' "${_line#*=}"; return 0 ;;
    esac
  done <<< "$TOOL_MAP"
  return 1
}

fail() { echo "sync-agents: $*" >&2; exit 1; }

# Emit the tool map, one Claude=Copilot pair per line, sorted. Consumed by
# check P6 so the two implementations' tables cannot drift apart.
if [ "$MODE" = "printmap" ]; then
  printf '%s\n' "$TOOL_MAP" | grep -v '^$' | sort -u
  exit 0
fi

[ -d "$SRC_DIR" ] || fail "missing source dir: $SRC_DIR"
mkdir -p "$DST_DIR"

# Read a single frontmatter field (first match) from a file.
fm_field() {
  awk -v key="$2" '
    NR==1 && $0!="---" { exit }
    NR==1 { next }
    /^---[[:space:]]*$/ { exit }
    index($0, key ":") == 1 { sub("^" key ":[[:space:]]*", ""); print; exit }
  ' "$1"
}

# Print the body (everything after the closing --- of the frontmatter).
fm_body() {
  awk 'BEGIN{n=0}
    NR==1 && $0=="---" { n=1; next }
    n==1 && /^---[[:space:]]*$/ { n=2; next }
    n==2 { print }
  ' "$1"
}

render_one() {
  # $1 = source .md path ; prints the rendered Copilot agent to stdout
  local src="$1" name desc tools_raw t mapped seen out_tools
  name="$(fm_field "$src" name)"
  desc="$(fm_field "$src" description)"
  tools_raw="$(fm_field "$src" tools)"

  [ -n "$name" ] || fail "$src: no name: field"
  [ -n "$desc" ] || fail "$src: no description: field"

  # Normalize "A, B, C" and [A, B, C] spellings, then map + dedupe (order kept).
  tools_raw="${tools_raw//\[/ }"; tools_raw="${tools_raw//\]/ }"
  tools_raw="${tools_raw//\'/ }"; tools_raw="${tools_raw//\"/ }"
  tools_raw="${tools_raw//,/ }"
  seen=" "
  out_tools=""
  for t in $tools_raw; do
    [ -n "$t" ] || continue
    if ! mapped="$(map_tool "$t")"; then
      echo "sync-agents: WARNING $name: no Copilot equivalent for tool '$t' (dropped)" >&2
      continue
    fi
    case "$seen" in *" $mapped "*) continue ;; esac
    seen="$seen$mapped "
    if [ -z "$out_tools" ]; then out_tools="'$mapped'"; else out_tools="$out_tools, '$mapped'"; fi
  done
  [ -n "$out_tools" ] || fail "$name: mapped to an empty tool list"

  printf -- '---\n'
  printf -- 'name: %s\n' "$name"
  printf -- 'description: %s\n' "$desc"
  printf -- 'tools: [%s]\n' "$out_tools"
  printf -- '---\n'
  printf -- '\n'
  printf -- '<!-- ------------------------------------------------------------------\n'
  printf -- '     GENERATED FILE - DO NOT EDIT.\n'
  printf -- '     Rendered from .claude/agents/specialists/%s\n' "${src##*/}"
  printf -- '     by scripts/sync-agents.sh (tool names mapped Claude -> Copilot).\n'
  printf -- '     To change this agent, edit the Claude source and re-run:\n'
  printf -- '       bash scripts/sync-agents.sh\n'
  printf -- '     Staleness is enforced by check P5 in\n'
  printf -- '     .assert-iq/tests/_qi/automated/e2e-agent-parity.sh\n'
  printf -- '     ------------------------------------------------------------------ -->\n'
  fm_body "$src"
}

rc=0
count=0
stale=""

for src in "$SRC_DIR"/*.md; do
  [ -f "$src" ] || continue
  base="${src##*/}"
  dst="$DST_DIR/${base%.md}.agent.md"
  count=$((count + 1))
  rendered="$(render_one "$src")"

  if [ "$MODE" = "check" ]; then
    if [ ! -f "$dst" ]; then
      stale="$stale
  MISSING  ${dst#$ROOT/}"
      rc=1
    # Strip CR before comparing. Line endings are a CHECKOUT artifact, not a
    # content difference: on Windows with core.autocrlf=true (the default) a
    # clean clone lands .agent.md as CRLF, and a byte comparison against
    # LF-rendered output then reports every file STALE -- so check P5 failed on
    # a clean Windows clone and told the maintainer their generated agents were
    # out of date when they were correct. .gitattributes now pins this tree to
    # LF as well; this is the belt to that braces, and it also covers a
    # hand-edited or hand-copied tree. sync-agents.ps1 has always normalized on
    # read, so only the bash side was wrong.
    elif [ "$rendered" != "$(tr -d '\r' < "$dst")" ]; then
      stale="$stale
  STALE    ${dst#$ROOT/}"
      rc=1
    fi
  else
    printf '%s\n' "$rendered" > "$dst"
    echo "  rendered ${dst#$ROOT/}"
  fi
done

# Generated outputs with no corresponding source must not linger.
for dst in "$DST_DIR"/*.agent.md; do
  [ -f "$dst" ] || continue
  b="${dst##*/}"; b="${b%.agent.md}"
  if [ ! -f "$SRC_DIR/$b.md" ]; then
    if [ "$MODE" = "check" ]; then
      stale="$stale
  ORPHAN   ${dst#$ROOT/} (no .claude source)"
      rc=1
    else
      rm -f "$dst"
      echo "  removed  ${dst#$ROOT/} (source deleted)"
    fi
  fi
done

if [ "$MODE" = "check" ]; then
  if [ $rc -eq 0 ]; then
    echo "sync-agents: $count generated Copilot specialist(s) are current"
  else
    echo "sync-agents: generated Copilot agents are OUT OF DATE:$stale"
    echo ""
    echo "Fix with:  bash scripts/sync-agents.sh"
  fi
  exit $rc
fi

echo "sync-agents: $count specialist(s) synced -> ${DST_DIR#$ROOT/}"
exit 0
