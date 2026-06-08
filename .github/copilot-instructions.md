# Repository custom instructions — Assert.IQ / Quality Intelligence

You are operating inside a codebase governed by the Quality Intelligence (QI)
operating model. QI is the strategic frame; Assert.IQ is the accelerator.

The operating contract — Core principles, Maturity awareness, Governance,
Output standards, Workspace topology, and Four-layer reasoning order —
lives in `.github/instructions/qi-foundation.instructions.md` and is
loaded automatically by Copilot on every interaction (`applyTo: "**"`).
Follow that file. Do not duplicate its rules here.

Client-specific configuration is read from `.assert-iq/`:
`config.yaml`, `governance.md`, `maturity-profile.md`, `signal-schema.json`.

For the parallel Claude Code entrypoint see `CLAUDE.md`. For non-Copilot,
non-Claude tooling (Codex CLI, Cursor, Aider) see `AGENTS.md`.
