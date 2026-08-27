#!/bin/bash
# ============================================================================
# E2E: Cross-harness agent parity (.claude/agents vs .github/agents)
# ============================================================================
# WHY THIS EXISTS
#
# `.claude/skills` is a symlink to `.github/skills`, so skills cannot drift.
# Agents have no such link: the two harnesses use incompatible frontmatter
# schemas (Claude Code: `tools: Read, Grep, Glob`; VS Code Copilot:
# `tools: ['codebase','search','editFiles']`), so each side is hand-maintained.
# Nothing enforced that they stay in step, and at v2.0 they diverged badly —
# the Claude side gained an 8-specialist orchestrator that the Copilot side
# never received, and 5 skills became unreachable from the Copilot router.
#
# RESOLUTION (post-v2.0.2): the Copilot specialists are no longer hand-written.
# scripts/sync-agents.sh renders .github/agents/specialists/*.agent.md from
# .claude/agents/specialists/*.md, mapping tool names between the two schemas.
# P5 fails if those generated files are stale; P6 fails if the bash and
# PowerShell implementations of the mapping table disagree. The lead/planner
# agents stay hand-authored per harness on purpose (their prose is genuinely
# harness-specific); their only mechanical concern is covered by P3.
#
# This check is STRICT: any divergence fails. It is meant to be a forcing
# function, not a formality. If a divergence is a deliberate product decision,
# encode that decision here explicitly rather than loosening the check.
#
# Run from the repo root.
# ============================================================================

PASSED=0
FAILED=0
DIVERGENCES=()

pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); DIVERGENCES+=("$1"); }

CLAUDE_DIR=".claude/agents"
COPILOT_DIR=".github/agents"
CLAUDE_ROUTER="$CLAUDE_DIR/assert-iq.md"
COPILOT_ROUTER="$COPILOT_DIR/Assert-IQ.agent.md"

echo "=== E2E: Cross-Harness Agent Parity ==="
echo ""

# ---------------------------------------------------------------------------
# P1: front-door agents must exist on both harnesses
# ---------------------------------------------------------------------------
echo "--- P1: Front-door agent pairing ---"
check_pair() {
  # Args: claude_file copilot_file label
  if [ -f "$1" ] && [ -f "$2" ]; then
    pass "P1: $3 present on both harnesses"
  elif [ -f "$1" ]; then
    fail "P1: $3 exists for Claude ($1) but NOT for Copilot ($2)"
  elif [ -f "$2" ]; then
    fail "P1: $3 exists for Copilot ($2) but NOT for Claude ($1)"
  else
    fail "P1: $3 missing from BOTH harnesses"
  fi
}
check_pair "$CLAUDE_ROUTER" "$COPILOT_ROUTER" "lead/front-door agent"
check_pair "$CLAUDE_DIR/assert-iq-plan.md" "$COPILOT_DIR/Assert-IQ-PLAN.agent.md" "planning sibling"

echo ""

