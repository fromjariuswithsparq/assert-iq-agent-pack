---
name: debug-ui-tests
mode: agent
description: "Diagnose failing UI tests — distinguish flaky vs brittle vs broken vs regression."
---

# Debug UI tests

Diagnose a failing or unstable UI test. Produce a root-cause classification
and the minimal corrective action.

## Inputs

- Failing test identifier (path or test name).
- Optional: recent run history if available via CI MCP.

## Procedure

1. Pull the test file and the failing assertion / error.
2. Pull the last 5 runs (pass/fail history).
3. Classify the failure into one of four categories:
   - **Flaky** — passes/fails non-deterministically. Likely waits, animations,
     timing, race conditions, shared state.
   - **Brittle** — passes today but breaks on minor UI changes. Likely fragile
     selectors, hard-coded data, environment coupling.
   - **Broken** — test logic itself is incorrect or outdated.
   - **Regression** — test is correct; production code broke the contract.
4. For flaky/brittle: propose a minimal fix in the test (better selector,
   explicit wait, idempotent setup).
5. For broken: surface the assertion drift; propose updated expectation.
6. For regression: STOP. Escalate to the developer. Do not patch.
7. Output a debug report including signature, classification, evidence,
   recommended action, confidence level.

## Governance

- Never modify production code from this skill. Regressions escalate.
- Never silently skip or quarantine. If a fix is not possible, surface the
  recommendation for the human to decide.
