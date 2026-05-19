# Assert.IQ / Quality Intelligence — Claude Code entrypoint

This repository is governed by the Quality Intelligence (QI) operating model.
QI is the strategic frame; Assert.IQ is the accelerator. This file is the
Claude Code counterpart to `.github/copilot-instructions.md` — same rules,
delivered through Claude's native config surface.

## Core principles you must apply on every interaction

1. Quality = Velocity × Customer Satisfaction × System Resilience.
2. Reason about quality through the four-layer signal model:
   - Change risk
   - Protection strength
   - Signal trustworthiness
   - Outcome evidence

   These combine into Decision Confidence. Never reduce a release decision
   to a single number.
3. Distinguish a metric (what happened) from a signal (decision-grade evidence).
4. Treat AI-generated code and tests as drafts. A human review gate is
   mandatory before merge. Surface assumptions explicitly.
5. Honor the client's existing test framework, branching model, and tracking
   system. Do not introduce new dependencies without explicit confirmation.

## Maturity awareness

Read `.assert-iq/maturity-profile.md` before acting (or
`~/.assert-iq/maturity-profile.md` as a user-global fallback). Behavior
changes by tier:

- **Early**: foundation + traceability + manual generation only. Agentic
  Healing disabled.
- **Mid**: add risk assessment + automated test generation. Healing operates
  in suggest-only mode.
- **Higher**: full pack, including autonomous healing within configured retry
  bounds.

## Governance you must enforce

- Every generated test must include a traceability comment linking to the
  source work item (ADO ID or Jira key).
- Every healed test must record the failure signature and the fix rationale.
- No prompt may exfiltrate code, secrets, or proprietary data outside the
  IDE/CI boundary.
- If a request would violate the client's compliance posture documented in
  `.assert-iq/governance.md` (or `~/.assert-iq/governance.md` as a
  user-global fallback), refuse and explain.

## Output standards

- Cite the work item, file path, and signal layer when producing artifacts.
- Provide a brief Recommendation, Next Steps, Owners, Timeline section on
  multi-step deliverables.
- Prefer paraphrase and synthesis over copy-paste from external sources.

## Scoped guidance (load when relevant)

Copilot loads these automatically through their `applyTo` frontmatter globs.
In Claude Code, treat them as scope-conditional guidance — read the file
referenced below when the user's task matches the "When this applies" header
inside each file.

- @.github/instructions/qi-foundation.instructions.md — **always-on**;
  baseline reasoning order for any quality/testing/release/risk question.
- @.github/instructions/qi-traceability.instructions.md — apply when adding
  or modifying production C# / XAML code (`**/*.{cs,xaml}`) tied to a work
  item.
- @.github/instructions/qi-test-design.instructions.md — apply when working
  with automated tests (`tests/**`, `*Test.*`, `*.test.*`, `*.spec.*`).
- @.github/instructions/qi-manual-test-design.instructions.md — apply when
  authoring manual test cases or exploratory charters under
  `tests/_qi/manual/**` or `tests/_qi/exploratory/**`.
- @.github/instructions/qi-signal-emission.instructions.md — apply when
  editing CI configuration (GitHub Actions, Azure Pipelines, GitLab CI,
  Jenkinsfile).

## Capabilities surface

- **Subagents** — `.claude/agents/assert-iq.md` (default Assert.IQ
  subagent, full tools) and `.claude/agents/assert-iq-plan.md`
  (read-only planning sibling).
- **Skills** — `.github/skills/` (canonical) is mirrored at `.claude/skills`
  so Claude auto-discovers all 22 QI skills (code review, test generation,
  bug reports, traceability matrix, release confidence, etc.).
- **Hooks** — wired through `.claude/settings.json`, sourced from
  `hooks/hooks.json` (Claude plugin format). Run `bash install.sh` (or `install.ps1` on
  Windows) after dropping the pack into a repo to sync hooks and create the
  skills symlink.
- **Per-client config** — `.assert-iq/config.yaml`,
  `.assert-iq/governance.md`, `.assert-iq/maturity-profile.md`,
  `.assert-iq/signal-schema.json`.

## Companion files

- `.github/copilot-instructions.md` — the Copilot-side equivalent of this
  file. If you change behavior here, update the Copilot file too (or vice
  versa) to keep tools in lockstep.
- `AGENTS.md` — generic agent-spec pointer for non-Copilot, non-Claude
  tooling (Codex CLI, Cursor, Aider).
