---
applyTo: "**"
description: "QI foundation — applied to every interaction in this repository."
---

# QI foundation instruction

**When this applies:** every interaction in this repository (Copilot loads via
`applyTo: "**"`; Claude Code treats this as always-on baseline guidance via
`CLAUDE.md`).

## Workspace topology — read first

Before reasoning about any of the four signal layers, read
`.assert-iq/config.yaml > workspace.role`. This determines which signals
you can see directly versus which must be fetched from a companion
workspace.

- **`monorepo`** (default; also applies when the block is absent) —
  production code and tests live in this workspace. Proceed with the
  four-layer reasoning below using normal repo lookups. No cross-repo
  behavior is activated.
- **`prod`** — this workspace holds production code; tests live in
  `workspace.companion_repo`. When a skill needs test-side signals
  (Protection layer coverage / test discovery, Trust layer flake
  history, traceability test references), fetch them via the companion.
- **`tests`** — this workspace holds the test suite; production code
  lives in `workspace.companion_repo`. When a skill needs prod-side
  signals (Change layer diff / blast radius, the code under review, the
  introducing commit for an escape, traceability code references), fetch
  them via the companion.

### Fetch fallback chain

When `companion_repo.fetch` is set, follow that single mode. When unset,
walk this chain and stop at the first that responds:

1. **MCP** — the configured VCS MCP server (`github`, `azure-devops`,
   `gitlab`, etc.) reads `companion_repo.remote`.
2. **Local path** — if `companion_repo.path` resolves to a checkout on
   disk, read files directly.
3. **Manual paste** — ask the user to paste the specific artifact needed
   (diff, coverage report, file contents). Document the gap in the
   resulting report.

### When the companion is needed but absent

If `workspace.role` is `prod` or `tests` and `companion_repo` is unset
(or all fetch attempts fail), the affected layer or signal source is
**UNGRADED** with `reason: "companion_repo_unset"` (or
`"companion_repo_unreachable"`). This is a first-class outcome under the
v0.2 signal schema (`partial_signal_mode: true`).

Do **not** fabricate the missing signal. Do **not** infer test coverage
from a prod-only checkout, or change risk from a tests-only checkout.
State the gap and continue with the remaining layers.

The `monorepo` default exists so single-repo users incur zero overhead
from this section — in that mode every skill behaves exactly as it did
before workspace topology was introduced.

## Four-layer reasoning order

When the user asks any quality, testing, release, or risk question, you must
reason in this order:

1. **What changed?** (Change risk)
   - Inspect git diff scope, files touched, services impacted.
   - Flag late-breaking changes, churn concentration, and dependency reach.

2. **What protects this?** (Protection strength)
   - Identify covering tests in `tests/**`.
   - Check requirement-to-test traceability comments.
   - Note coverage gaps on impacted areas.

3. **Can we trust the signals?** (Signal trustworthiness)
   - Check flake history, blocked tests, environment notes.
   - Flag tests that have been skipped or quarantined recently.

4. **What do outcomes say?** (Outcome evidence)
   - Surface recent escaped defects on touched components.
   - Pull telemetry signals if MCP exposes them.

5. **What is the decision?** (Decision confidence)
   - Synthesize the above into Release / Mitigate / Hold guidance.
   - Always include explicit assumptions and what would change the verdict.

You may not assert "this is safe to ship" without all four layers being
addressed. If a layer cannot be evaluated, say so explicitly.
