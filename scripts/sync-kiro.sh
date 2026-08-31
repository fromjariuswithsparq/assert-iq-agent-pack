#!/bin/bash
# ============================================================================
# sync-kiro.sh — render the Kiro harness surfaces from their existing sources.
# ============================================================================
# WHY THIS EXISTS
#
# Kiro is the pack's third harness. It reads none of .github/*, none of
# .claude/*, and no CLAUDE.md — only .kiro/*. Two of its surfaces are pure
# translations of files the pack already maintains, so they are GENERATED
# rather than hand-copied:
#
#   .github/instructions/*.instructions.md  ->  .kiro/steering/*.md
#   .claude/agents/specialists/*.md         ->  .kiro/agents/*.md
#
# Hand-maintaining the QI rulebook across three harnesses is exactly what
# failed at v2.0, when the 8-specialist orchestrator landed in .claude/agents/
# only and Copilot users silently kept v1.x routing for a whole release. Two
# harnesses were already one too many to do by hand; three is hopeless.
#
# The alternative to generating steering was to write thin .kiro/steering/
# files that point at .github/instructions/ via Kiro's "#[[file:...]]"
# reference. Rejected deliberately: a Kiro-only consumer who never installed
# .github/ gets a dangling reference that degrades SILENTLY, which is the
# exact failure shape this pack keeps getting bitten by. Generated files plus
# --check fail LOUDLY instead.
#
# SCOPE — deliberately limited.
#
#   IN   .github/instructions/*.instructions.md -> .kiro/steering/<base>.md
#   IN   .claude/agents/specialists/*.md        -> .kiro/agents/<base>.md
#
#   NOT GENERATED, hand-authored per harness:
#     .kiro/steering/00-assert-iq.md   (the Kiro entrypoint; Kiro has no
#                                       CLAUDE.md equivalent, so the pointer
#                                       file IS steering)
#     .kiro/agents/assert-iq.md        (lead)
#     .kiro/agents/assert-iq-plan.md   (planner)
#
#   The lead and planner are excluded for the same reason sync-agents.sh
#   excludes them: their prose is genuinely harness-specific. Kiro has specs,
#   dispatchKind, Powers and #[[file:]] with no Claude equivalent. Rendering
#   one from the other would destroy correct content. That every shipped skill
#   stays routable is enforced separately by check P3 in
#   .assert-iq/tests/_qi/automated/e2e-agent-parity.sh.
#
# CONTRACT: .assert-iq/kiro-harness.md — every schema fact below was verified
# against a real Kiro 1.0.337 install, not against kiro.dev docs, which are
# wrong about the agent file format (they say JSON; the binary requires .md).
#
# USAGE
#   bash scripts/sync-kiro.sh              # write/refresh generated files
#   bash scripts/sync-kiro.sh --check      # verify they are current (CI/parity)
#   bash scripts/sync-kiro.sh --print-map  # emit the tool map (parity check)
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

INSTR_DIR="$ROOT/.github/instructions"
SPEC_SRC_DIR="$ROOT/.claude/agents/specialists"
STEERING_DIR="$ROOT/.kiro/steering"
AGENTS_DIR="$ROOT/.kiro/agents"

# Hand-authored files in the generated directories. Never written, never
# treated as orphans. Keep in step with $KiroHandAuthored in sync-kiro.ps1.
HAND_AUTHORED_STEERING="00-assert-iq.md"
HAND_AUTHORED_AGENTS="assert-iq.md assert-iq-plan.md"

# --- tool-name mapping ------------------------------------------------------
# Claude Code tool -> Kiro tool TAG.
#
# Tags, not tool names. Kiro's own bundled agent-authoring guidance is
# explicit: "Use tags exclusively instead of specific tool names. This ensures
# your custom agent definitions remain stable as tools are renamed." The
# underlying names genuinely churn — fs_write, fsWrite and str_replace all
# coexist in 1.0.337 — while the tags are the documented stable surface.
#
# Grep and Glob both fold into `read`: Kiro's `read` tag covers file_search
# and grep_search alongside read_file. That collapse is why the renderer
# dedupes while preserving order.
#
# Held as DATA, not a case statement, so --print-map can enumerate it. Check
# P8 in e2e-agent-parity.sh compares this against $ToolMap in sync-kiro.ps1,
# so the two implementations cannot silently diverge and emit different agents
# depending on which OS ran the sync.
TOOL_MAP='Read=read
Grep=read
Glob=read
Bash=shell
Edit=write
Write=write
WebFetch=web
WebSearch=web
Agent=subagent'

