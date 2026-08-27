#!/bin/bash
# ============================================================================
# UNIT: Claude Code agent frontmatter schema validation
# ============================================================================
# WHY THIS EXISTS
#
# At v2.0 all 8 specialist subagents under .claude/agents/specialists/ shipped
# with VS Code Copilot frontmatter instead of Claude Code frontmatter:
#
#   mode: agent                                          <- not a Claude key
#   tools: [vscode_readFile, grep_search, semantic_search] <- not Claude tools
#   context: isolated                                    <- not a Claude key
#
# Claude Code registered the agents but resolved the tool allowlist to a set of
# names that do not exist, leaving every specialist with no working tools. The
# pre-existing orchestration tests only asserted that a `name:` field was
# present, so this was invisible to CI.
#
# This test validates the frontmatter schema itself: legal tool names, no
# foreign-harness keys, name/filename agreement, and resolvable model ids.
#
# Run from the repo root.
# ============================================================================

PASSED=0
FAILED=0

pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

# Tool names Claude Code actually exposes to subagents.
VALID_TOOLS="Read Grep Glob Bash Edit Write WebFetch WebSearch Agent Task \
NotebookEdit AskUserQuestion TodoWrite BashOutput KillShell SlashCommand Skill"

# Frontmatter keys that belong to VS Code Copilot's agent schema, not Claude's.
FOREIGN_KEYS="mode context target argument-hint disable-model-invocation \
handoffs agents applyTo"

# Model ids/aliases Claude Code accepts. Bare aliases are preferred because
# they track the current generation without needing edits.
VALID_MODELS="sonnet opus haiku fable inherit"

echo "=== UNIT: Claude Agent Frontmatter Schema ==="
echo ""

