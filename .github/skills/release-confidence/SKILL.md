---
name: release-confidence
description: "Aggregate QI signals across an upcoming release and produce a go/no-go report."
---

# Release confidence report

Produce a release readiness report for a candidate release artifact (tag, build,
or release branch). Aggregates signals across the QI four-layer model and delivers
an evidence-based go/no-go recommendation.

## Scope boundary

This skill assesses **release-level** confidence (multiple PRs, a release scope).

| Request | Action |
|---|---|
| Release/tag/build + feature scope | Proceed with report below |
| Single PR risk assessment | Redirect: "That's PR-level scope — use `risk-assess-pr`. For release confidence, provide the release candidate (tag/build/branch) and the set of features included." |
| "Should we deploy?" + release context | Proceed |
| "Is this PR safe?" / single change | Redirect: "Single-change assessment uses `risk-assess-pr`. Release confidence aggregates across all changes in a release." |
| Sprint/milestone with no specific artifact | Ask: "Which build/tag/branch represents the release candidate?" |

## Inputs

- **Release identifier** — tag, branch, or build number
- **Scope** — work items/features included (fetch via MCP; otherwise ask user)
- **Available signals** — what data sources are accessible (CI, coverage, telemetry, incident history)

## Procedure

### Step 1: Gather signals

| Layer | Sources | What to look for |
|---|---|---|
| **Change risk** | PR list, diff scope, files touched, services impacted | Criticality of workflows, blast radius, reversibility |
| **Protection** | Coverage, traceability, PR reviews | Coverage on impacted code, requirement-to-test mapping |
| **Signal trust** | Test results, flake history, CI status | Pass rates, flake/block counts, overrides, test age |
| **Outcome evidence** | Prod telemetry, incident history, escaped defects | Recent incidents, error rate trends, SLO status |

**If a signal source is unavailable:** Note it explicitly. Don't fabricate. Score that layer with reduced confidence.

### Step 2: Score each layer

Score each layer **High / Medium / Low**:

| Layer | High | Medium | Low |
|---|---|---|---|
| **Change** | Low-criticality, small scope, fully reversible | Mixed criticality, moderate scope, mostly reversible | High-criticality workflows, large scope, irreversible |
| **Protection** | ≥80% coverage on impacted code, full traceability | 60-80% coverage, partial traceability | <60% coverage, no traceability, bypassed reviews |
| **Trust** | <2% flake rate, no overrides, tests well-aged | 2-5% flake rate, minor overrides | >5% flake, overridden failures, untested new tests |
| **Outcome** | No incidents on touched components (30d), stable | Minor incidents, slight variance | Recent P1/P2 on touched components, degrading trends |

#### Intra-layer aggregation

When a layer has mixed signals across services/components:

1. **Weight by criticality** — payment pipeline at 60% coverage matters more than admin dashboard at 60%
2. **Worst-critical-path rule** — the layer score cannot exceed the score of its most critical component
3. **Example:** Auth 94% + Payments 78% + Notifications 60%. If payments is highest-criticality → Protection score is driven by payments (78% → Medium). Notifications at 60% reinforces Medium. Overall: **Medium**.

### Step 3: Validate signals (red-flag check)

Before computing verdict, check for patterns that invalidate surface metrics:

| Red flag | Signal | Impact |
|---|---|---|
| Coverage spike (>20% jump in <1 week) | Tests may be shallow/quantity-over-quality | Protection → Medium max |
| New tests >30% of covering suite (<48h old) | Unproven test reliability | Trust → downgrade one level |
| Overridden/skipped CI checks | Signals actively suppressed | Trust → Low |
| Key personnel unavailable post-deploy | Can't triage issues | Add operational mitigation |
| No rollback plan for irreversible changes | Recovery impossible | Cannot be GO without plan |
| No production baseline (new product area) | Cannot assess Outcome layer | Outcome → "Unable to assess"; increase Protection weight |
| Business pressure to ship | External factor | Note in report; never adjusts layer scores |
| Deploy window risk (Friday PM, holiday eve) | Reduced response capacity | Add operational mitigation |

