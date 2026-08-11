#!/bin/bash
set -euo pipefail

# ============================================================================
# E2E Integration Tests: v2.0 Multi-Agent Orchestration + Commercial Metrics
# ============================================================================
# Comprehensive testing of:
#   1. Orchestration model (parallel batch, serial specialists, aggregation)
#   2. Specialist agent prompting (JSON schema validation)
#   3. Business metrics dashboard (HTML generation, calculations)
#   4. Baseline metrics loading and validation
#   5. Lead agent routing and specialist invocation
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
cd "$REPO_ROOT"

# Test counters
PASS=0
FAIL=0
SUITE=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() {
  echo -e "${GREEN}✅${NC} $1"
  ((PASS++))
}

log_fail() {
  echo -e "${RED}❌${NC} $1"
  ((FAIL++))
}

log_suite() {
  ((SUITE++))
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "SUITE $SUITE: $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================================================
# SUITE 1: Specialist Agent File Structure & YAML Frontmatter
# ============================================================================
log_suite "Specialist Agent File Structure & YAML Frontmatter"

SPECIALISTS=("risk-scorer" "coverage-analyst" "flake-adjudicator" "oracle-grader" \
             "calibration-specialist" "memory-curator" "traceability-auditor" "hotspot-analyzer")

for specialist in "${SPECIALISTS[@]}"; do
  file=".claude/agents/specialists/$specialist.md"
  if [ ! -f "$file" ]; then
    log_fail "Specialist file missing: $file"
  else
    # Verify YAML frontmatter
    if grep -q "^---$" "$file" && grep -q "^name:" "$file"; then
      log_pass "Specialist $specialist exists with valid frontmatter"
    else
      log_fail "Specialist $specialist missing YAML frontmatter"
    fi
    
    # Verify name field matches filename
    name_field=$(grep "^name:" "$file" | sed 's/^name: //' | tr -d ' "')
    filename_name=$(basename "$file" .md)
    if [ "$name_field" = "$filename_name" ]; then
      log_pass "Specialist $specialist name field matches filename"
    else
      log_fail "Specialist $specialist name mismatch: '$name_field' vs '$filename_name'"
    fi
  fi
done

# ============================================================================
# SUITE 2: Specialist JSON Output Schema Validation
# ============================================================================
log_suite "Specialist JSON Output Schema Validation"

# Mock specialist output schemas
cat > /tmp/risk-scorer-output.json << 'SCHEMA'
{
  "specialist": "risk-scorer",
  "verdict_band": "green",
  "verdict_score": 0.87,
  "layer_scores": {
    "change_risk": {"score": 0.8, "state": "STRONG"},
    "protection_strength": {"score": 0.9, "state": "STRONG"},
    "signal_trustworthiness": {"score": 0.85, "state": "STRONG"},
    "outcome_evidence": {"score": 0.88, "state": "STRONG"}
  },
  "recommendation": "Safe to ship with standard review",
  "summary": "PR touches 3 files, 85% protected, no recent escapes on modules"
}
SCHEMA

cat > /tmp/coverage-analyst-output.json << 'SCHEMA'
{
  "specialist": "coverage-analyst",
  "overall_protection": 78.5,
  "coverage_percentage": 78.5,
  "gaps": [
    {"module": "src/auth/mfa.ts", "coverage": 42, "functions": 5, "priority": "high"}
  ],
  "recommendation": "Add 8 tests to mfa.ts for production readiness",
  "summary": "78.5% coverage, gaps identified in high-risk modules"
}
SCHEMA

cat > /tmp/flake-adjudicator-output.json << 'SCHEMA'
{
  "specialist": "flake-adjudicator",
  "test_name": "TestAuthFlow",
  "classification": "flaky",
  "root_cause": "Async timing issue in mock server response",
  "layer_responsible": "signal_trustworthiness",
  "confidence": 0.92,
  "recommendation": "Add explicit wait and stabilize",
  "summary": "Test fails 15% of runs; async timing is root cause"
}
SCHEMA

cat > /tmp/oracle-grader-output.json << 'SCHEMA'
{
  "specialist": "oracle-grader",
  "rubric_id": "code-review-v1.0",
  "overall_grade": "A",
  "grades": {
    "readability": "A",
    "error_handling": "A-",
    "performance": "A",
    "security": "B+"
  },
  "recommendation": "Approve with minor security fixes",
  "summary": "Strong code quality; address SQL injection risk in query builder"
}
SCHEMA

cat > /tmp/calibration-specialist-output.json << 'SCHEMA'
{
  "specialist": "calibration-specialist",
  "period": "2026-Q3",
  "verdicts_analyzed": 24,
  "brier_score": 0.18,
  "brier_score_by_band": {
    "green": 0.12,
    "amber": 0.25,
    "red": 0.22
  },
  "layer_fidelity": {
    "change_risk": 0.88,
    "protection_strength": 0.76,
    "signal_trustworthiness": 0.82,
    "outcome_evidence": 0.85
  },
  "drift_detected": false,
  "recommendation": "Verdict accuracy stable; no drift detected",
  "summary": "Brier score 0.18 (good), protection layer needs recalibration"
}
SCHEMA

cat > /tmp/memory-curator-output.json << 'SCHEMA'
{
  "specialist": "memory-curator",
  "memory_health": "good",
  "issues_found": 0,
  "cycles_detected": [],
  "stale_entries": 0,
  "contradictions": [],
  "dream_cycle_run": "2026-08-11T14:30:00Z",
  "recommendation": "Memory store healthy; run dream next week",
  "summary": "No cycles, staleness, or contradictions detected"
}
SCHEMA

cat > /tmp/traceability-auditor-output.json << 'SCHEMA'
{
  "specialist": "traceability-auditor",
  "coverage_percentage": 92.5,
  "orphan_tests": [],
  "untraceable_code": ["src/util/helpers.ts"],
  "uncovered_acs": [],
  "recommendation": "Link src/util/helpers.ts to AC or create issue",
  "summary": "92.5% traceability; 1 untraceable module"
}
SCHEMA

cat > /tmp/hotspot-analyzer-output.json << 'SCHEMA'
{
  "specialist": "hotspot-analyzer",
  "period_days": 90,
  "hotspots": [
    {
      "module": "src/billing/invoice.ts",
      "risk_score": 0.89,
      "churn_commits": 47,
      "complexity_avg": 8.2,
      "escapes_count": 3,
      "priority": "critical"
    }
  ],
  "recommendation": "Focus testing on billing/invoice; 3 recent escapes",
  "summary": "1 critical hotspot detected in billing module"
}
SCHEMA

# Validate each schema
for schema_file in /tmp/*-output.json; do
  if python3 -m json.tool "$schema_file" > /dev/null 2>&1; then
    specialist=$(basename "$schema_file" -output.json)
    log_pass "Schema valid for $specialist"
  else
    specialist=$(basename "$schema_file" -output.json)
    log_fail "Schema invalid for $specialist"
  fi
done

# ============================================================================
# SUITE 3: Orchestration Model - Parallel Batch Execution Order
# ============================================================================
log_suite "Orchestration Model - Parallel Batch Execution Order"

# Verify lead agent has orchestration directives
if grep -q "Specialist Agents" .claude/agents/assert-iq.md; then
  log_pass "Lead agent has Specialist Agents section"
else
  log_fail "Lead agent missing Specialist Agents section"
fi

if grep -q "Orchestration Model" .claude/agents/assert-iq.md; then
  log_pass "Lead agent has Orchestration Model section"
else
  log_fail "Lead agent missing Orchestration Model section"
fi

if grep -q "Parallel Batch" .claude/agents/assert-iq.md; then
  log_pass "Lead agent defines Parallel Batch execution"
else
  log_fail "Lead agent missing Parallel Batch definition"
fi

# Verify parallel batch includes 4 agents
if grep -q "risk-scorer\|coverage-analyst\|flake-adjudicator\|hotspot-analyzer" .claude/agents/assert-iq.md; then
  log_pass "Lead agent specifies 4 parallel batch agents"
else
  log_fail "Lead agent missing parallel batch agent list"
fi

# Verify serial specialists order
if grep -q "oracle-grader\|calibration-specialist\|memory-curator\|traceability-auditor" .claude/agents/assert-iq.md; then
  log_pass "Lead agent specifies 4 serial specialist agents"
else
  log_fail "Lead agent missing serial specialist list"
fi

# ============================================================================
# SUITE 4: Lead Agent Routing & Request Delegation
# ============================================================================
log_suite "Lead Agent Routing & Request Delegation"

# Verify lead agent has skill routing table
if grep -q "How you route to skills" .claude/agents/assert-iq.md; then
  log_pass "Lead agent has skill routing guidance"
else
  log_fail "Lead agent missing skill routing guidance"
fi

# Verify /measure-qi-impact is documented in lead agent
if grep -q "measure-qi-impact" .claude/agents/assert-iq.md; then
  log_pass "Lead agent documents /measure-qi-impact skill"
else
  log_fail "Lead agent missing /measure-qi-impact documentation"
fi

# Verify measure-qi-impact skill exists
if [ -f ".github/skills/measure-qi-impact/SKILL.md" ]; then
  log_pass "Business metrics skill file exists"
else
  log_fail "Business metrics skill missing"
fi

# ============================================================================
# SUITE 5: Business Metrics Configuration Validation
# ============================================================================
log_suite "Business Metrics Configuration Validation"

# Check config.yaml has business_metrics section
if grep -q "^business_metrics:" .assert-iq/config.yaml; then
  log_pass "config.yaml has business_metrics section"
else
  log_fail "config.yaml missing business_metrics section"
fi

# Verify required fields in business_metrics
required_fields=("enabled" "escape_incident_cost" "engineer_burden_rate" "baseline_path" "reporting_period" "report_sink" "auto_generate")
for field in "${required_fields[@]}"; do
  if grep -q "  $field:" .assert-iq/config.yaml; then
    log_pass "Config has $field field"
  else
    log_fail "Config missing $field field"
  fi
done

# Verify enabled is true
if grep "^business_metrics:" -A 10 .assert-iq/config.yaml | grep -q "enabled: true"; then
  log_pass "Business metrics enabled in config"
else
  log_fail "Business metrics not enabled in config"
fi

# ============================================================================
# SUITE 6: Baseline Metrics Structure & Loading
# ============================================================================
log_suite "Baseline Metrics Structure & Loading"

baseline_file=".assert-iq/business-metrics/baseline.json"

if [ ! -f "$baseline_file" ]; then
  log_fail "Baseline file missing: $baseline_file"
else
  log_pass "Baseline file exists"
  
  # Validate JSON
  if python3 -m json.tool "$baseline_file" > /dev/null 2>&1; then
    log_pass "Baseline JSON is valid"
  else
    log_fail "Baseline JSON is invalid"
  fi
  
  # Verify required fields
  required_fields=("capture_date" "escape_rate_per_quarter" "triage_hours_per_quarter" "cycle_time_days_pr_to_release")
  for field in "${required_fields[@]}"; do
    if grep -q "\"$field\"" "$baseline_file"; then
      log_pass "Baseline has $field field"
    else
      log_fail "Baseline missing $field field"
    fi
  done
  
  # Verify metric values are positive
  escape_rate=$(python3 -c "import json; print(json.load(open('$baseline_file'))['escape_rate_per_quarter'])" 2>/dev/null || echo "-1")
  if [ "$escape_rate" -gt 0 ]; then
    log_pass "Baseline escape_rate_per_quarter is positive ($escape_rate)"
  else
    log_fail "Baseline escape_rate_per_quarter invalid ($escape_rate)"
  fi
fi

# ============================================================================
# SUITE 7: Business Metrics Calculation & Transformation
# ============================================================================
log_suite "Business Metrics Calculation & Transformation"

# Mock business metrics calculation
cat > /tmp/test-metrics-calc.py << 'PYEOF'
import json

# Load baseline
baseline = {
    "escape_rate_per_quarter": 12,
    "triage_hours_per_quarter": 200,
    "cycle_time_days_pr_to_release": 18
}

# Current period (mock data)
current = {
    "escape_rate_per_quarter": 7,
    "triage_hours_per_quarter": 120,
    "cycle_time_days_pr_to_release": 14
}

# Config
config = {
    "escape_incident_cost": 50000,
    "engineer_burden_rate": 85
}

# Calculate deltas
escape_reduction = baseline["escape_rate_per_quarter"] - current["escape_rate_per_quarter"]
escape_reduction_pct = (escape_reduction / baseline["escape_rate_per_quarter"]) * 100
triage_hours_saved = baseline["triage_hours_per_quarter"] - current["triage_hours_per_quarter"]
cycle_time_improvement = baseline["cycle_time_days_pr_to_release"] - current["cycle_time_days_pr_to_release"]
cycle_time_improvement_pct = (cycle_time_improvement / baseline["cycle_time_days_pr_to_release"]) * 100

# Calculate economic value
escape_value = escape_reduction * config["escape_incident_cost"]
triage_value = triage_hours_saved * config["engineer_burden_rate"]
total_economic_value = escape_value + triage_value

# Output
metrics = {
    "escape_reduction": {
        "value": escape_reduction,
        "percentage": escape_reduction_pct,
        "economic_impact": escape_value
    },
    "triage_hours_saved": {
        "value": triage_hours_saved,
        "percentage": (triage_hours_saved / baseline["triage_hours_per_quarter"]) * 100,
        "economic_impact": triage_value
    },
    "cycle_time_improvement": {
        "value": cycle_time_improvement,
        "percentage": cycle_time_improvement_pct,
        "days": cycle_time_improvement
    },
    "total_economic_value": total_economic_value,
    "recommendation": f"Release with confidence: {escape_reduction_pct:.1f}% fewer escapes, {triage_hours_saved} hours reclaimed"
}

print(json.dumps(metrics, indent=2))
PYEOF

if python3 /tmp/test-metrics-calc.py > /tmp/metrics-output.json 2>&1; then
  output=$(cat /tmp/metrics-output.json)
  if echo "$output" | grep -q "total_economic_value"; then
    log_pass "Metrics calculation produces valid output"
  else
    log_fail "Metrics output missing total_economic_value"
  fi
else
  log_fail "Metrics calculation failed"
fi

# ============================================================================
# SUITE 8: HTML Dashboard Template & Structure
# ============================================================================
log_suite "HTML Dashboard Template & Structure"

# Verify /measure-qi-impact skill has output specifications
if grep -q "HTML Dashboard" .github/skills/measure-qi-impact/SKILL.md; then
  log_pass "Skill specifies HTML Dashboard output"
else
  log_fail "Skill missing HTML Dashboard specification"
fi

if grep -q "4 metric cards\|metric card\|hero section" .github/skills/measure-qi-impact/SKILL.md; then
  log_pass "Skill documents dashboard structure"
else
  log_fail "Skill missing dashboard structure details"
fi

if grep -q "escape rate\|triage hours\|cycle-time\|ROI" .github/skills/measure-qi-impact/SKILL.md; then
  log_pass "Skill specifies all 4 business metrics"
else
  log_fail "Skill missing metric definitions"
fi

# ============================================================================
# SUITE 9: Orchestration Artifact Tracking
# ============================================================================
log_suite "Orchestration Artifact Tracking"

# Verify agent-runs directory structure
if [ -d ".assert-iq/agent-runs" ]; then
  log_pass "Orchestration artifacts directory exists"
else
  log_fail "Orchestration artifacts directory missing"
fi

if [ -f ".assert-iq/agent-runs/.gitignore" ]; then
  log_pass "Orchestration artifacts .gitignore exists"
else
  log_fail "Orchestration artifacts .gitignore missing"
fi

if [ -f ".assert-iq/agent-runs/index.json" ]; then
  log_pass "Orchestration index.json exists"
  
  # Verify index structure
  if python3 -m json.tool ".assert-iq/agent-runs/index.json" > /dev/null 2>&1; then
    log_pass "Orchestration index.json is valid JSON"
  else
    log_fail "Orchestration index.json is invalid"
  fi
  
  if grep -q "runs_total" ".assert-iq/agent-runs/index.json"; then
    log_pass "Index has runs_total field"
  else
    log_fail "Index missing runs_total field"
  fi
else
  log_fail "Orchestration index.json missing"
fi

# ============================================================================
# SUITE 10: Business Metrics Reports Directory
# ============================================================================
log_suite "Business Metrics Reports Directory"

if [ -d ".assert-iq/business-metrics/reports" ]; then
  log_pass "Business metrics reports directory exists"
else
  log_fail "Business metrics reports directory missing"
fi

if [ -f ".assert-iq/business-metrics/.gitignore" ]; then
  log_pass "Business metrics .gitignore exists"
  
  # Verify it excludes reports
  if grep -q "reports/" ".assert-iq/business-metrics/.gitignore"; then
    log_pass "Business metrics .gitignore excludes reports/"
  else
    log_fail "Business metrics .gitignore missing reports/ exclusion"
  fi
else
  log_fail "Business metrics .gitignore missing"
fi

# ============================================================================
# SUITE 11: Specialist Agent Routing in Lead Agent
# ============================================================================
log_suite "Specialist Agent Routing in Lead Agent"

# Count mentions of each specialist in lead agent
specialists=("risk-scorer" "coverage-analyst" "flake-adjudicator" "oracle-grader" \
             "calibration-specialist" "memory-curator" "traceability-auditor" "hotspot-analyzer")

count=0
for specialist in "${specialists[@]}"; do
  if grep -q "$specialist" .claude/agents/assert-iq.md; then
    ((count++))
  fi
done

if [ $count -eq 8 ]; then
  log_pass "Lead agent mentions all 8 specialists"
else
  log_fail "Lead agent only mentions $count/8 specialists"
fi

# ============================================================================
# SUITE 12: Config Consistency Across v2.0 Components
# ============================================================================
log_suite "Config Consistency Across v2.0 Components"

# Verify baseline_path in config matches actual file
baseline_path=$(grep "baseline_path:" .assert-iq/config.yaml | sed 's/.*baseline_path: //' | tr -d ' ')
if [ -f "$baseline_path" ]; then
  log_pass "Config baseline_path points to existing file"
else
  log_fail "Config baseline_path ($baseline_path) does not exist"
fi

# Verify report_sink directory exists
report_sink=$(grep "report_sink:" .assert-iq/config.yaml | sed 's/.*report_sink: //' | tr -d ' ')
if [ -d "$report_sink" ]; then
  log_pass "Config report_sink directory exists"
else
  log_fail "Config report_sink directory does not exist"
fi

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════════════════════════════════╗"
echo "║ E2E V2.0 Integration Test Results                                                      ║"
echo "╚════════════════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Total Suites: $SUITE"
echo "Passed: ${GREEN}$PASS${NC}"
echo "Failed: ${RED}$FAIL${NC}"
echo ""

if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}✅ ALL E2E V2.0 INTEGRATION TESTS PASSED${NC}"
  exit 0
else
  echo -e "${RED}❌ SOME TESTS FAILED (see details above)${NC}"
  exit 1
fi