# Resources every generated Kiro agent must declare.
#
# THIS IS NOT OPTIONAL. Kiro custom agents do NOT inherit steering or skills
# the way the default agent does — they load only what `resources` names. A
# specialist without these two globs runs with no QI rulebook at all, and
# because Kiro DROPS INVALID RESOURCE ENTRIES SILENTLY, a typo here is
# invisible at runtime. unit-kiro-schema.py fails the build if either glob is
# missing from a generated agent.
AGENT_RESOURCES='  - "file://.kiro/steering/**/*.md"
  - "skill://.kiro/skills/**/SKILL.md"'

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

fail() { echo "sync-kiro: $*" >&2; exit 1; }

if [ "$MODE" = "printmap" ]; then
  printf '%s\n' "$TOOL_MAP" | grep -v '^$' | sort -u
  exit 0
fi

[ -d "$INSTR_DIR" ]    || fail "missing source dir: $INSTR_DIR"
[ -d "$SPEC_SRC_DIR" ] || fail "missing source dir: $SPEC_SRC_DIR"

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

# Strip one layer of surrounding single/double quotes.
unquote() {
  local s="$1"
  case "$s" in
    \"*\") s="${s#\"}"; s="${s%\"}" ;;
    \'*\') s="${s#\'}"; s="${s%\'}" ;;
  esac
  printf '%s' "$s"
}

# Turn a Copilot `applyTo` value into one Kiro fileMatchPattern per line.
#
# Done entirely in awk, deliberately. The obvious bash version -- split on
# commas with IFS, loop over the words -- is wrong twice over, and both bugs
# are silent:
#
#   1. Splitting on commas BEFORE expanding braces shreds a brace group.
#      qi-traceability's applyTo is one 22-extension group, so
#      `**/*.{cs,xaml,ts}` became `**/*.{cs`, `xaml`, `ts`.
#   2. Iterating an unquoted variable lets the shell PATHNAME-EXPAND the
#      pattern against the pack itself. `tests/**` matched a real directory
#      and was rewritten to `tests/_qi` -- a pattern that looks plausible in
#      review and quietly stops matching the user's tests.
#
# awk has neither hazard: no word splitting, no globbing.
#
# Brace expansion happens here because Kiro's own brace support in
# fileMatchPattern is UNVERIFIED (kiro-harness.md §8). If Kiro does not expand
# braces, the traceability instruction would match nothing and traceability
# enforcement would be silently dead on every Kiro workspace -- the worst
# possible failure for the one rule that must fire on every production-code
# edit. Expanding here costs nothing and removes the bet.
#
# More than one brace group in a single pattern is refused, not half-expanded.
expand_apply_to() {
  awk -v apply="$1" -v src="$2" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    BEGIN {
      # Split on top-level commas only: a comma inside {...} belongs to a
      # brace group, not to the applyTo list.
      n = length(apply); depth = 0; seg = ""; nseg = 0
      for (i = 1; i <= n; i++) {
        c = substr(apply, i, 1)
        if (c == "{") depth++
        else if (c == "}") depth--
        if (c == "," && depth == 0) { segs[++nseg] = seg; seg = "" }
        else seg = seg c
      }
      segs[++nseg] = seg

      for (s = 1; s <= nseg; s++) {
        pat = trim(segs[s])
        if (pat == "") continue
        ob = index(pat, "{")
        cb = index(pat, "}")
        if (ob == 0 || cb == 0) { print pat; continue }
        pre   = substr(pat, 1, ob - 1)
        inner = substr(pat, ob + 1, cb - ob - 1)
        post  = substr(pat, cb + 1)
        if (index(post, "{") > 0) {
          printf("sync-kiro: %s: more than one brace group in \"%s\" (unsupported)\n", src, pat) > "/dev/stderr"
          exit 1
        }
        m = split(inner, alts, ",")
        for (a = 1; a <= m; a++) {
          alt = trim(alts[a])
          if (alt != "") print pre alt post
        }
      }
    }'
}

# ---------------------------------------------------------------------------
# Steering: .github/instructions/<x>.instructions.md -> .kiro/steering/<x>.md
# ---------------------------------------------------------------------------
render_steering() {
  local src="$1" apply desc base patterns
  apply="$(unquote "$(fm_field "$src" applyTo)")"
  desc="$(unquote "$(fm_field "$src" description)")"
  base="${src##*/}"; base="${base%.instructions.md}"

  [ -n "$apply" ] || fail "$src: no applyTo: field"

  printf -- '---\n'
  if [ "$apply" = "**" ]; then
    # applyTo "**" is Copilot's always-on. Kiro's equivalent is inclusion:
    # always -- which is ALSO the default when inclusion is absent, but state
    # it explicitly so the intent survives a reader who does not know that.
    printf -- 'inclusion: always\n'
  else
    patterns="$(expand_apply_to "$apply" "${src##*/}")" \
      || fail "${src##*/}: could not expand applyTo"
    [ -n "$patterns" ] || fail "${src##*/}: applyTo '$apply' expanded to nothing"
    printf -- 'inclusion: fileMatch\n'
    # Always emit an ARRAY even for a single pattern, so the shape never
    # varies across the six generated files. Kiro accepts string or array;
    # one shape is easier to assert on.
    printf -- 'fileMatchPattern:\n'
    printf -- '%s\n' "$patterns" | while IFS= read -r p; do
      [ -n "$p" ] || continue
      printf -- '  - "%s"\n' "$p"
    done
  fi
  [ -n "$desc" ] && printf -- 'description: "%s"\n' "$desc"
  printf -- '---\n'
  printf -- '\n'
  printf -- '<!-- ------------------------------------------------------------------\n'
  printf -- '     GENERATED FILE - DO NOT EDIT.\n'
  printf -- '     Rendered from .github/instructions/%s\n' "${src##*/}"
  printf -- '     by scripts/sync-kiro.sh (applyTo -> inclusion/fileMatchPattern).\n'
  printf -- '     To change this steering file, edit the instruction source and\n'
  printf -- '     re-run:\n'
  printf -- '       bash scripts/sync-kiro.sh\n'
  printf -- '     Staleness is enforced by check P7 in\n'
  printf -- '     .assert-iq/tests/_qi/automated/e2e-agent-parity.sh\n'
  printf -- '     Contract: .assert-iq/kiro-harness.md\n'
  printf -- '     ------------------------------------------------------------------ -->\n'
  fm_body "$src"
}

# ---------------------------------------------------------------------------
# Agents: .claude/agents/specialists/<x>.md -> .kiro/agents/<x>.md
# ---------------------------------------------------------------------------
render_agent() {
  local src="$1" name desc tools_raw t mapped seen out_tools
  name="$(fm_field "$src" name)"
  desc="$(fm_field "$src" description)"
  tools_raw="$(fm_field "$src" tools)"

  [ -n "$name" ] || fail "$src: no name: field"
  [ -n "$desc" ] || fail "$src: no description: field"

  # Normalize "A, B, C" and [A, B, C] spellings, then map + dedupe (order
  # kept). Dedupe matters more here than on the Copilot side: Read/Grep/Glob
  # all collapse to `read`.
  tools_raw="${tools_raw//\[/ }"; tools_raw="${tools_raw//\]/ }"
  tools_raw="${tools_raw//\'/ }"; tools_raw="${tools_raw//\"/ }"
  tools_raw="${tools_raw//,/ }"
  seen=" "
  out_tools=""
  for t in $tools_raw; do
    [ -n "$t" ] || continue
    if ! mapped="$(map_tool "$t")"; then
      echo "sync-kiro: WARNING $name: no Kiro tag for tool '$t' (dropped)" >&2
      continue
    fi
    case "$seen" in *" $mapped "*) continue ;; esac
    seen="$seen$mapped "
    if [ -z "$out_tools" ]; then out_tools="\"$mapped\""; else out_tools="$out_tools, \"$mapped\""; fi
  done
  [ -n "$out_tools" ] || fail "$name: mapped to an empty tool list"

  printf -- '---\n'
  printf -- 'name: %s\n' "$name"
  printf -- 'description: %s\n' "$desc"
  printf -- 'tools: [%s]\n' "$out_tools"
  # "sub-agent" is what makes this delegable from the lead. Without it the
  # file is a standalone custom agent the orchestrator cannot spawn.
  printf -- 'dispatchKind: sub-agent\n'
  printf -- 'resources:\n'
  printf -- '%s\n' "$AGENT_RESOURCES"
  printf -- '---\n'
  printf -- '\n'
  printf -- '<!-- ------------------------------------------------------------------\n'
  printf -- '     GENERATED FILE - DO NOT EDIT.\n'
  printf -- '     Rendered from .claude/agents/specialists/%s\n' "${src##*/}"
  printf -- '     by scripts/sync-kiro.sh (tool names mapped Claude -> Kiro tags).\n'
  printf -- '     To change this agent, edit the Claude source and re-run:\n'
  printf -- '       bash scripts/sync-kiro.sh\n'
  printf -- '     Staleness is enforced by check P7 in\n'
  printf -- '     .assert-iq/tests/_qi/automated/e2e-agent-parity.sh\n'
  printf -- '     Contract: .assert-iq/kiro-harness.md\n'
  printf -- '     ------------------------------------------------------------------ -->\n'
  fm_body "$src"
}

# ---------------------------------------------------------------------------
# Drive
# ---------------------------------------------------------------------------
rc=0
count=0
stale=""

emit() {
  # $1 = rendered content, $2 = destination path
  local rendered="$1" dst="$2"
  count=$((count + 1))
  if [ "$MODE" = "check" ]; then
    if [ ! -f "$dst" ]; then
      stale="$stale
  MISSING  ${dst#"$ROOT"/}"
      rc=1
    elif [ "$rendered" != "$(cat "$dst")" ]; then
      stale="$stale
  STALE    ${dst#"$ROOT"/}"
      rc=1
    fi
  else
    printf '%s\n' "$rendered" > "$dst"
    echo "  rendered ${dst#"$ROOT"/}"
  fi
}

is_hand_authored() {
  # $1 = basename, $2 = space-separated set
  case " $2 " in *" $1 "*) return 0 ;; esac
  return 1
}

[ "$MODE" = "check" ] || mkdir -p "$STEERING_DIR" "$AGENTS_DIR"

for src in "$INSTR_DIR"/*.instructions.md; do
  [ -f "$src" ] || continue
  base="${src##*/}"; base="${base%.instructions.md}"
  emit "$(render_steering "$src")" "$STEERING_DIR/$base.md"
done

for src in "$SPEC_SRC_DIR"/*.md; do
  [ -f "$src" ] || continue
  base="${src##*/}"
  emit "$(render_agent "$src")" "$AGENTS_DIR/$base"
