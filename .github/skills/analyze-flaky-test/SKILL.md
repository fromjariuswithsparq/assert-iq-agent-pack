---
name: analyze-flaky-test
mode: agent
description: "Analyze flake patterns over run history — find the systemic cause, not just diagnose one failure."
---

# Analyze flaky test

Different from `/debug-ui-tests`: this skill operates over historical run
data to find *patterns* of flake (timing, environment, data, concurrency)
rather than diagnose a single failure.

## Inputs

- Scope: a single test ID, a suite, or "all flakes in the last N days."
- History window (default: 30 days, configurable in `config.yaml` under
  `flake_analysis.history_days`).

## Procedure

1. Pull run history for the scope from the configured CI / test-results
   store. If none is wired, ask the user where flake data lives.

2. Compute flake metrics per test:
   - Pass rate over window
   - Failure clustering (time-of-day, day-of-week, branch, environment)
   - Failure signature diversity (is it the same error every time, or many?)
   - Co-failure correlation (does it flake alongside other tests?)

3. Classify the flake pattern:
   - **Timing** — race conditions, animations, async ordering, missing waits
   - **Environment** — flake correlates with environment instability,
     pipeline runner, or specific agent
   - **Data** — flake correlates with shared test data or order-dependent
     setup
   - **Concurrency** — flake correlates with parallel execution
   - **External dependency** — flake correlates with third-party service
     latency or availability
   - **Genuine intermittent bug** — production code has a real race or
     non-determinism

4. Produce a confidence-weighted root cause hypothesis. State your
   confidence and what evidence would raise or lower it.

5. Recommend mitigation per pattern:
   - Timing → explicit wait, idempotent setup
   - Environment → infrastructure ticket, runner pinning
   - Data → test isolation, factory regeneration per test
   - Concurrency → serialize, or fix shared state
   - External → contract mock, retry-with-backoff at the boundary
   - Genuine bug → escalate to engineering; do not patch in test

6. Output a flake pattern report. Include a recommended next action with
   an owner and a target sprint.

## Governance

- Do not quarantine or skip the test as a fix. Quarantine is a temporary
  containment; recommend it explicitly with an expiry date if needed.
- If the root cause is a genuine production bug, escalate. Do not propose
  test-side workarounds for production issues.
- Surface flake patterns that span multiple tests as systemic issues; a
  per-test fix is the wrong altitude.
