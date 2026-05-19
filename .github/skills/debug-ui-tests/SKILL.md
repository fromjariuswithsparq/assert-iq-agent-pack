---
name: debug-ui-tests
mode: agent
description: "Diagnose failing UI tests — distinguish flaky vs brittle vs broken vs regression."
---

<!-- markdownlint-disable MD033 -->
<!--
HOW TO CUSTOMIZE THIS SKILL
===========================

This skill is a universal template. It works out of the box for **any
UI test framework, language, platform, browser/device target, CI host, or
team** — it diagnoses whatever UI test runner your repo already uses; it
does not impose one. You'll get sharper, faster results if you fill in
the per-repo specifics below.

**How placeholders work**: `{{NAME}}` strings are **documentation
placeholders, not runtime variables** — nothing substitutes them
automatically. The agent reads this file, then reads
`.assert-iq/config.yaml` to find the corresponding key (cited next to
each placeholder). If the key is absent, the agent infers from repo
signals or asks you. Wire the values once in `.assert-iq/config.yaml`
and they flow into every skill that references them — no per-skill
editing required.

1. **UI test framework** — set
   `.assert-iq/config.yaml > test_framework.primary`. Examples and the
   selector/wait idioms the agent will assume:
   - **Playwright** (TS/JS/Python/.NET/Java): `getByRole`, `getByTestId`,
     `expect(locator).toBeVisible()` auto-wait
   - **Cypress** (JS/TS): `cy.get('[data-cy=...]')`, retry-ability
     built-in
   - **WebdriverIO** (JS/TS): `$('aria/...')`, `waitForDisplayed`
   - **Selenium** (any language): `WebDriverWait` + `ExpectedConditions`
   - **Puppeteer** (JS/TS): `page.waitForSelector`
   - **TestCafe** (JS/TS): smart wait + `Selector`
   - **Appium** (any language): `accessibility-id` selectors, mobile
     contexts
   - **Espresso** (Android / Kotlin / Java): `onView(withId(...))`,
     `IdlingResource`
   - **XCUITest** (iOS / Swift): `XCUIApplication().buttons["id"]`,
     `waitForExistence`
   - **Detox** (React Native): `by.id(...)`, automatic sync
   - **Maestro** (mobile): YAML flows with retries
   - **Robot Framework + SeleniumLibrary / Browser**: keyword-style
   - **Generic / other**: the universal taxonomy below still applies

2. **Targeted-test command** — `{{TARGETED_TEST_COMMAND}}` runs the
   single failing UI test. Examples by framework:
   - Playwright: `npx playwright test path/to/spec.ts:42`
   - Cypress: `npx cypress run --spec path/to/spec.cy.ts`
   - Selenium (pytest): `pytest tests/ui/test_login.py::test_happy_path`
   - WebdriverIO: `npx wdio run wdio.conf.ts --spec path/to/spec.ts`
   - Espresso: `./gradlew connectedDebugAndroidTest --tests <FQN>`
   - XCUITest: `xcodebuild test -only-testing:<Target>/<Class>/<Test>`
   - Generic: whatever your CI invokes

3. **Run-history source** — set
   `.assert-iq/config.yaml > flake_analysis.results_store` (this skill
   reuses the same store as `analyze-flaky-test`). Options:
   `ci_native` | `junit_glob` | `datadog` | `launchable` | `buildpulse`
   | `allure` | `reportportal` | `trunk` | `elasticsearch` |
   `clickhouse` | `bigquery` | `snowflake`. Preferred fallback chain:
   MCP → CLI → manual paste.

4. **Artifact retrieval** — UI debugging hinges on visual evidence. Set
   `.assert-iq/config.yaml > ui_debug.artifact_sources` to a list of
   where the skill should look for screenshots, video, traces, DOM
   snapshots, logs. Defaults cover common locations:
   `./test-results/**`, `./playwright-report/**`, `./cypress/screenshots/**`,
   `./cypress/videos/**`, `./build/reports/androidTests/**`,
   CI-host artifact URLs when MCP is wired.

5. **Selector-stability policy** — `.assert-iq/config.yaml >
   ui_debug.selector_policy`:
   - `test_id_first` (default) — prefer `data-testid` / `data-cy` /
     `accessibility-id` / `automation-id`
   - `role_first` — prefer ARIA-role-based selectors
     (`getByRole`, accessibility identifiers)
   - `text_allowed` — allow text-based selectors when stable
   - `xpath_last_resort` — only when no other anchor exists

6. **Wait-strategy policy** — `.assert-iq/config.yaml >
   ui_debug.wait_policy`:
   - `framework_auto` (default) — rely on framework's built-in retry /
     auto-wait (Playwright, Cypress)
   - `explicit_conditions` — require explicit `wait_for_*` /
     `ExpectedConditions` calls
   - `forbid_sleeps` — flag any hard sleep / `Thread.sleep` /
     `cy.wait(<ms>)` / `time.sleep` as 🔴 (default true for new edits)

7. **Maturity tier** — set `maturity_tier` in `.assert-iq/config.yaml`.
   `early` → diagnose and recommend, no edits. `mid` → suggest-only
   patches. `higher` → autonomous test-side fixes within bounds (never
   production code).

8. **Production code is off-limits** — regardless of tier, this skill
   **never** patches production code. Regressions escalate.

9. **Debug-report sink** — by default the report is written to
   `ui-debug-report.md` at the repo root. Override the path in
   `.assert-iq/config.yaml > ui_debug.report_path`. (Structured QI
   signal emission is separate — see the `signals` section in
   `.assert-iq/config.yaml`.)

