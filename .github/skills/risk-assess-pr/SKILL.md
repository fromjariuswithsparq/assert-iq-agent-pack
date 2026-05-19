name: risk-assess-pr
description: "Score a pull request across the QI four-layer signal model and post a structured risk comment."
---

# PR risk assessment

Compute a four-layer QI score for the current PR and produce a comment that
delivery leaders can act on.

---

## Before you start: verify PR context

You need access to the PR changes before running the assessment. Check in this order:

1. **MCP server** — use it if available to inspect the PR diff and file list
2. **Git diff** — inspect the working tree or staged changes directly
3. **User-provided description** — if neither is available, ask: "I need the list of changed files and a brief description of what the PR does before I can run the assessment."

Do not attempt the assessment without knowing what changed.

---

## Layer states

Each of the four layers must be assessed as one of:

| State | Meaning | Verdict impact |
|-------|---------|---------------|
| **STRONG** | Layer signal is positive — coverage adequate, flakes low, no recent escapes | Supports GREEN |
| **WEAK** | Layer signal is negative — gaps present, risk factor identified | Pushes toward AMBER or RED |
| **UNGRADED** | Data is unavailable — source broken, no history exists, tooling not configured | Blocks GREEN; treat as uncertainty, not safety |

> **Integrity rule:** A verdict may only be GREEN if all four layers are STRONG. If any layer is UNGRADED, the maximum verdict is AMBER with explicit notation of what data is missing. Never assign GREEN to an ungraded layer because no negative signal was found — absence of data is not evidence of safety.

> **Layer skipping vs. UNGRADED:**
> - *Skipping* (low-complexity quick assessment) = all layers are STRONG by inspection and you state them briefly
> - *UNGRADED* = the data source is broken, no history exists, or tooling is not configured — you cannot assess regardless of complexity
> These are different. A low-complexity PR with a broken defect tracker has a STRONG Change layer and UNGRADED Outcome layer — it cannot be GREEN.

---

## Complexity calibration

| Class | Criteria | Assessment mode |
|-------|----------|----------------|
| **Low** | ≤ 50 lines, single file or tightly-scoped single service, no shared/infrastructure touches, no late changes | **Quick**: all 4 layers, each resolved by inspection if trivially STRONG |
| **Medium** | 51–500 lines, up to 2 services, no late changes | **Standard**: all 4 layers, full procedure |
| **High** | > 500 lines, cross-service, shared infrastructure, any late-breaking change | **Thorough**: all 4 layers, note blast radius, flag each weakness explicitly |

**Early exit for obvious-STRONG cases:** If after Steps 1–2 both Change and Protection are STRONG, and the PR is Low or Medium complexity, you may spot-check Steps 3–4 (rather than doing exhaustive analysis) and confirm STRONG or note any exception found. Still state each layer in the comment — "STRONG (confirmed by inspection)" is valid.

---

## Procedure

### Step 1 — Change layer

List and characterize:
- Files changed, lines added/removed
- Services, modules, or shared dependencies touched
- Late-breaking changes (not in original scope, discovered late)
- Blast radius: other services importing or depending on anything changed

**Weakness thresholds:**
| Factor | STRONG | WEAK |
|--------|--------|------|
| Scope | Single service or well-bounded | Cross-service or shared infrastructure |
| Churn | < 200 lines, delete ratio < 40% | ≥ 200 lines, or delete ratio ≥ 40% |
| Late changes | None | Material late-breaking discovery |
| Blast radius | Contained | Reaches ≥ 2 unrelated services |

**Late-change materiality:**
| Late change type | Materiality | Verdict effect |
|-----------------|-------------|----------------|
| Comment/doc/formatting/minor rename | **Low** — cosmetic | Note; no escalation |
| Logic change, new method, new dependency | **High** — behavior change | Minimum AMBER |
| Shared config, shared library, infrastructure | **Critical** — blast radius beyond this PR | Minimum AMBER; list all downstream services |

### Step 2 — Protection layer

**How to find tests (in order of reliability):**
1. `qi-traceability.instructions.md` traces if configured
2. Test files matching: `*Test*.*, *Tests.*, *Spec.*, *_test.*` co-located with changed files
3. Files in directories: `test/`, `tests/`, `__tests__/`, `spec/`
4. Search for imports/references to the changed class or function in test directories
5. If nothing found: Protection is WEAK (new uncovered code) or UNGRADED (cannot determine)