done

# Generated outputs with no corresponding source must not linger. Hand-authored
# files in the same directories are skipped -- they have no source by design.
for dst in "$STEERING_DIR"/*.md; do
  [ -f "$dst" ] || continue
  b="${dst##*/}"
  is_hand_authored "$b" "$HAND_AUTHORED_STEERING" && continue
  if [ ! -f "$INSTR_DIR/${b%.md}.instructions.md" ]; then
    if [ "$MODE" = "check" ]; then
      stale="$stale
  ORPHAN   ${dst#"$ROOT"/} (no instruction source)"
      rc=1
    else
      rm -f "$dst"
      echo "  removed  ${dst#"$ROOT"/} (source deleted)"
    fi
  fi
done

for dst in "$AGENTS_DIR"/*.md; do
  [ -f "$dst" ] || continue
  b="${dst##*/}"
  is_hand_authored "$b" "$HAND_AUTHORED_AGENTS" && continue
  if [ ! -f "$SPEC_SRC_DIR/$b" ]; then
    if [ "$MODE" = "check" ]; then
      stale="$stale
  ORPHAN   ${dst#"$ROOT"/} (no .claude specialist source)"
      rc=1
    else
      rm -f "$dst"
      echo "  removed  ${dst#"$ROOT"/} (source deleted)"
    fi
  fi
done

if [ "$MODE" = "check" ]; then
  if [ $rc -eq 0 ]; then
    echo "sync-kiro: $count generated Kiro file(s) are current"
  else
    echo "sync-kiro: generated Kiro files are OUT OF DATE:$stale"
    echo ""
    echo "Fix with:  bash scripts/sync-kiro.sh"
  fi
  exit $rc
fi

echo "sync-kiro: $count file(s) synced -> .kiro/steering/, .kiro/agents/"
exit 0