### Step 4: Determine verdict

| Verdict | Criteria |
|---|---|
| **GO** | All layers High, OR 3 High + 1 Medium with no red flags |
| **GO-WITH-MITIGATION** | At least 2 High, no Low, mitigations address Medium areas |
| **HOLD** | Any layer Low, OR unmitigatable red flag, OR multiple Medium + red flags |

**HOLD framing:** "What needs to happen before this ships" — list specific resolution criteria.

**Low layer + mitigation?** Only if mitigation fully resolves the Low (e.g., "add rollback plan" resolves "no rollback plan"). If Low comes from fundamental coverage/quality gaps, mitigation can't substitute → HOLD.

### Step 5: Assess operational readiness

Beyond code quality — supplementary factors that can add mitigations or caveats:
- On-call capacity and domain expertise coverage
- Rollback plan existence and test status
- Monitoring/alerting for impacted paths
- Communication plan for customer-facing changes
- Deploy window appropriateness

These don't override layer verdicts but can add mitigations to a GO verdict.

### Step 6: Produce report

```markdown
# Release Confidence Report — <release-id>

**Verdict:** GO | GO-WITH-MITIGATION | HOLD
**Date:** <date>
**Signals available:** <what was assessable>
**Signal gaps:** <what's missing, if any> → <impact on confidence>

## Layer Scores

| Layer | Score | Key Evidence |
|---|---|---|
| Change risk | High/Med/Low | <1-2 sentences with data> |
| Protection | High/Med/Low | <coverage %, traceability, reviews> |
| Signal trust | High/Med/Low | <pass rate, flakes, overrides, test age> |
| Outcome evidence | High/Med/Low | <incidents, trends, or "unable to assess — no baseline"> |

## Red Flags
- [Flag]: [Evidence] → [Scoring impact]
(or "None identified")

## Operational Readiness
- On-call: [status]
- Rollback: [exists/tested/missing]
- Monitoring: [adequate/gaps]
- Deploy window: [appropriate/risky]

## Mitigations Required (GO-WITH-MITIGATION)
| # | Mitigation | Owner | By When | Addresses |
|---|---|---|---|---|
| 1 | <action> | <person/team> | <date> | <layer/risk> |

## Blocking Items (HOLD)
| # | Blocker | Resolution Criteria | Layer |
|---|---|---|---|
| 1 | <blocker> | <what specifically must change> | <layer> |

## Explicit Risk Acceptance
- <risk> — accepted by <name/role> — rationale: <why>

## What Would Change the Verdict
- <signal shift that flips recommendation>
- <e.g., "Coverage on payment path → 80% upgrades Protection to High → GO">
```

### Partial-signal mode

When signals are incomplete, add to report header:
```markdown
**Confidence modifier:** Reduced — [layer(s)] could not be independently verified.
**Assumptions:** <what was assumed in absence of data>
```

For unassessable layers:
> "[Layer]: Unable to assess — [source] unavailable. Assuming Medium for verdict calculation. Verify [specific data needed] before shipping."

### Low-risk fast-path

If initial scan shows: all changes are low-criticality (UI copy, config, styling), scope is small (≤5 PRs, single service), no red flags visible → abbreviated report:

```markdown
# Release Confidence — <id>
**Verdict:** GO (low-risk fast-path)
**Rationale:** [N] low-criticality changes, [service] only, all signals green, no red flags.
**Caveat:** Fast-path applied due to low complexity. Full assessment not performed.
```

## Governance

- Never GO when any layer is Low without a mitigation that fully resolves the Low.
- Low + incomplete mitigation = HOLD.
- Business pressure noted in report but never adjusts layer scores.
- All risk acceptances require a named person/role.
- HOLD includes specific resolution criteria (not just "fix it").
- Verdict must be justified by layer scores — no overriding the framework with "gut feel."