10. **Platform notes** — this skill is platform-agnostic (desktop web,
    mobile web, native iOS, native Android, React Native, Electron,
    embedded WebView, VR/AR harness). If your runner needs a wrapper
    (`xvfb-run`, `docker compose exec`, `npx playwright test`,
    `flutter drive`, `gradle connectedAndroidTest`, simulator boot),
    include that wrapper inside `{{TARGETED_TEST_COMMAND}}`.
-->

# Debug UI tests

Diagnose a failing or unstable UI test. Produce a root-cause
classification and the minimal corrective action.

This skill is **framework-, language-, platform-, browser/device-, and
CI-host-agnostic**. It reads whatever artifacts your UI runner already
produces (see customization points 1, 3, 4 above).

## Pre-conditions

- A failing or unstable UI test is identified (path, fully-qualified
  name, or runner-native selector).
- The runner produces at least one of: structured failure output,
  screenshot / video / trace, DOM snapshot, or console / device log.
- Run history is reachable via `flake_analysis.results_store` OR the
  user is prepared to paste it manually.

## Inputs you must collect

- **Failing test identifier** — required.
- **Recent run history** — last N runs (default 5), pulled from
  `flake_analysis.results_store`. If unavailable, ask the user to
  paste; note the gap in the report.
- **Artifact set for the latest failure** — screenshots, video, trace,
  DOM snapshot, console / device logs. Fetch from
  `ui_debug.artifact_sources`.
- **Tracker reference** when the test carries a traceability comment
  (see `traceability.marker_style`) — preserve it on any edit.

## Procedure

1. **Pull the test file and the failing assertion / error.** Capture
   the full failure signature (stack, message, screenshot reference,
   trace reference, browser / device, runner version, last green
   commit).

2. **Pull the last N runs** from `flake_analysis.results_store`
   (default 5). Note the pass/fail pattern, the commit SHA range, and
   any environment dimension that correlates (branch, browser, device,
   shard, runner, time of day).

3. **Classify the failure** into exactly one of four universal
   categories:
   - **Flaky** — passes/fails non-deterministically on the same code.
     Likely causes: timing, animations, race conditions, shared state,
     hard sleeps, network/data variability, viewport / device variance.
   - **Brittle** — passes today but breaks on minor UI changes. Likely
     causes: fragile selectors (CSS path, nth-child, generated IDs),
     hard-coded test data, environment coupling, locale / timezone
     coupling.
   - **Broken** — test logic itself is incorrect or outdated. The
     assertion no longer matches the intended behavior.
   - **Regression** — the test is correct; production code broke the
     contract the test encodes.

4. **For flaky** — propose a minimal test-side fix:
   - replace hard sleeps with framework-native waits / retry-ability
     (per `ui_debug.wait_policy`)
   - isolate shared state (fresh fixtures, per-test data factory,
     storage reset)
   - stabilize ordering (no inter-test dependency)
   - if the root cause is genuinely a product timing bug, escalate as
     **Regression** instead

5. **For brittle** — propose selector / data hardening:
   - migrate the selector to the policy in `ui_debug.selector_policy`
   - replace hard-coded data with factories / deterministic seeds (see
     `generate-test-data`)
   - decouple from environment-specific text where possible

6. **For broken** — surface the assertion drift; propose the updated
   expectation, citing the work item or PR that changed the intended
   behavior. Do **not** simply re-record golden values to "make it
   pass" — confirm the new behavior is correct first.

7. **For regression — STOP.** Escalate to the developer with the
   evidence chain. Do **not** patch production code under any maturity
   tier. Do **not** weaken the assertion to mask the regression.

8. **Emit a debug report** containing:
   - failure signature (stack, screenshots / trace references, env)
   - run-history slice with the correlation dimension
   - classification + confidence + reasoning
   - artifact links (screenshots, video, trace, DOM)
   - recommended corrective action (test edit OR escalation)
   - tracker reference preserved from the test header

## Stop conditions

- Classification cannot be determined with confidence — surface the
  ambiguity to the user; recommend additional artifacts (more runs,
  trace, video) before acting.
- A **regression** is detected — escalate; do **not** patch production
  code.
- The proposed fix would weaken the assertion's intent (e.g. removing
  the failing check, broadening the matcher to swallow the defect) —
  refuse and surface as regression-class.
- The fix requires changes beyond the test file and approved fixtures
  — escalate.

## Governance

- **Never** modify production code from this skill. Regressions
  escalate. This is non-negotiable across all maturity tiers.
- **Never** silently skip, quarantine, or `@Ignore` a test. Quarantine
  is containment, not a fix — it requires human sign-off, an owner,
  and an expiry recorded in the report (see
  `flake_analysis.quarantine_workflow`).
- **Never** re-record a golden / snapshot value to mask a real
  behavior change — confirm intent first, cite the work item.
- Selector and wait edits must conform to
  `ui_debug.selector_policy` and `ui_debug.wait_policy`.
- The blameless principle applies: classify the failure, don't blame
  the author.

## Output

A `ui-debug-report.md` artifact (or the path configured in
`.assert-iq/config.yaml > ui_debug.report_path`) with the
classification, evidence, and recommended action — plus the corrected
test file(s) when the proposed fix is test-side.

## Signals emitted

When the QI signal sink is wired, this skill emits a `test.ui_debug`
signal per run conforming to `.assert-iq/signal-schema.json`, carrying:
`test_id`, `framework`, `classification`
(`flaky` | `brittle` | `broken` | `regression`), `confidence`,
`history_window`, `correlation_dimension`, `action`
(`test_fix` | `escalate` | `await_artifacts`), `selector_changes`,
`wait_changes`, and `tracker_ref`.