**Report at function/method level:** Name each changed function/method as covered or NOT covered.

**Coverage delta:**
- *Net positive*: more tests now than before (new tests > deleted tests, and new code is covered)
- *Net negative*: fewer tests than before, or new code added without new tests
- *Neutral*: test count stable, no new gaps, no new coverage

**Weakness thresholds:**
| Factor | STRONG | WEAK |
|--------|--------|------|
| Function coverage | All changed functions/methods have tests | Any changed function/method uncovered |
| Coverage delta | Net positive or neutral | Net negative |
| New service | Coverage plan in PR (even partial) | No tests for new code |

If no tests located by any method: "Protection: UNGRADED — test files not located."

### Step 3 — Trust layer

Flake and block history for impacted test paths (CI system, test dashboard, MCP server).

**Thresholds:** Flake rate < 5% → STRONG; ≥ 5% on any suite → WEAK. Blocked test in last 14 days → WEAK. New service → UNGRADED.

If CI data unavailable: "Trust: UNGRADED — flake/block history not accessible."

### Step 4 — Outcome layer

Escaped defects on touched components, last 30 days (ADO, GitHub Issues, Jira, or configured tracker).

**Thresholds:** 0 escapes, stable trend → STRONG. ≥ 1 escape in last 30 days → WEAK. New component → UNGRADED.

If tracker unavailable: "Outcome: UNGRADED — defect history not accessible."

### Step 5 — Decision

| Condition | Band |
|-----------|------|
| All four layers STRONG | **GREEN** |
| ≥ 1 layer WEAK, rest STRONG or UNGRADED | **AMBER** |
| ≥ 2 layers WEAK, or Change WEAK + any other WEAK/UNGRADED | **RED** |
| Any high- or critical-materiality late-breaking change | Minimum **AMBER** |

### Step 6 — Post comment

---

## Comment template

```
## QI Risk Assessment — [GREEN | AMBER | RED]

**Change**: [Files and services. Lines added/removed. Delete ratio if notable.
            Late changes with materiality. Blast radius if cross-service.]

**Protection**: [Each changed function/method: covered or NOT covered.
                Coverage delta (net positive/negative/neutral). UNGRADED if applicable.]

**Trust**: [Flake rate with date range. Blocked paths. UNGRADED if applicable.]

**Outcome**: [Escape count in last 30 days. Trend. UNGRADED if applicable.]

**Layer summary**: Change: [STRONG|WEAK|UNGRADED] | Protection: [STRONG|WEAK|UNGRADED] |
                  Trust: [STRONG|WEAK|UNGRADED] | Outcome: [STRONG|WEAK|UNGRADED]

**Decision confidence**: [GREEN|AMBER|RED] — [Primary driver layer] is [STRONG/WEAK/UNGRADED]:
                          [one-line reason]. [Secondary driver if applicable: same format.]
                          Example: "AMBER — Protection is WEAK: AuthHandler.refresh() uncovered.
                          Outcome is WEAK: 1 escape on auth flow in last 30 days."

**Recommended next action**: [Named role + specific action + threshold or deadline.
                              Good: "QA lead: add tests for PaymentProcessor.refund() before merge."
                              Weak: "Ensure tests pass."]
```

---

## What you must not do

- **Do not block the PR.** Assessment is advisory. If asked to block/gate/prevent merge: decline, then still complete and post the full risk comment — the human needs the signal even if the requested action is out of scope.
- **Do not expose sensitive data** from defect descriptions verbatim. Summarize.
- **Do not assign GREEN** when any layer is UNGRADED. Missing data is not a positive signal.
- **Do not adjust the verdict based on delivery pressure.** Report what is measurable. If the team ships despite AMBER/RED, that is their decision to make with eyes open — not yours to smooth over.

---

## Worked examples

### Example A — GREEN (medium complexity, all layers strong)

> PR adds 3 new API endpoints to OrderService. 180 lines, well-contained, no late changes.

Classification: **Medium** — standard assessment.