## Worked examples

### Standard release — GO-WITH-MITIGATION

```
Release: v2.4.1 — 12 PRs, Auth + Payments + Notifications services

Step 1-2 (Gather + Score):
  Change: Mixed criticality (auth=high, notifications=low), moderate scope, reversible → Medium
  Protection: Auth 94%, Payments 78%, Notifications 60%. Payments is highest-criticality.
    → Worst-critical-path: Payments 78% = Medium. Notification 60% reinforces. → Medium.
  Trust: 1.2% flake rate, no overrides, tests aged 3+ months → High
  Outcome: No incidents on auth/payments (30d), 1 minor on notifications (resolved) → High

Step 3 (Red flags): None identified.

Step 4 (Verdict): 2 High (Trust, Outcome) + 2 Medium (Change, Protection), no Low, no flags
  → GO-WITH-MITIGATION (need mitigations for Medium areas)

Mitigations:
  1. Add integration test for payments edge case (78% gap area) — owner: @payments-team — by: before deploy
  2. Feature flag on auth changes for instant rollback — owner: @platform — by: deploy time

What would change: "Payments coverage → 80% upgrades Protection to High → plain GO."
```

### Partial signals — degraded mode

```
Release: v1.2.0 — 4 PRs, UI theming + accessibility fixes, single frontend service.
No MCP available. No coverage tool integrated. Manual review only.

Step 1-2 (Gather + Score):
  Change: Low-criticality (styling, a11y), small scope, fully reversible → High
  Protection: Unable to assess — no coverage tool. Code reviews: all 4 PRs approved by 2+ reviewers.
    → Unable to assess independently. Reviews suggest adequate. Assuming Medium.
  Trust: Manual test pass on staging. No automated suite metrics available.
    → Unable to assess independently. Manual pass noted. Assuming Medium.
  Outcome: No prior incidents on frontend theming (90d). → High

Step 3 (Red flags): None.

Step 4 (Verdict): 2 High (Change, Outcome) + 2 assumed-Medium (Protection, Trust), no flags.
  → GO-WITH-MITIGATION (reduced confidence)

Confidence modifier: Reduced — Protection and Trust could not be independently verified.
Assumptions: Coverage adequate based on review approval; tests reliable based on manual pass.

Mitigations:
  1. Manual smoke test of themed pages across browsers — owner: @frontend-qa — by: deploy day
  2. Staged rollout (internal → 10% → 100%) — owner: @platform — by: deploy sequence

What would change: "Integrating coverage tool would allow independent Protection verification."
```

### Adversarial / conflicting signals — don't be fooled

```
Release: v3.0.0-beta — 100% CI pass, 89% coverage (was 45% last week),
all core authors on vacation, business must-ship deadline, new product area.

Step 2 (initial): Change=Medium (new area, moderate scope), Protection=High (89%!),
                  Trust=High (100% pass!), Outcome=N/A (new area).

Step 3 (red flags):
  - Coverage spike: 45% → 89% in one week → Protection capped at Medium
  - New tests: >40% of suite added in 48h → Trust downgraded to Medium
  - No baseline: new product → Outcome unable to assess (assume Medium)
  - Key personnel: unavailable → operational mitigation needed
  - Business pressure: noted, scores unchanged

Step 4: Revised scores: Change=Medium, Protection=Medium, Trust=Medium, Outcome=Medium.
        Multiple Medium + red flags → Verdict: GO-WITH-MITIGATION (borderline HOLD)

Mitigations: Manual smoke test of critical paths (covers Protection gap),
             senior engineer on-call arrangement (covers personnel gap),
             staged rollout (10% → 50% → 100%) instead of full deploy.

What would change: "If coverage jump is verified as meaningful (tests cover real scenarios,
not just line coverage gaming), Protection upgrades → stronger GO."
```
