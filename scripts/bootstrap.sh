#!/usr/bin/env bash
# Assert.IQ Agent Pack — workspace bootstrap (macOS / Linux)
#
# Copies workspace-loaded surfaces (instructions, .assert-iq/, CLAUDE.md,
# copilot-instructions.md, AGENTS.md) from a plugin install into the
# user's workspace or user-global slots. Flag-driven; no interactive
# prompts (the agent does the prompting in chat).
#
# See .github/skills/assert-iq-bootstrap/SKILL.md for full docs.

set -euo pipefail

# ---- Defaults ---------------------------------------------------------------
PRESET=""
ASSERT_IQ=""
INSTRUCTIONS=""
CLAUDE_MD=""
COPILOT=""
AGENTS_MD=""
WORKSPACE="$PWD"
# Source: prefer CLAUDE_PLUGIN_ROOT, else parent dir of this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# ---- Parse flags ------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --preset=*)       PRESET="${arg#*=}" ;;
    --assert-iq=*)    ASSERT_IQ="${arg#*=}" ;;
    --instructions=*) INSTRUCTIONS="${arg#*=}" ;;
    --claude=*)       CLAUDE_MD="${arg#*=}" ;;
    --copilot=*)      COPILOT="${arg#*=}" ;;
    --agents=*)       AGENTS_MD="${arg#*=}" ;;
    --workspace=*)    WORKSPACE="${arg#*=}" ;;
    --source=*)       SOURCE="${arg#*=}" ;;
    --help|-h)
      sed -n '2,9p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "ERROR: unknown flag: $arg" >&2
      exit 2
      ;;
  esac
done

# ---- Apply preset defaults --------------------------------------------------
case "$PRESET" in
  solo)
    : "${ASSERT_IQ:=workspace}"
    : "${INSTRUCTIONS:=user}"
    : "${CLAUDE_MD:=user}"
    : "${COPILOT:=workspace}"
    : "${AGENTS_MD:=workspace}"
    ;;
  pod|"")
    : "${ASSERT_IQ:=workspace}"
    : "${INSTRUCTIONS:=workspace}"
    : "${CLAUDE_MD:=workspace}"
    : "${COPILOT:=workspace}"
    : "${AGENTS_MD:=workspace}"
    ;;
  *)
    echo "ERROR: unknown --preset value '$PRESET' (expected: solo, pod)" >&2
    exit 2
    ;;
esac

# ---- Resolve user-global paths by OS ----------------------------------------
case "$(uname -s)" in
  Darwin)
    USER_PROMPTS="$HOME/Library/Application Support/Code/User/prompts"
    ;;
  Linux|*)
    USER_PROMPTS="$HOME/.config/Code/User/prompts"
    ;;
esac
USER_ASSERT_IQ="$HOME/.assert-iq"
USER_CLAUDE_MD="$HOME/.claude/CLAUDE.md"

# ---- Result tracking --------------------------------------------------------
declare -a RESULTS=()

record() {
  # label | result | destination
  RESULTS+=("$1|$2|$3")
}

copy_if_absent() {
  local label="$1" src="$2" dst="$3"
  if [[ ! -e "$src" ]]; then
    record "$label" "missing-source" "$src"
    return
  fi
  if [[ -e "$dst" ]]; then
    record "$label" "skipped (already present)" "$dst"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -d "$src" ]]; then
    cp -R "$src" "$dst"
  else
    cp "$src" "$dst"
  fi
  record "$label" "copied" "$dst"
}

# ---- Per-surface handlers ---------------------------------------------------
process_assert_iq() {
  case "$ASSERT_IQ" in
    workspace) copy_if_absent ".assert-iq"  "$SOURCE/.assert-iq" "$WORKSPACE/.assert-iq" ;;
    user)      copy_if_absent ".assert-iq"  "$SOURCE/.assert-iq" "$USER_ASSERT_IQ" ;;
    skip)      record ".assert-iq" "skipped (user choice)" "-" ;;
    *) echo "ERROR: invalid --assert-iq value '$ASSERT_IQ'" >&2; exit 2 ;;
  esac
}