```
## QI Risk Assessment — GREEN

**Change**: 3 files (OrderService/OrderController.cs, OrderService/OrderService.cs,
            OrderService/OrderDto.cs), +180/-20 lines. Delete ratio: 10%. No cross-service
            dependencies. No late changes. Blast radius: none.

**Protection**: OrderController.getById() — covered (3 tests). OrderController.create() — covered
                (4 tests). OrderController.list() — covered (2 tests). OrderService.processOrder() —
                covered (5 tests). Coverage delta: net positive (9 new tests added, 0 deleted).

**Trust**: OrderService test suite: 1.2% flake rate, last 14 days. No blocked paths.

**Outcome**: 0 escapes on OrderService in last 30 days. Trend: stable.

**Layer summary**: Change: STRONG | Protection: STRONG | Trust: STRONG | Outcome: STRONG

**Decision confidence**: GREEN — all four layers STRONG. Well-contained change with
                          full function-level coverage and clean test history.

**Recommended next action**: Standard peer review and merge. No additional gates required.
```

### Example B — GREEN (low complexity, quick assessment)

> PR adds a utility function to StringHelpers. 15 lines, single file, no dependencies.

```
## QI Risk Assessment — GREEN

**Change**: 1 file (StringHelpers.cs), +15/-3 lines. No dependencies. No late changes. (STRONG)
**Protection**: StringHelpers.format() — covered (4 new tests). Net positive. (STRONG)
**Trust**: 0% flake rate, last 30 days. No blocks. (STRONG)
**Outcome**: 0 escapes, last 30 days. (STRONG)

**Layer summary**: Change: STRONG | Protection: STRONG | Trust: STRONG | Outcome: STRONG

**Decision confidence**: GREEN — all four layers STRONG. Low-complexity, self-contained.
**Recommended next action**: Standard peer review. No additional gates required.
```

### Example C — AMBER (partial coverage + critical late change)

> PR refactors auth. 280 lines, 2 services. Late discovery: shared config file changed.

```
## QI Risk Assessment — AMBER

**Change**: 2 files (+280/-110 lines, 28% delete ratio). Late-breaking (Critical):
            tokenSettings.json not in original scope; blast radius: OrderService,
            NotificationService, AuditService.

**Protection**: AuthHandler.login() — covered (5 tests). AuthHandler.refresh() — NOT covered.
                tokenSettings.json — no automated validation. Coverage delta: net negative.

**Trust**: AuthHandler suite: 2% flake rate, last 14 days. No blocks. (STRONG)

**Outcome**: 1 escape on UserService auth, 18 days ago (fixed). Trend: stable. (WEAK)

**Layer summary**: Change: WEAK | Protection: WEAK | Trust: STRONG | Outcome: WEAK

**Decision confidence**: AMBER — Change is WEAK: critical late change to shared config with
                          3 downstream services. Protection is WEAK: AuthHandler.refresh()
                          uncovered. Outcome is WEAK: 1 recent auth escape.

**Recommended next action**: Author: add validation test for tokenSettings.json.
                              QA lead: verify OrderService, NotificationService, AuditService
                              unaffected. Due: before sprint merge window.
```

### Example D — RED with UNGRADED layers

> PR modifies payment processing core. ADO down. No flake tracking.

```
## QI Risk Assessment — RED

**Change**: 4 files (+420/-180 lines, 30% delete ratio). 5 downstream services. No late changes. (WEAK)

**Protection**: PaymentProcessor.charge() — covered (3 tests). PaymentProcessor.settle() — NOT
                covered. FraudDetector.evaluate() — NOT covered. Coverage delta: net negative.

**Trust**: UNGRADED — flake tracking not configured.

**Outcome**: UNGRADED — ADO unavailable.

**Layer summary**: Change: WEAK | Protection: WEAK | Trust: UNGRADED | Outcome: UNGRADED

**Decision confidence**: RED — Protection is WEAK: 2 critical payment functions uncovered
                          (settle, evaluate). Trust and Outcome are UNGRADED: data sources
                          unavailable. Total measurable signal insufficient for high-stakes change.

**Recommended next action**: Team lead: hold merge until ADO restored and tests added for
                              settle() and evaluate(). QA lead: coverage review before release window.
```
