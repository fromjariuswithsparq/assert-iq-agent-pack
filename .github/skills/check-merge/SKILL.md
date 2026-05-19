---
name: check-merge
mode: agent
description: "Pre-merge quality gate — synthesize all signals into a merge / hold / discuss verdict."
---

# Check merge

Run a pre-merge quality gate against the current PR. Aggregate all available
signals; produce a verdict the developer can act on in seconds.

## Inputs

- PR identifier (default: current branch's PR).

## Procedure

1. Confirm CI state: tests passing, coverage uploaded, lint clean.
2. Pull the latest `/risk-assess-pr` result. If none, run it.
3. Pull `/check-test-coverage` for the changed surfaces.
4. Pull traceability — every changed function should resolve to a work item.
5. Check for quarantined or skipped tests near touched code.
6. Check for unaddressed comments from `/code-review`.
7. Compute verdict:
   - **MERGE** — all signals green, no blockers.
   - **HOLD** — at least one red signal (failing test, missing coverage on
     high-risk path, regression detected).
   - **DISCUSS** — amber signals require a human decision (e.g., risk-accepted
     mitigation, scope change).
8. Output a one-screen merge readiness card.

## Governance

- This is advisory. Branch protection, not Copilot, gates merges.
- Do not modify branch protection settings.
- If maturity tier is `early`, soften verdicts: surface concerns rather than
  enforce gates.
