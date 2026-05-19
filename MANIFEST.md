# Assert.IQ Agent Pack — File Manifest

**Version**: v0.6.0
**Generated**: 2026-05-18
**Total files (top-level inventory)**: 49 + hooks tree + tests scaffolding

---

## Why this manifest exists

This pack uses dot-prefixed directories — `.github/`, `.vscode/`, `.assert-iq/` —
which are conventional locations for tooling configuration. **macOS Finder and
Windows Explorer hide dot-prefixed directories by default.** If you extracted
this pack and only see `README.assert-iq.md` and the `tests/` folder, the rest
is there — your file browser is filtering it.

**To show hidden files:**
- macOS Finder: press `Cmd + Shift + .`
- Windows Explorer: View tab → check **Hidden items**
- VS Code: hidden files are visible by default — open the pack folder in VS Code to see everything
- Terminal: `ls -la` shows everything

## Full file inventory

| # | Path | Purpose |
|---|---|---|
| 1 | `.assert-iq/config.yaml` | Per-client configuration (maturity, tracker, framework, etc.) |
| 2 | `.assert-iq/governance.md` | Compliance posture and refusal rules — fill in per client |
| 3 | `.assert-iq/maturity-profile.md` | QI maturity tier rationale — fill in per client |
| 4 | `.assert-iq/signal-schema.json` | JSON schema for the QI outcome signal payload |
| 5 | `.claude-plugin/plugin.json` | Plugin manifest (Claude plugin format) — makes the pack installable as a cross-tool plugin in VS Code Copilot and Claude Code. Uses `${CLAUDE_PLUGIN_ROOT}` for portable hook paths. |
| 5a | `.github/agents/Assert-IQ.agent.md` | Default front-door agent (Copilot) — full tools, routes to skills |
| 5b | `.github/agents/Assert-IQ-PLAN.agent.md` | Read-only planning sibling (Copilot) — ends with Start Implementation handoff to Assert-IQ |
| 6 | `.github/copilot-instructions.md` | Always-on QI guidance loaded by Copilot |
| 7 | `.github/instructions/qi-foundation.instructions.md` | Instruction file (auto-loaded by Copilot via `applyTo` glob) |
| 8 | `.github/instructions/qi-manual-test-design.instructions.md` | Instruction file (auto-loaded by Copilot via `applyTo` glob) |
| 9 | `.github/instructions/qi-signal-emission.instructions.md` | Instruction file (auto-loaded by Copilot via `applyTo` glob) |
| 10 | `.github/instructions/qi-test-design.instructions.md` | Instruction file (auto-loaded by Copilot via `applyTo` glob) |
| 11 | `.github/instructions/qi-traceability.instructions.md` | Instruction file (auto-loaded by Copilot via `applyTo` glob) |
| 12 | `.github/skills/agentic-heal/SKILL.md` | Skill: `/agentic-heal` |
| 13 | `.github/skills/analyze-escaped-defect/SKILL.md` | Skill: `/analyze-escaped-defect` |
| 14 | `.github/skills/analyze-flaky-test/SKILL.md` | Skill: `/analyze-flaky-test` |
| 15 | `.github/skills/check-merge/SKILL.md` | Skill: `/check-merge` |
| 16 | `.github/skills/check-test-coverage/SKILL.md` | Skill: `/check-test-coverage` |
| 17 | `.github/skills/code-review/SKILL.md` | Skill: `/code-review` |
| 18 | `.github/skills/debug-ui-tests/SKILL.md` | Skill: `/debug-ui-tests` |
| 19 | `.github/skills/generate-automated-api-test/SKILL.md` | Skill: `/generate-automated-api-test` |
| 20 | `.github/skills/generate-automated-ui-test/SKILL.md` | Skill: `/generate-automated-ui-test` |
| 21 | `.github/skills/generate-automated-unit-test/SKILL.md` | Skill: `/generate-automated-unit-test` |
| 22 | `.github/skills/generate-bug-report/SKILL.md` | Skill: `/generate-bug-report` |
| 23 | `.github/skills/generate-exploratory-charter/SKILL.md` | Skill: `/generate-exploratory-charter` |
| 24 | `.github/skills/generate-manual-test-case/SKILL.md` | Skill: `/generate-manual-test-case` |
| 25 | `.github/skills/generate-test-data/SKILL.md` | Skill: `/generate-test-data` |
| 26 | `.github/skills/generate-test-plan/SKILL.md` | Skill: `/generate-test-plan` |
| 27 | `.github/skills/generate-tests-from-ac/SKILL.md` | Skill: `/generate-tests-from-ac` |
| 28 | `.github/skills/generate-traceability-matrix/SKILL.md` | Skill: `/generate-traceability-matrix` |
| 29 | `.github/skills/new-pull-request/SKILL.md` | Skill: `/new-pull-request` |
| 30 | `.github/skills/release-confidence/SKILL.md` | Skill: `/release-confidence` |
| 31 | `.github/skills/review-acceptance-criteria/SKILL.md` | Skill: `/review-acceptance-criteria` |
| 32 | `.github/skills/review-test-quality/SKILL.md` | Skill: `/review-test-quality` |
| 33 | `.github/skills/risk-assess-pr/SKILL.md` | Skill: `/risk-assess-pr` |
| 33a | `.github/skills/assert-iq-bootstrap/SKILL.md` | Skill: `/assert-iq-bootstrap` — cross-platform bootstrap for new workspaces (workspace / user-global / skip per surface, `solo` and `pod` presets) |
| 34 | `.vscode/mcp.json` | MCP wiring for ADO / Jira / GitHub |
| 35 | `.vscode/settings.json` | VS Code config to wire skills/ into Copilot |
| 36 | `MANIFEST.md` | This file — full file listing, visible to all file browsers |
| 37 | `README.assert-iq.md` | Day-one onboarding doc for client engineers and Sparq pods |
| 38 | `tests/_qi/automated/.gitkeep` | Placeholder so the empty test directory is preserved by git |
| 39 | `tests/_qi/exploratory/.gitkeep` | Placeholder so the empty test directory is preserved by git |
| 40 | `tests/_qi/manual/.gitkeep` | Placeholder so the empty test directory is preserved by git |
| 41 | `CLAUDE.md` | Claude Code entrypoint — mirrors Copilot guidance + `@`-imports scoped instructions |
| 42 | `AGENTS.md` | Generic agent-spec pointer (Codex CLI, Cursor, Aider) |
| 43 | `.claude/agents/assert-iq.md` | Claude Code default Assert.IQ subagent (mirror of Copilot Assert-IQ) |
| 43a | `.claude/agents/assert-iq-plan.md` | Claude Code planning sibling (mirror of Copilot Assert-IQ-PLAN) |
| 44 | `.claude/settings.json` | Claude Code settings — embeds hooks block (synced by installer) |
| 45 | `.claude/skills` | Symlink → `../.github/skills/` so Claude discovers the same skills as Copilot |
| 46 | `install.sh` | Bash installer — syncs hooks into settings.json, creates skills symlink (idempotent) |
| 47 | `install.ps1` | PowerShell installer — parity with `install.sh` |
| 47a | `scripts/bootstrap.sh` | Cross-platform bootstrap (macOS/Linux) invoked by `/assert-iq-bootstrap`. Flag-driven, idempotent, skip-if-exists. |
| 47b | `scripts/bootstrap.ps1` | Cross-platform bootstrap (Windows) invoked by `/assert-iq-bootstrap`. PowerShell parity with `bootstrap.sh`. |
| 48 | `.github/README.md` | Plain-language guide to the Copilot-side of the pack |
| 49 | `.claude/README.md` | Plain-language guide to the Claude-side of the pack |
| — | `hooks/hooks.json` + `hooks/scripts/` | Hooks tree at pack root: `hooks/hooks.json` (Claude plugin format, paths use `${CLAUDE_PLUGIN_ROOT}`) + `hooks/scripts/` + `hooks/config/` + `hooks/state/` + `hooks/sessions/` + `hooks/logs/` |

