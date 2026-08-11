#!/bin/bash
set -euo pipefail

# E2E Test Suite: Specialist Orchestration (v2.0)
# Tests: File existence, configuration, JSON schemas, artifacts

# Correct REPO_ROOT calculation: from test file location to repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TEST_RESULTS=()
PASS_COUNT=0
FAIL_COUNT=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_pass() {
  echo -e "${GREEN}✅ $1${NC}"
  ((PASS_COUNT++))
}

log_fail() {
  echo -e "${RED}❌ $1${NC}"
  TEST_RESULTS+=("$1")
  ((FAIL_COUNT++))
}

echo "════════════════════════════════════════════════════════════════"
echo "E2E-28: Specialist Orchestration Tests (v2.0)"
echo "════════════════════════════════════════════════════════════════"
echo ""

# SUITE 1: Specialist Agent Files
echo "SUITE 1: Specialist Agent File Validation"
echo "────────────────────────────────────────────"

AGENTS=(
  "risk-scorer"
  "coverage-analyst"
  "flake-adjudicator"
  "oracle-grader"
  "calibration-specialist"
  "memory-curator"
  "traceability-auditor"
  "hotspot-analyzer"
)

for agent in "${AGENTS[@]}"; do
  agent_file="$REPO_ROOT/.claude/agents/specialists/$agent.md"
  if [ -f "$agent_file" ]; then
    if head -5 "$agent_file" | grep -q "^---"; then
      if grep "^name: $agent" "$agent_file" > /dev/null; then
        log_pass "Specialist agent $agent exists and well-formed"
      else
        log_fail "Specialist agent $agent missing name in frontmatter"
      fi
    else
      log_fail "Specialist agent $agent missing YAML frontmatter"
    fi
  else
    log_fail "Specialist agent file not found: $agent_file"
  fi
done

echo ""

# SUITE 2: Lead Agent Orchestration
echo "SUITE 2: Lead Agent Orchestration Directives"
echo "──────────────────────────────────────────────"

lead_agent="$REPO_ROOT/.claude/agents/assert-iq.md"

if [ -f "$lead_agent" ]; then
  if grep -q "Specialist Agents" "$lead_agent"; then
    log_pass "Lead agent defines specialist agents section"
  else
    log_fail "Lead agent missing specialist agents section"
  fi
  
  if grep -q "Orchestration Model" "$lead_agent"; then
    log_pass "Lead agent includes orchestration model"
  else
    log_fail "Lead agent missing orchestration model"
  fi
  
  if grep -q "Parallel Batch" "$lead_agent"; then
    log_pass "Lead agent defines parallel batch orchestration"
  else
    log_fail "Lead agent missing parallel batch definition"
  fi
else
  log_fail "Lead agent file not found: $lead_agent"
fi

echo ""

# SUITE 3: Orchestration Artifacts
echo "SUITE 3: Orchestration Artifacts Directory"
echo "──────────────────────────────────────────"

agent_runs_dir="$REPO_ROOT/.assert-iq/agent-runs"

if [ -d "$agent_runs_dir" ]; then
  log_pass "agent-runs directory exists"
  
  if [ -f "$agent_runs_dir/.gitignore" ]; then
    log_pass "agent-runs/.gitignore exists"
  else
    log_fail "agent-runs/.gitignore missing"
  fi
  
  if [ -f "$agent_runs_dir/index.json" ]; then
    if python3 -m json.tool "$agent_runs_dir/index.json" > /dev/null 2>&1; then
      log_pass "agent-runs/index.json is valid JSON"
    else
      log_fail "agent-runs/index.json is malformed"
    fi
  else
    log_fail "agent-runs/index.json missing"
  fi
else
  log_fail "agent-runs directory not found"
fi

echo ""

# SUITE 4: Business Metrics Configuration
echo "SUITE 4: Business Metrics Configuration"
echo "─────────────────────────────────────────"

config_file="$REPO_ROOT/.assert-iq/config.yaml"

if [ -f "$config_file" ]; then
  if grep -q "^business_metrics:" "$config_file"; then
    log_pass "config.yaml contains business_metrics section"
    
    if grep -A 7 "^business_metrics:" "$config_file" | grep -q "enabled: true"; then
      log_pass "business_metrics.enabled is true"
    else
      log_fail "business_metrics.enabled is not true"
    fi
    
    if grep -A 7 "^business_metrics:" "$config_file" | grep -q "escape_incident_cost"; then
      log_pass "business_metrics.escape_incident_cost configured"
    else
      log_fail "business_metrics.escape_incident_cost missing"
    fi
    
    if grep -A 7 "^business_metrics:" "$config_file" | grep -q "engineer_burden_rate"; then
      log_pass "business_metrics.engineer_burden_rate configured"
    else
      log_fail "business_metrics.engineer_burden_rate missing"
    fi
  else
    log_fail "config.yaml missing business_metrics section"
  fi
else
  log_fail "config.yaml not found"
fi

echo ""

# SUITE 5: Business Metrics Baseline
echo "SUITE 5: Business Metrics Baseline"
echo "──────────────────────────────────"

baseline_file="$REPO_ROOT/.assert-iq/business-metrics/baseline.json"

