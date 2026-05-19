---
applyTo: "**"
description: "QI foundation — applied to every interaction in this repository."
---

# QI foundation instruction

**When this applies:** every interaction in this repository (Copilot loads via
`applyTo: "**"`; Claude Code treats this as always-on baseline guidance via
`CLAUDE.md`).

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
