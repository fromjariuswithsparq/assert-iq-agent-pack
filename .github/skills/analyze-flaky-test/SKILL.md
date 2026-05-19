---
name: analyze-flaky-test
mode: agent
description: "Analyze flake patterns over run history — find the systemic cause, not just diagnose one failure."
---

<!-- markdownlint-disable MD033 -->
<!--
HOW TO CUSTOMIZE THIS SKILL
===========================

This skill is a universal template. It works out of the box for **any
language, framework, platform, CI system, or team** — the flake-pattern
taxonomy and root-cause discipline are universal; only the data source and
test runner change. You'll get sharper results if you fill in the per-repo
specifics below.

**How placeholders work**: `{{NAME}}` strings are **documentation
placeholders, not runtime variables** — nothing substitutes them
automatically. The agent reads this file, then reads
`.assert-iq/config.yaml` to find the corresponding key (cited next to
each placeholder). If the key is absent, the agent infers from repo
signals or asks you. Wire the values once in `.assert-iq/config.yaml`
and they flow into every skill that references them — no per-skill
editing required.

1. **Test-results store** — `{{RESULTS_STORE}}` is where historical run
   data lives. Examples:
   - CI provider native: GitHub Actions (Artifacts + Checks API), Azure
     Pipelines (Test Plans / TRX), GitLab CI (JUnit XML artifacts),
     Jenkins (JUnit / xUnit publisher), CircleCI (test metadata), Buildkite
     (`buildkite-test-collector`), TeamCity
   - Test-analytics platforms: Datadog CI Visibility, Launchable,
     BuildPulse, Allure TestOps, ReportPortal, Trunk Flaky Tests, Foresight,
     Currents (Cypress), Sauce Labs Insights, BrowserStack Insights,
     Microsoft Playwright Service
   - Self-hosted: Elasticsearch / OpenSearch index of JUnit XML, ClickHouse
     test-results table, BigQuery / Snowflake warehouse of CI exports
   Wire access in `.assert-iq/config.yaml > flake_analysis.results_store`.

2. **Query mechanism** — `{{RESULTS_QUERY}}` is how the agent fetches
   history. Options in priority order:
   - MCP server (Datadog MCP, GitHub MCP, Azure DevOps MCP, etc.) — preferred.
   - REST / GraphQL API call with a stored credential reference.
   - CLI wrapper (`gh run list`, `az pipelines runs test results list`,
     `glab ci list`).
   - Local file glob over JUnit / TRX / xUnit XML artifacts.
   - Manual paste — the user pastes recent runs inline.

3. **Test identifier format** — `{{TEST_ID_FORMAT}}` is how a test is named
   in your results store. Examples:
   - JUnit: `com.example.MyTest#testMethod`
   - pytest: `tests/test_foo.py::TestClass::test_method`
   - xUnit / NUnit / MSTest: `Namespace.ClassName.MethodName`
   - Go: `TestFunctionName` (with `pkg/path` prefix)
   - Jest / Vitest / Mocha: `describe › nested describe › it name`
   - Playwright / Cypress: spec file + test title path
   This determines how the agent groups runs into a single test history.

4. **History window** — `{{HISTORY_DAYS}}` is the default lookback.
   Default is `30`. Set in `.assert-iq/config.yaml >
   flake_analysis.history_days`. Increase for low-velocity repos, decrease
   for very-high-frequency CI.

5. **Flake threshold** — what counts as "flaky" in your team's vocabulary.
   Default is **pass rate between 5% and 95% on the same commit SHA, or ≥2
   alternating pass/fail transitions in the window**. Override in
   `.assert-iq/config.yaml > flake_analysis.flake_threshold`.

6. **Environment / dimensions to correlate** — `{{CORRELATION_DIMS}}` is
   the list of axes the analyzer slices flake by. Defaults: branch,
   environment, runner type, time-of-day, day-of-week, parallel-shard
   index. Add team-specific dimensions (region, browser, device profile,
   feature flag, tenant) in
   `.assert-iq/config.yaml > flake_analysis.correlation_dimensions`.

7. **Mitigation libraries** — the recommendations in step 5 of the
   Procedure call out generic patterns (explicit waits, factory isolation,
   contract mocks, etc.). If your framework has a preferred library
   (e.g. Playwright `expect.toPass`, Awaitility for JVM, `pytest-retry`,
   `Polly` for .NET, `tenacity` for Python), record it under
   `.assert-iq/config.yaml > flake_analysis.preferred_mitigations` so
   the agent recommends your team's idiom.

8. **Quarantine policy** — by default this skill **refuses** to quarantine
   or `@Skip` a test as a fix. If your team uses a structured
   quarantine workflow (label, tag, separate suite, dashboard), document
   it under `.assert-iq/config.yaml > flake_analysis.quarantine_workflow`
   so the agent can recommend it with the required expiry and owner
   fields. The governance rule below remains: quarantine is **containment,
   not a fix**.