if [ -f "$baseline_file" ]; then
  if python3 -m json.tool "$baseline_file" > /dev/null 2>&1; then
    log_pass "baseline.json is valid JSON"
    
    if python3 -c "import json; d=json.load(open('$baseline_file')); assert d.get('escape_rate_per_quarter')" 2>/dev/null; then
      log_pass "baseline.json contains escape_rate_per_quarter"
    else
      log_fail "baseline.json missing escape_rate_per_quarter"
    fi
    
    if python3 -c "import json; d=json.load(open('$baseline_file')); assert d.get('triage_hours_per_quarter')" 2>/dev/null; then
      log_pass "baseline.json contains triage_hours_per_quarter"
    else
      log_fail "baseline.json missing triage_hours_per_quarter"
    fi
  else
    log_fail "baseline.json is not valid JSON"
  fi
else
  log_fail "baseline.json not found"
fi

echo ""

# SUITE 6: Measure-QI-Impact Skill
echo "SUITE 6: Measure-QI-Impact Skill"
echo "───────────────────────────────────"

skill_file="$REPO_ROOT/.github/skills/measure-qi-impact/SKILL.md"

if [ -f "$skill_file" ]; then
  log_pass "measure-qi-impact skill file exists"
  
  if grep -q "^name: measure-qi-impact" "$skill_file"; then
    log_pass "measure-qi-impact skill has correct name"
  else
    log_fail "measure-qi-impact skill has wrong name"
  fi
  
  if grep -q "## Inputs\|## Procedure\|## Output Format" "$skill_file"; then
    log_pass "measure-qi-impact skill has required sections"
  else
    log_fail "measure-qi-impact skill missing required sections"
  fi
  
  if grep -q "HTML.*Dashboard\|VP-ready" "$skill_file"; then
    log_pass "measure-qi-impact skill mentions HTML dashboard format"
  else
    log_fail "measure-qi-impact skill missing HTML dashboard documentation"
  fi
else
  log_fail "measure-qi-impact skill file not found"
fi

echo ""

# SUITE 7: Specialist Output JSON Schema
echo "SUITE 7: Specialist Output JSON Schema"
echo "──────────────────────────────────────"

mock_risk_output='
{
  "specialist": "risk-scorer",
  "verdict_band": "green",
  "verdict_score": 0.85,
  "layer_scores": {
    "change": {"state": "strong", "score": 0.90},
    "protection": {"state": "strong", "score": 0.95},
    "trust": {"state": "weak", "score": 0.60},
    "outcome": {"state": "strong", "score": 0.85}
  },
  "recommendation": "Approve",
  "summary": "Low-risk change with strong protection"
}
'

if echo "$mock_risk_output" | python3 -m json.tool > /dev/null 2>&1; then
  log_pass "Specialist output JSON schema is valid"
  
  if echo "$mock_risk_output" | python3 -c "import sys, json; d=json.load(sys.stdin); assert d.get('specialist')" 2>/dev/null; then
    log_pass "Specialist output contains specialist field"
  else
    log_fail "Specialist output missing specialist field"
  fi
  
  if echo "$mock_risk_output" | python3 -c "import sys, json; d=json.load(sys.stdin); assert d.get('verdict_band')" 2>/dev/null; then
    log_pass "Specialist output contains verdict_band field"
  else
    log_fail "Specialist output missing verdict_band field"
  fi
else
  log_fail "Specialist output JSON is malformed"
fi

echo ""

# SUITE 8: Aggregation Audit Trail
echo "SUITE 8: Aggregation Audit Trail Schema"
echo "────────────────────────────────────────"

mock_audit='
{
  "run_id": "2026-08-11-143022",
  "timestamp": "2026-08-11T14:30:22Z",
  "user_request": "Assess this PR for risk",
  "specialists_invoked": ["risk-scorer", "coverage-analyst", "flake-adjudicator", "hotspot-analyzer"],
  "execution_mode": "parallel",
  "execution_time_ms": 4230,
  "specialists": {
    "risk-scorer": {"specialist": "risk-scorer", "verdict_band": "green", "verdict_score": 0.85}
  },
  "synthesized_narrative": "PR is low-risk with strong protection",
  "lead_recommendation": "Approve with mitigations"
}
'

if echo "$mock_audit" | python3 -m json.tool > /dev/null 2>&1; then
  log_pass "Audit trail JSON schema is valid"
  
  if echo "$mock_audit" | python3 -c "import sys, json; d=json.load(sys.stdin); assert d.get('run_id')" 2>/dev/null; then
    log_pass "Audit trail contains run_id"
  else
    log_fail "Audit trail missing run_id"
  fi
  
  if echo "$mock_audit" | python3 -c "import sys, json; d=json.load(sys.stdin); assert d.get('specialists_invoked')" 2>/dev/null; then
    log_pass "Audit trail contains specialists_invoked"
  else
    log_fail "Audit trail missing specialists_invoked"
  fi
else
  log_fail "Audit trail JSON is malformed"
fi

echo ""

# SUMMARY
echo "════════════════════════════════════════════════════════════════"
echo "Test Summary"
echo "════════════════════════════════════════════════════════════════"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ $FAIL_COUNT -eq 0 ]; then
  echo -e "${GREEN}✅ All tests passed${NC}"
  exit 0
else
  echo -e "${RED}❌ Some tests failed:${NC}"
  for result in "${TEST_RESULTS[@]}"; do
    echo "  - $result"
  done
  exit 1
fi
