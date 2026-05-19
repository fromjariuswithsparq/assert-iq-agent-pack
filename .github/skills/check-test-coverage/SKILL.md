---
name: check-test-coverage
description: "Coverage analysis with QI risk weighting — not just %, but coverage where it matters."
---

# Check test coverage

Coverage analysis through the QI lens. Raw coverage % is a metric; risk-weighted
coverage is a signal.

## Inputs

- Scope: current diff, full repo, or named module. Default: current diff.

## Procedure

1. Pull coverage report from the configured tool (`coverage_command` in
   `~/Library/Application Support/Code/User/prompts/assert-iq/config.yaml`).
2. Identify the changed surfaces in the current scope.
3. Compute three coverage views:
   - **Line coverage on changed code** — raw %.
   - **Risk-weighted coverage** — coverage % weighted by:
     - business criticality of the workflow (from work item priority)
     - recent escape history on the component (from tracker)
     - change churn on the file (from git)
   - **Traceability coverage** — % of changed functions that have a `///<qi-trace: WORK-ITEM />`
     resolving to a real work item.
4. Surface gaps in this order:
   - Uncovered code on a critical workflow with recent escapes.
   - Uncovered code with high churn.
   - Untraceable code (no work item linkage).
   - Standard low-coverage gaps.
5. Recommend specific tests to author. Where possible, propose the route
   (automation / manual / exploratory) per gap.

## Governance

- Do not optimize for raw % over risk-weighted coverage. Surface both, lead
  with risk-weighted.
- Do not modify the coverage tool's configuration without explicit confirmation.
