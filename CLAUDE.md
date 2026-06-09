# Assert.IQ / Quality Intelligence — Claude Code entrypoint

This repository is governed by the Quality Intelligence (QI) operating model.
QI is the strategic frame; Assert.IQ is the accelerator. This file is the
Claude Code counterpart to `.github/copilot-instructions.md`.

## Operating contract — load first

The shared rulebook (Core principles, Maturity awareness, Governance,
Output standards, Workspace topology, Four-layer reasoning order) lives
in `@.github/instructions/qi-foundation.instructions.md`. That file is
the single source of truth for both Copilot and Claude Code — read it
at the start of every interaction. Do not duplicate its rules here.

Client-specific configuration is read from `.assert-iq/`: `config.yaml`,
`governance.md`, `maturity-profile.md`, `signal-schema.json`.

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
  so Claude auto-discovers all 26 QI skills (code review, test generation,
  bug reports, traceability matrix, release confidence, hotspot map, etc.).
- **Hooks** — wired through `.claude/settings.json`, sourced from
  `hooks/hooks.json` (Claude plugin format). Run `bash install.sh` (or `install.ps1` on
  Windows) after dropping the pack into a repo to sync hooks and create the
  skills symlink.
- **Per-client config** — `.assert-iq/config.yaml`,
  `.assert-iq/governance.md`, `.assert-iq/maturity-profile.md`,
  `.assert-iq/signal-schema.json`.
- **Workspace bootstrap** — `scripts/bootstrap.sh` /
  `scripts/bootstrap.ps1`, invoked by the `/assert-iq-bootstrap` skill.
  Three install modes:
  - `--mode=committed` — files visible to git (team adoption).
  - `--mode=trial` — files added to `.git/info/exclude` (local-only;
    the codebase `.gitignore` is **never** touched). User graduates
    later with `scripts/bootstrap.sh --graduate`.
  - `--mode=ask` (default in TTY) — interactive prompt.
  Pre-existing user files are preserved via SHA256 compare + interactive
  conflict resolver. Every install records
  `.assert-iq/.install-manifest.json` (version, mode, paths).

## Companion files

- `.github/copilot-instructions.md` — the Copilot-side equivalent of this
  file. If you change behavior here, update the Copilot file too (or vice
  versa) to keep tools in lockstep.
- `AGENTS.md` — generic agent-spec pointer for non-Copilot, non-Claude
  tooling (Codex CLI, Cursor, Aider).