---

**Pack root**: `assert-iq-agent-pack/`
**Skill count**: 23 (in `.github/skills/`)
**Instruction count**: 5 (in `.github/instructions/`)
**Agents (Copilot)**: 2 (in `.github/agents/`) — `Assert-IQ` (default), `Assert-IQ-PLAN` (planner)
**Subagents (Claude)**: 2 (in `.claude/agents/`) — `assert-iq`, `assert-iq-plan`
**Hooks**: SessionStart, PostToolUse, Stop (see `hooks/hooks.json`)

## Notes for v0.6.0

- **Now installable as a cross-tool plugin** using the Claude plugin
  format (`.claude-plugin/plugin.json` + `hooks/hooks.json`). VS Code
  Copilot auto-detects this layout, so a single install path works for
  both Copilot and Claude Code.
- **Portable hook scripts.** Hook commands in `hooks/hooks.json` use
  `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/...` (and `%CLAUDE_PLUGIN_ROOT%`
  for Windows), so the bundled scripts work out-of-the-box from
  whichever directory the plugin manager installs into — no more
  hardcoded `$HOME/.agents/...` paths.
- **Two agents replace the deprecated chat mode.** `Assert-IQ` is the
  default front door — full tools, skill routing, executes. `Assert-IQ-PLAN`
  is the read-only planning sibling — produces a plan and ends with a
  **Start Implementation** handoff button back to `Assert-IQ`. The old
  `.github/chatmodes/qi-advisor.chatmode.md` and
  `.claude/agents/qi-advisor.md` are removed.
