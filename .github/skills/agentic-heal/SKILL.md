---
name: agentic-heal
mode: agent
description: "Agentic Healing — autonomously diagnose, repair, and re-execute failing tests within bounded retries."
---

# Agentic Healing

Operationalizes the UPS MDA pattern: when a test fails, diagnose the root cause,
propose a minimal correction, re-execute, and iterate until the test passes or
the retry bound is exhausted.

## Pre-conditions

- Maturity tier in `.assert-iq/config.yaml` must be `mid` (suggest-only) or
  `higher` (autonomous within bounds). On `early`, this prompt explains why
  it is disabled and exits.
- The repository must have an executable test command configured.

## Inputs you must collect

- Failing test identifier (path or test name) — required.
- Retry bound (default: 3).
- Allowed change scope: `test-only` (default) or `test-plus-fixtures`. Never
  `production-code` without explicit user confirmation.

## Procedure

1. Capture the current failure signature: stack trace, assertion, last green commit.
2. Classify the failure:
   - flaky (retry-able without code change)
   - environmental (configuration or data issue)
   - assertion drift (test expectation outdated against current correct behavior)
   - regression (production code broke the contract)
3. Pick the minimal corrective action consistent with the allowed change scope.
4. Apply, re-execute, observe the new failure signature.
5. Repeat until pass OR retry bound reached.
6. Emit a healing report with:
   - failure signatures observed
   - actions taken
   - final outcome
   - confidence level
   - human review recommendation

## Stop conditions

- Retry bound reached.
- Two consecutive iterations produce identical signatures (no progress).
- A regression is detected — escalate to the developer; do not patch
  production code under any maturity tier.

## Output

A `healing-report.md` artifact with the iteration log, plus the corrected
test file. Never silently quarantine or skip a test.