# ---------------------------------------------------------------------------
# P2: specialist subagent count must match
# ---------------------------------------------------------------------------
echo "--- P2: Specialist subagent parity ---"
claude_specialists=$(find "$CLAUDE_DIR/specialists" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
copilot_specialists=$(find "$COPILOT_DIR/specialists" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')

if [ "$claude_specialists" -eq "$copilot_specialists" ]; then
  pass "P2: specialist counts match ($claude_specialists each)"
else
  fail "P2: specialist count divergence — Claude has $claude_specialists, Copilot has $copilot_specialists"
  if [ "$claude_specialists" -gt 0 ] && [ "$copilot_specialists" -eq 0 ]; then
    echo "      Claude-only specialists:"
    find "$CLAUDE_DIR/specialists" -name '*.md' 2>/dev/null \
      | sed 's|.*/||; s|\.md$||' | sort | sed 's/^/        - /'
    echo "      => The v2.0 multi-agent orchestrator is Claude-only. Copilot"
    echo "         users get v1.x single-agent routing with no delegation."
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# P3: every shipped skill must be routable from BOTH routers
# ---------------------------------------------------------------------------
echo "--- P3: Skill-routing coverage ---"
skill_total=0
claude_missing=()
copilot_missing=()

# Extract the set of /slash-commands each router mentions with ONE grep per
# router, then test membership with `case`. Two greps per skill (60
# subprocesses) cost ~55s on Windows; and `[[ =~ ]]` with an interpolated
# pattern behaves inconsistently on bash 3.2 (macOS), so it is avoided here.
# The surrounding spaces make ' /check-merge ' an exact-token test, so
# /check-merge cannot satisfy a lookup for /check-merge-gate.
claude_routed=" $(grep -oE '/[a-z0-9][a-z0-9-]*' "$CLAUDE_ROUTER"  | sort -u | tr '\012' ' ')"
copilot_routed=" $(grep -oE '/[a-z0-9][a-z0-9-]*' "$COPILOT_ROUTER" | sort -u | tr '\012' ' ')"

for skill_dir in .github/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill="${skill_dir%/}"; skill="${skill##*/}"
  skill_total=$((skill_total + 1))
  case "$claude_routed"  in *" /$skill "*) ;; *) claude_missing[${#claude_missing[@]}]="$skill" ;; esac
  case "$copilot_routed" in *" /$skill "*) ;; *) copilot_missing[${#copilot_missing[@]}]="$skill" ;; esac
done

if [ ${#claude_missing[@]} -eq 0 ]; then
  pass "P3: Claude router covers all $skill_total skills"
else
  fail "P3: Claude router misses ${#claude_missing[@]}/$skill_total skills"
  printf '        - %s\n' "${claude_missing[@]}"
fi

if [ ${#copilot_missing[@]} -eq 0 ]; then
  pass "P3: Copilot router covers all $skill_total skills"
else
  fail "P3: Copilot router misses ${#copilot_missing[@]}/$skill_total skills"
  printf '        - %s\n' "${copilot_missing[@]}"
fi

echo ""

# ---------------------------------------------------------------------------
# P4: every instruction file must be reachable from each harness entry point
# ---------------------------------------------------------------------------
# Claude Code loads instruction files via @-references in CLAUDE.md.
# Copilot loads them via applyTo globs, but the agent/instructions entry point
# should still name them so the set stays discoverable and auditable.
echo "--- P4: Instruction-file reachability ---"
instr_orphaned=()
for instr in .github/instructions/*.md; do
  b=$(basename "$instr")
  in_claude=no
  in_copilot=no
  grep -qF "$b" CLAUDE.md && in_claude=yes
  { grep -qF "$b" .github/copilot-instructions.md || grep -qF "$b" "$COPILOT_ROUTER"; } && in_copilot=yes

  if [ "$in_claude" = yes ] && [ "$in_copilot" = yes ]; then
    continue
  fi
  instr_orphaned+=("$b (CLAUDE.md=$in_claude, copilot=$in_copilot)")
done

if [ ${#instr_orphaned[@]} -eq 0 ]; then
  pass "P4: all instruction files reachable from both harnesses"
else
  fail "P4: ${#instr_orphaned[@]} instruction file(s) not reachable from both harnesses"
  printf '        - %s\n' "${instr_orphaned[@]}"
fi

echo ""

# ---------------------------------------------------------------------------
# P5: generated Copilot specialists must be current w.r.t. their Claude sources
# ---------------------------------------------------------------------------
echo "--- P5: Generated specialist freshness ---"
if [ ! -f scripts/sync-agents.sh ]; then
  fail "P5: scripts/sync-agents.sh is missing (specialists cannot be generated)"
else
  if sync_out="$(bash scripts/sync-agents.sh --check 2>&1)"; then
    pass "P5: generated Copilot specialists are current"
  else
    fail "P5: generated Copilot specialists are STALE -- run: bash scripts/sync-agents.sh"
    echo "$sync_out" | sed 's/^/        /'
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# P6: the two sync implementations must agree on the tool-name mapping
# ---------------------------------------------------------------------------
# The pack ships .sh/.ps1 pairs because macOS boxes may lack PowerShell and
# Windows boxes may lack bash. If the two mapping tables drift, the generated
# agents differ depending on which OS ran the sync -- a silent per-platform bug.
#
# The bash table is read via its own --print-map (authoritative, no parsing).
# The PowerShell table is text-extracted so this check still runs on machines
# without pwsh; CR is stripped because PowerShell would emit CRLF.
echo "--- P6: sync-agents tool map agrees across implementations ---"
if [ ! -f scripts/sync-agents.ps1 ]; then
  fail "P6: scripts/sync-agents.ps1 is missing (no Windows-native sync)"
else
  sh_map="$(bash scripts/sync-agents.sh --print-map | tr -d '\r')"
  ps_map="$(grep -oE "'[A-Za-z]+' *= *'[^']*'" scripts/sync-agents.ps1 | tr -d " '" | tr -d '\r' | sort -u)"
  map_count="$(echo "$sh_map" | grep -c .)"
  if [ -z "$sh_map" ] || [ -z "$ps_map" ]; then
    fail "P6: could not extract a tool map from one or both implementations (sh=$map_count entries, ps=$(echo "$ps_map" | grep -c .))"
  elif [ "$sh_map" = "$ps_map" ]; then
    pass "P6: tool map identical in sync-agents.sh and sync-agents.ps1 ($map_count entries)"
  else
    fail "P6: tool map DIVERGES between sync-agents.sh and sync-agents.ps1"
    echo "        only in .sh:"
    comm -23 <(echo "$sh_map") <(echo "$ps_map") | sed 's/^/          /'
    echo "        only in .ps1:"
    comm -13 <(echo "$sh_map") <(echo "$ps_map") | sed 's/^/          /'
  fi
fi

echo ""
echo "=== Results: $PASSED PASS, $FAILED FAIL ==="

if [ $FAILED -eq 0 ]; then
  echo "✅ Harnesses are in parity."
  exit 0
fi

cat <<'EOF'

────────────────────────────────────────────────────────────────────────
AGENT PARITY DIVERGENCE — this failure is informational, not flaky.
Resolve by either:
  (a) bringing .github/agents up to parity (port the specialists and the
      missing skill routes to Copilot schema), or
  (b) making a deliberate product decision that the orchestrator is
      Claude-only, documenting it in CLAUDE.md + copilot-instructions.md,
      and narrowing this check to the dimensions you still consider binding.
Do NOT silence this check without recording which option was chosen.
────────────────────────────────────────────────────────────────────────
EOF

exit 1