- **Both Copilot agents reference the QI instruction files** via a
  `## QI guidance to consult` section so the agent knows where to look
  even when `applyTo` globs don't fire.
- **Caveat.** The plugin install carries skills, agents, hooks, and
  slash commands — but not `copilot-instructions.md`, `CLAUDE.md`,
  `AGENTS.md`, the file-scoped `.github/instructions/qi-*.instructions.md`
  files, or the per-client `.assert-iq/` config. **Run
  `/assert-iq-bootstrap` once per new workspace** to copy them into
  place — the skill walks the user through workspace / user-global /
  skip per surface, supports `solo` and `pod` presets, and is
  cross-platform (bash on macOS/Linux, PowerShell on Windows). Both
  READMEs document this and include uninstall steps.
- **User-global fallback for `.assert-iq/`.** All four agent files and
  both top-level instruction files (`copilot-instructions.md`,
  `CLAUDE.md`) now read `.assert-iq/maturity-profile.md` from the
  workspace first, then fall back to `~/.assert-iq/maturity-profile.md`
  — supporting contractors who rotate across many client repos.

## Notes for v0.5.0

- **Dual-target hooks**: VS Code Copilot and Claude Code share the same hook
  schema, so `.github/hooks/hooks.json` is the canonical source. The pack's
  `.vscode/settings.json` sets `chat.hookFilesLocations` to disable
  `.claude/settings.json` for Copilot, preventing double-fire when the
  installer mirrors hooks to the Claude side.
- **Cross-tool tool-name compat**: detection scripts
  (`skill-improve-detect.{sh,ps1}` and `lib/correction-signatures.{sh,ps1}`)
  recognize both VS Code names (`replace_string_in_file`,
  `multi_replace_string_in_file`, `create_file`, `read_file`) and Claude Code
  names (`Edit`, `MultiEdit`, `Write`, `Read`), so correction-signal
  detection works identically in either tool.

If any file listed here is missing after extraction, your archive tool
may have stripped dot-prefixed entries. Re-extract using `unzip` from the
command line, or use VS Code's built-in extraction.
