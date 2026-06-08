---
applyTo: "**"
description: "QI foundation — applied to every interaction in this repository."
---

# QI foundation instruction

**When this applies:** every interaction in this repository. This file is the
single shared rulebook for both Copilot (loaded via `applyTo: "**"`) and
Claude Code (loaded via `@.github/instructions/qi-foundation.instructions.md`
in `CLAUDE.md`).

## Always-on rules (Copilot + Claude)

### Core principles

1. Quality = Velocity × Customer Satisfaction × System Resilience.
2. Reason about quality through the four-layer signal model — Change risk,
   Protection strength, Signal trustworthiness, Outcome evidence — and
   synthesize Decision Confidence. Never reduce a release decision to a
   single number.
3. Distinguish a metric (what happened) from a signal (decision-grade evidence).
4. AI-generated code and tests are drafts. A human review gate is mandatory
   before merge. Surface assumptions explicitly.
5. Honor the client's existing test framework, branching model, and tracking
   system. Do not introduce new dependencies without explicit confirmation.

### Maturity awareness

Read `.assert-iq/maturity-profile.md` before acting (or
`~/.assert-iq/maturity-profile.md` as a user-global fallback). Behavior
changes by tier:

- **Early** — foundation + traceability + manual generation only. Agentic
  Healing disabled.
- **Mid** — add risk assessment + automated test generation. Healing operates
  in suggest-only mode.
- **Higher** — full pack, including autonomous healing within configured retry
  bounds.

### Governance you must enforce

- Every generated test must include a traceability comment linking to the
  source work item (ADO ID or Jira key).
- Every healed test must record the failure signature and the fix rationale.
- No prompt may exfiltrate code, secrets, or proprietary data outside the
  IDE / CI boundary.
- If a request would violate `.assert-iq/governance.md` (or
  `~/.assert-iq/governance.md` as a user-global fallback), refuse and explain.

### Output standards

- Cite the work item, file path, and signal layer when producing artifacts.
- Provide a brief Recommendation, Next Steps, Owners, Timeline section on
  multi-step deliverables.
- Prefer paraphrase and synthesis over copy-paste from external sources.

## Workspace topology — read first

Before reasoning about any of the four signal layers, read
`.assert-iq/config.yaml > workspace.role`. The default is `monorepo` —
production code and tests live in this workspace; no cross-repo behavior
activates and every skill behaves exactly as it did before topology was
introduced.

When `workspace.role` is `prod` or `tests`, this workspace holds only one
half. Read `.assert-iq/workspace-topology.md` for the full contract:
which signals fetch from `workspace.companion_repo`, the MCP → local path
→ manual paste fallback chain, and the **UNGRADED** rules
(`reason: "companion_repo_unset"` / `"companion_repo_unreachable"` under
v0.2 signal schema `partial_signal_mode: true`). Never fabricate a missing
signal. State the gap and continue with the remaining layers.

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
