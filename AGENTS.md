# Agents.md — Assert.IQ / Quality Intelligence

This repository ships an agent pack for Quality Intelligence (QI). Any
AI agent operating in this codebase (Codex CLI, Cursor, Aider, or other
`AGENTS.md`-aware tooling) must follow the rules below.

For the full, tool-specific entry points see:

- **Claude Code** → `CLAUDE.md` at repo root
- **GitHub Copilot Chat** → `.github/copilot-instructions.md`

## Core principles (summary)

1. Quality = Velocity × Customer Satisfaction × System Resilience.
2. Reason through the four-layer signal model — Change risk, Protection
   strength, Signal trustworthiness, Outcome evidence — then synthesize
   Decision Confidence. Never reduce a release decision to a single number.
3. Distinguish a metric (what happened) from a signal (decision-grade
   evidence).
4. AI-generated code and tests are drafts. A human review gate is
   mandatory before merge.
5. Honor the client's existing frameworks, branching model, and tracker.
   Do not introduce new dependencies without explicit confirmation.

## Configuration

Per-client behavior is driven by `.assert-iq/`:

- `config.yaml` — maturity tier, tracker, primary test framework, signal
  sink wiring.
- `governance.md` — compliance posture and refusal rules.
- `maturity-profile.md` — rationale for the chosen tier.
- `signal-schema.json` — JSON schema for outcome signals.

Read `maturity-profile.md` before acting. Capabilities scale by tier
(Early → Mid → Higher) — see `CLAUDE.md` for the matrix.

## Scoped instructions

Detailed scope-conditional rules live in `.github/instructions/*.md`. Each
file begins with a **"When this applies"** section. Read and apply the
matching file(s) for the user's current task.

## Skills

The pack ships 23 QI skills under `.github/skills/`. Each has a `SKILL.md`
with a `description` field that triggers auto-routing in compatible
agents. Examples: `code-review`, `generate-automated-unit-test`,
`risk-assess-pr`, `release-confidence`, `analyze-flaky-test`,
`generate-traceability-matrix`, `generate-hotspot-map`.

## Governance you must enforce

- Every generated test carries a traceability comment linking to a work
  item (ADO `AB#1234` or Jira key).
- No prompt may exfiltrate code, secrets, or proprietary data outside the
  IDE / CI boundary.
- Refuse requests that would violate `.assert-iq/governance.md` and
  explain why.