# Collect every Claude agent definition.
# NOTE: a while-read loop, not `mapfile`. mapfile is bash 4.0+, and macOS still
# ships bash 3.2 as /bin/bash -- this suite must run there unchanged.
AGENT_FILES=()
while IFS= read -r _f; do
  [ -n "$_f" ] && AGENT_FILES[${#AGENT_FILES[@]}]="$_f"
done <<< "$(find .claude/agents -name '*.md' 2>/dev/null | sort)"

if [ ${#AGENT_FILES[@]} -eq 0 ]; then
  fail "no agent files found under .claude/agents/"
  echo ""
  echo "=== Results: $PASSED PASS, $FAILED FAIL ==="
  exit 1
fi

echo "Validating ${#AGENT_FILES[@]} agent definition(s)."
echo ""

extract_frontmatter() {
  # Print the YAML frontmatter block (between the first two --- lines).
  awk 'NR==1 && $0!="---" { exit } NR==1 { next } /^---[[:space:]]*$/ { exit } { print }' "$1"
}

# Strip surrounding whitespace then surrounding double quotes, in place.
# Done with parameter expansion rather than sed: this runs per-field per-agent,
# and on Windows each subprocess costs ~100ms, which turned this suite into a
# 115s test (and pushed e2e-comprehensive-validation past its budget).
# Sets AIQ_TRIMMED. Uses a global rather than a nameref: `local -n` is bash
# 4.3+, and macOS ships bash 3.2.
AIQ_TRIMMED=""
trim_val() {
  local _s="$1"
  _s="${_s#"${_s%%[![:space:]]*}"}"
  _s="${_s%"${_s##*[![:space:]]}"}"
  _s="${_s%\"}"
  _s="${_s#\"}"
  AIQ_TRIMMED="$_s"
}

for file in "${AGENT_FILES[@]}"; do
  label="${file#.claude/agents/}"
  fm="$(extract_frontmatter "$file")"

  if [ -z "$fm" ]; then
    fail "$label: missing or empty YAML frontmatter"
    continue
  fi

  # Single pass over the frontmatter, no subprocess per key.
  name_val=""; desc_present=0; tools_line=""; model_val=""
  has_tools_key=0; found_foreign=""
  while IFS= read -r _line; do
    case "$_line" in
      name:*)        name_val="${_line#name:}" ;;
      description:*) desc_present=1 ;;
      tools:*)       tools_line="${_line#tools:}"; has_tools_key=1 ;;
      model:*)       model_val="${_line#model:}" ;;
      mode:*|context:*|target:*|argument-hint:*|disable-model-invocation:*|handoffs:*|agents:*|applyTo:*)
                     found_foreign="$found_foreign ${_line%%:*}" ;;
    esac
  done <<< "$fm"
  trim_val "$name_val";  name_val="$AIQ_TRIMMED"
  trim_val "$model_val"; model_val="$AIQ_TRIMMED"

  # --- name present and matching the filename -----------------------------
  stem="${file##*/}"; stem="${stem%.md}"
  if [ -z "$name_val" ]; then
    fail "$label: no 'name:' field"
  elif [ "$name_val" = "$stem" ]; then
    pass "$label: name matches filename"
  else
    # grader.md intentionally uses a display name ("Oracle Grader"); flag it as
    # a soft mismatch rather than pretending it is fine.
    fail "$label: name '$name_val' does not match filename stem '$stem' (invocation name and file will disagree)"
  fi

  # --- description present ------------------------------------------------
  if [ "$desc_present" -eq 1 ]; then
    pass "$label: has description"
  else
    fail "$label: no 'description:' field"
  fi

  # --- no foreign-harness keys -------------------------------------------
  if [ -z "$found_foreign" ]; then
    pass "$label: no foreign-harness frontmatter keys"
  else
    fail "$label: Copilot-only frontmatter key(s):$found_foreign"
  fi

  # --- tools must all be real Claude Code tool names ---------------------
  if [ "$has_tools_key" -eq 1 ]; then
    # Normalize both accepted spellings: "A, B, C" and [A, B, C] / ['a','b'].
    tools_norm="${tools_line//\[/ }"; tools_norm="${tools_norm//\]/ }"
    tools_norm="${tools_norm//\'/ }"; tools_norm="${tools_norm//\"/ }"
    tools_norm="${tools_norm//,/ }"
    bad_tools=""
    for t in $tools_norm; do
      [ -n "$t" ] || continue
      case " $VALID_TOOLS " in
        *" $t "*) ;;
        *) bad_tools="$bad_tools $t" ;;
      esac
    done
    if [ -z "$bad_tools" ]; then
      pass "$label: all declared tools are valid Claude Code tools"
    else
      fail "$label: unknown tool name(s):$bad_tools  (agent will have no working tools for these)"
    fi
  else
    # No tools key = inherit everything. Legal, but call it out for agents whose
    # own contract claims read-only or isolated behaviour.
    if grep -qiE 'read-only|independent|isolat' "$file"; then
      fail "$label: no 'tools:' allowlist, but the prompt claims read-only/isolated behaviour (it inherits Write/Edit/Bash)"
    else
      pass "$label: no tools allowlist (inherits all tools) — acceptable"
    fi
  fi

  # --- model id must be resolvable ---------------------------------------
  if [ -n "$model_val" ]; then
    case " $VALID_MODELS " in
      *" $model_val "*)
        pass "$label: model '$model_val' is a valid alias"
        ;;
      *)
        # Allow fully-qualified ids like claude-sonnet-5 / claude-opus-5[1m].
        # `case` glob, not =~: bash 3.2 mishandles escaped brackets in regexes.
        case "$model_val" in
          claude-*-[0-9]|claude-*-[0-9][0-9]|claude-*-[0-9]'[1m]'|claude-*-[0-9][0-9]'[1m]')
            pass "$label: model '$model_val' is a fully-qualified id" ;;
          *)
            fail "$label: unresolvable model id '$model_val' (use an alias: $VALID_MODELS)" ;;
        esac
        ;;
    esac
  fi

  echo ""
done

echo "=== Results: $PASSED PASS, $FAILED FAIL ==="
[ $FAILED -eq 0 ] && exit 0 || exit 1