process_instructions() {
  case "$INSTRUCTIONS" in
    workspace)
      local dest="$WORKSPACE/.github/instructions"
      mkdir -p "$dest"
      shopt -s nullglob
      for f in "$SOURCE/.github/instructions/"*.instructions.md; do
        copy_if_absent "instructions/$(basename "$f")" "$f" "$dest/$(basename "$f")"
      done
      shopt -u nullglob
      ;;
    user)
      mkdir -p "$USER_PROMPTS"
      shopt -s nullglob
      for f in "$SOURCE/.github/instructions/"*.instructions.md; do
        copy_if_absent "instructions/$(basename "$f")" "$f" "$USER_PROMPTS/$(basename "$f")"
      done
      shopt -u nullglob
      ;;
    skip) record "instructions" "skipped (user choice)" "-" ;;
    *) echo "ERROR: invalid --instructions value '$INSTRUCTIONS'" >&2; exit 2 ;;
  esac
}

process_claude() {
  case "$CLAUDE_MD" in
    workspace) copy_if_absent "CLAUDE.md" "$SOURCE/CLAUDE.md" "$WORKSPACE/CLAUDE.md" ;;
    user)      copy_if_absent "CLAUDE.md" "$SOURCE/CLAUDE.md" "$USER_CLAUDE_MD" ;;
    skip)      record "CLAUDE.md" "skipped (user choice)" "-" ;;
    *) echo "ERROR: invalid --claude value '$CLAUDE_MD'" >&2; exit 2 ;;
  esac
}

process_copilot() {
  case "$COPILOT" in
    workspace)
      copy_if_absent "copilot-instructions.md" \
        "$SOURCE/.github/copilot-instructions.md" \
        "$WORKSPACE/.github/copilot-instructions.md"
      ;;
    user)
      echo "WARN: copilot-instructions.md has no native user-global slot. Skipping." >&2
      echo "      (The .instructions.md files under --instructions=user cover the" >&2
      echo "       same QI rules and load globally from the user prompts folder.)" >&2
      record "copilot-instructions.md" "skipped (no user-global slot)" "-"
      ;;
    skip) record "copilot-instructions.md" "skipped (user choice)" "-" ;;
    *) echo "ERROR: invalid --copilot value '$COPILOT'" >&2; exit 2 ;;
  esac
}

process_agents() {
  case "$AGENTS_MD" in
    workspace) copy_if_absent "AGENTS.md" "$SOURCE/AGENTS.md" "$WORKSPACE/AGENTS.md" ;;
    user)
      echo "WARN: AGENTS.md has no native user-global slot. Skipping." >&2
      record "AGENTS.md" "skipped (no user-global slot)" "-"
      ;;
    skip) record "AGENTS.md" "skipped (user choice)" "-" ;;
    *) echo "ERROR: invalid --agents value '$AGENTS_MD'" >&2; exit 2 ;;
  esac
}

process_assert_iq
process_instructions
process_claude
process_copilot
process_agents

# ---- Summary ----------------------------------------------------------------
echo ""
echo "=== Assert.IQ bootstrap summary ==="
echo "Source:    $SOURCE"
echo "Workspace: $WORKSPACE"
echo "Preset:    ${PRESET:-(none)}"
echo ""
printf "%-32s %-30s %s\n" "Surface" "Result" "Destination"
printf "%-32s %-30s %s\n" "-------" "------" "-----------"
for r in "${RESULTS[@]}"; do
  IFS='|' read -r label result dst <<< "$r"
  printf "%-32s %-30s %s\n" "$label" "$result" "$dst"
done
echo ""
echo "Reload your editor window so the new instructions and config are picked up:"
echo "  - VS Code:    Cmd/Ctrl + Shift + P -> 'Developer: Reload Window'"
echo "  - Claude Code: restart the session"
