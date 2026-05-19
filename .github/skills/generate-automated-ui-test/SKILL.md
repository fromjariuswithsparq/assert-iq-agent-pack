---
name: generate-automated-ui-test
mode: agent
description: "Generate UI tests for a workflow — Page Object Model, stable selectors, explicit waits."
---

# Generate automated UI test

Produce UI tests in the project's framework (Playwright / Cypress / Selenium /
WebDriverIO per config). UI tests are expensive — design for stability.

## Inputs

- Workflow: user journey or AC reference.
- Framework: read from `.assert-iq/config.yaml`.

## Procedure

1. Identify the user journey. Map it to: pages visited, actions taken,
   assertions at each meaningful state.
2. Apply the project's existing Page Object pattern. If none exists, propose
   one before generating tests; do not invent silently.
3. Selector strategy in priority order:
   - `data-testid` or equivalent project convention
   - Accessible role + name (ARIA)
   - Visible text (only for stable copy)
   - Avoid: CSS structure, nth-child, brittle XPath
4. Wait strategy:
   - Use the framework's auto-wait or explicit-wait idiom.
   - No hard sleeps. No arbitrary timeouts unless documented and justified.
5. Test data:
   - Use the project's test data factory.
   - Each test sets up and tears down its own state. No shared mutable state.
6. Cover: happy path, one negative path, one boundary case per AC.
7. Apply `qi-test-design.instructions.md` rules; include `@qi-trace` header.

## Governance

- Do not run UI tests against production endpoints.
- Do not commit credentials. Use the project's secret management.
- If a stable selector cannot be found, surface a recommendation to add a
  `data-testid` rather than fall back to a brittle selector.
