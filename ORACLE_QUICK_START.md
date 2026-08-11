# Oracle Layer — Quick Start (5 Steps)

**Version:** 1.6.0+  
**What this is:** Independent quality verification via rubric-based grading. Author what "done" looks like → grade independently → make confident merge/release decisions.

---

## 5-Step Workflow

### 1. Author a Rubric

Define quality criteria with `/define-quality-rubric`.

```
You: "/define-quality-rubric"

Skill guides you through:
  - Artifact type? (test, bug_report, plan, etc.)
  - What's painful now? (e.g., "Our unit tests have weak assertions")
  - Define dimensions (independently scoreable criteria)
  - Name, criterion, weight, levels (PASS/CONDITIONAL/FAIL)
  - Validate & version (e.g., test-unit-v1.0)
```

**Output:** `.assert-iq/oracles/rubrics/<rubric_id>.json`  
**Committed:** Yes (rubric is a spec, git-safe)

**Example Dimension:**
```
Assertion Clarity
  Criterion: "Each assertion documents what is being verified"
  Weight: 1.0 (critical)
  
  PASS: "All assertions have inline messages"
  CONDITIONAL: "70%+ have messages"
  FAIL: "Bare assertions with no context"
```

---

### 2. Grade an Artifact

Evaluate code/tests/reports against the rubric using `/grade-with-rubric`.

```
You: "/grade-with-rubric tests/unit/login.test.ts test-unit-v1.0"

Skill:
  [1] Reads artifact (42 lines)
  [2] Loads rubric (4 dimensions)
  [3] Spawns isolated grader agent
  [4] Grades each dimension independently
  
  Verdict: CONDITIONAL (0.92 / 1.0)
  
  ✓ PASS: independence, determinism
  ⚠ CONDITIONAL: assertion clarity (line 25 bare assert)
  
  Saved to: .assert-iq/oracles/outcomes/login.test.ts/latest.json
```

**Modes:**
- **Manual** — Interactive feedback, one artifact
- **Async (CI)** — Grade in pipeline, post verdicts to PR
- **Batch** — Preview all tests against new rubric before adoption

---

### 3. View Verdict

Verdict is stored locally in `.assert-iq/oracles/outcomes/`:

```
.assert-iq/oracles/outcomes/
  └─ login.test.ts/
     ├─ latest.json          # Most recent verdict
     └─ history.jsonl        # Full lineage (append-only)
```

**Latest Verdict Structure:**
```json
{
  "rubric_id": "test-unit-v1.0",
  "artifact_id": "tests/unit/login.test.ts",
  "verdict": "CONDITIONAL",
  "score": 0.92,
  "dimensions": [
    {
      "id": "assertion_clarity",
      "name": "Assertion clarity",
      "verdict": "CONDITIONAL",
      "score": 0.67,
      "evidence": "Lines 10–22 have messages. Line 25 is bare assert() → 67%"
    }
  ],
  "summary": "Test structure solid. Add message to line 25.",
  "recommended_action": "Fix artifact"
}
```

---

### 4. Integrate with Merge/Release Gates (Optional)

Oracle verdicts feed into the **Outcome layer** of QI decisions:

**In `/check-merge`:**
- Looks for oracle verdicts on touched tests
- FAIL verdicts → amber (discuss) or block (maturity-dependent)

**In `/release-confidence`:**
- Aggregates oracle verdicts on test suite
- Outcome layer score reflects grading results
- Verdict: GO / GO-WITH-MITIGATION / HOLD

**Maturity Weighting:**
```yaml
early:   0%   (oracle is advisory only; never blocks)
mid:     20%  (oracle is co-informational)
higher:  50%  (oracle is co-decisive; can block merge)
```

Configure in `.assert-iq/config.yaml > oracle.maturity_gating`.

---

### 5. Iterate

**Artifact needs work?**
- Fix the issue (e.g., add assert message on line 25)
- Re-run `/grade-with-rubric` with same rubric
- Compare history: artifact v1 → v2 shows progress

**Rubric needs refinement?**
- Don't edit the existing rubric (immutable)
- Create a new version (e.g., `test-unit-v1.1`)
- Batch-grade with new version to see impact
- Adopt v1.1 if better; keep v1.0 in git history

**Example progression:**
```
login.test.ts artifact v1 + test-unit-v1.0 = CONDITIONAL (0.92)
  → Fix line 25
login.test.ts artifact v2 + test-unit-v1.0 = PASS (1.0)
  → But find new issue: missing test for error case
login.test.ts artifact v2 + test-unit-v1.1 (new dimension: error-path coverage)
  = CONDITIONAL (0.80)
  → Add error test
login.test.ts artifact v3 + test-unit-v1.1 = PASS (1.0)
```

---

## Key Concepts

**Rubric authorship ≠ test generation**
- Rubrics are pre-authored specs (dimensions, levels, passing criteria)
- Grading is independent (grader has no access to generator reasoning)
- This isolation is the defensible differentiator

**Immutable rubrics, versioned evolution**
- Once created, a rubric (e.g., `test-unit-v1.0`) never changes
- Refinements become new versions (v1.1, v2.0)
- Full lineage preserved in git

**Evidence-driven verdicts**
- Every verdict cites specific evidence (line numbers, patterns)
- Why this level? What would change it?
- Never subjective or fabricated

**Maturity-gated**
- Early: rubric authoring + advisory grading
- Mid: optional CI grading, optional gates
- Higher: auto-grade in CI, can block merges

---

## Config: Activation & Customization

**Enable oracle layer:**
```yaml
oracle:
  enabled: true
  grader:
    model: "claude-3-5-sonnet"
    timeout_seconds: 60
  defaults_by_artifact_type:
    test: "test-unit-v1.0"
    test_integration: "test-integration-v1.0"
    bug_report: "bug-report-v1.0"
    plan: "plan-v1.0"
  verdict_sink: "local"  # or "github", "ado", "jira", "none"
  maturity_gating:
    early:   { oracle_weight: 0.0, mode: "advisory_only" }
    mid:     { oracle_weight: 0.2, mode: "optional_gate" }
    higher:  { oracle_weight: 0.5, mode: "can_block_merge" }
```

---

## Troubleshooting

**Q: Verdicts aren't being saved**  
A: Check `.assert-iq/oracles/outcomes/` exists. If not, run `/assert-iq-bootstrap` to scaffold.

**Q: Can't remember the rubric ID**  
A: List available rubrics: `ls .assert-iq/oracles/rubrics/`

**Q: Want to change a rubric that's already in use**  
A: Don't edit it. Create a new version (v1.1, v2.0). Old version stays in history.

**Q: Oracle verdict FAIL but I disagree**  
A: Refine the rubric (new version) or file a GitHub issue (oracle grader may need tuning).

**Q: How do I post verdicts to my tracker?**  
A: Set `.assert-iq/config.yaml > oracle.verdict_sink: "github"` (or ado, jira). Then re-grade.

---

## Further Reading

- **Full guide:** `oracles-readme.html`
- **Rubric authoring:** `/define-quality-rubric` skill
- **Grading:** `/grade-with-rubric` skill
- **Grader agent:** `.claude/agents/grader.md`
- **Registry:** `.assert-iq/oracles/README.md`
- **Config:** `.assert-iq/config.yaml > oracle:`
- **Governance:** `.github/instructions/qi-oracle.instructions.md`