9. **Report sink** — by default the report is written to
   `flake-analysis-report.md` at the repo root. Override the path in
   `.assert-iq/config.yaml > flake_analysis.report_path`. (Structured
   QI signal emission is separate — see the `signals` section in
   `.assert-iq/config.yaml`.)
-->

# Analyze flaky test

This skill operates over **historical run
data** to find *patterns* of flake (timing, environment, data,
concurrency) rather than diagnose a single failure.

This skill is **framework-, language-, platform-, and CI-agnostic** — it
queries whatever results store and runner your team already uses (see
`{{RESULTS_STORE}}`, `{{RESULTS_QUERY}}`, and `{{TEST_ID_FORMAT}}` in the
customization block above).

## Inputs

- **Scope** — a single test ID in `{{TEST_ID_FORMAT}}`, a suite / file /
  tag glob, or "all flakes in the last N days."
- **History window** — defaults to `{{HISTORY_DAYS}}` (configurable via
  `.assert-iq/config.yaml > flake_analysis.history_days`).
- **Optional dimension filter** — limit analysis to a branch, environment,
  runner, or any axis in `{{CORRELATION_DIMS}}`.

## Procedure

1. **Pull run history** for the scope from `{{RESULTS_STORE}}` via
   `{{RESULTS_QUERY}}`. If none is wired, ask the user where flake data
   lives and fall back to a manual paste.

2. **Compute flake metrics** per test:
   - Pass rate over the window
   - Failure clustering across `{{CORRELATION_DIMS}}` (time-of-day,
     day-of-week, branch, environment, runner, shard, region, browser,
     etc.)
   - Failure-signature diversity (is it the same error every time, or many?)
   - Co-failure correlation (does it flake alongside other tests?)
   - First-seen / last-seen and trend (worsening, stable, recovering)

3. **Classify the flake pattern**:
   - **Timing** — race conditions, animations, async ordering, missing waits
   - **Environment** — flake correlates with environment instability,
     pipeline runner, or specific agent
   - **Data** — flake correlates with shared test data or order-dependent
     setup
   - **Concurrency** — flake correlates with parallel execution / shard
   - **External dependency** — flake correlates with third-party service
     latency or availability
   - **Genuine intermittent bug** — production code has a real race or
     non-determinism

4. **Produce a confidence-weighted root-cause hypothesis.** State your
   confidence level and what evidence would raise or lower it.

5. **Recommend mitigation** per pattern, preferring the team's idioms
   from `flake_analysis.preferred_mitigations` when set:
   - Timing → explicit wait / idempotent setup
     (e.g. Playwright `expect.toPass`, Awaitility, `pytest-retry`)
   - Environment → infrastructure ticket, runner pinning, image rebuild
   - Data → test isolation, per-test factory regeneration, transaction
     rollback
   - Concurrency → serialize, fix shared state, scope fixtures correctly
   - External → contract mock, retry-with-backoff at the boundary,
     circuit breaker (Polly / resilience4j / tenacity)
   - Genuine bug → escalate to engineering; do **not** patch in test

6. **Output a flake-pattern report** containing:
   - Scope and history window
   - Flake metrics and trend
   - Pattern classification with confidence
   - Recommended mitigation, owner, and target sprint
   - Any cross-test pattern detected
   - Traceability reference if the test carries a tracker ID

## Governance

- Do **not** quarantine or skip the test as a fix. Quarantine is
  **temporary containment**; if recommended, it must follow the workflow
  in `flake_analysis.quarantine_workflow` and carry an explicit **expiry
  date and owner**.
- If the root cause is a **genuine production bug**, escalate. Do **not**
  propose test-side workarounds for production issues.
- Surface flake patterns that span **multiple tests** as systemic issues;
  a per-test fix is the wrong altitude. Recommend the cross-cutting
  remediation explicitly.
- Preserve any existing traceability comments (`AB#`, Jira key, etc.) on
  tests touched by the recommendations.

## Output

A `flake-analysis-report.md` artifact (or the path configured in
`.assert-iq/config.yaml > flake_analysis.report_path`) with the
sections listed in step 6. No silent edits to test files — recommendations
are presented for human review unless the maturity tier explicitly allows
autonomous mitigation.

## Signals emitted

When the QI signal sink is wired, this skill emits a `test.flake_analysis`
signal per run conforming to `.assert-iq/signal-schema.json`, carrying:
`scope`, `history_window_days`, `flake_count`, `pattern_classification`,
`confidence`, `correlation_dimensions[]`, `recommended_action`,
`cross_test_pattern_detected`, and `tracker_ref`.
