# Assert.IQ Agent Pack — File Manifest

**Version**: v0.9.0
**Generated**: 2026-05-20
**Total files (top-level inventory)**: 53 + hooks tree + tests scaffolding

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
| 4a | `.assert-iq/.install-manifest.json` | **Generated at bootstrap time.** Records `{version, installed_at, mode, paths[]}` for the install. Trial mode uses this to wire `.git/info/exclude`; `--graduate` flips `mode` to `committed`. |
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
| 33a | `.github/skills/assert-iq-bootstrap/SKILL.md` | Skill: `/assert-iq-bootstrap` — cross-platform bootstrap for new workspaces. Three install modes (`trial` / `committed` / `ask`), per-file conflict resolver with SHA256 fast-path, manifest tracking, `--graduate` to reverse trial mode. |
| 34 | `.vscode/mcp.json` | MCP wiring for 20 servers: GitHub, ADO, Jira/Atlassian, git, GitLab, Bitbucket, filesystem, Postgres, SQLite, AWS, Sentry, Grafana, Datadog, Honeycomb, Playwright, Puppeteer, Notion, Confluence, Slack, Teams. All credentials via `${input:…}` prompts — file is safe to commit. |
| 34a | `.vscode/MCP.md` | Per-server setup guide: prerequisites (`uv`, `node`), VS Code quick start, Claude Code / Claude Desktop equivalents, credential sourcing, and troubleshooting for every MCP server in `mcp.json`. |
| 35 | `.vscode/settings.json` | VS Code config to wire skills/ into Copilot |
| 36 | `MANIFEST.md` | This file — full file listing, visible to all file browsers |
| 36a | `README.md` | Repo landing page ("Start Here"). QI overview, Assert.IQ pitch, three-step get-started, annotated directory tree, upgrade steps, and links to all deep-dive docs. Replaces the `.github/README.md` fallback GitHub previously displayed. |
| 37 | `README.assert-iq.md` | Full reference doc: detailed install options, drop-in / air-gapped path, skill reference, maturity tier matrix, MCP inventory, hooks architecture, release history. |
| 38 | `tests/_qi/automated/.gitkeep` | Placeholder so the empty test directory is preserved by git |
| 39 | `tests/_qi/exploratory/.gitkeep` | Placeholder so the empty test directory is preserved by git |
| 40 | `tests/_qi/manual/.gitkeep` | Placeholder so the empty test directory is preserved by git |
| 41 | `CLAUDE.md` | Claude Code entrypoint — mirrors Copilot guidance + `@`-imports scoped instructions |
| 42 | `AGENTS.md` | Generic agent-spec pointer (Codex CLI, Cursor, Aider) |
| 43 | `.claude/agents/assert-iq.md` | Claude Code default Assert.IQ subagent (mirror of Copilot Assert-IQ) |
| 43a | `.claude/agents/assert-iq-plan.md` | Claude Code planning sibling (mirror of Copilot Assert-IQ-PLAN) |
| 44 | `.claude/settings.json` | Claude Code settings — embeds hooks block (synced by installer) |
| 45 | `.claude/skills` | Symlink → `../.github/skills/` so Claude discovers the same skills as Copilot |
| 46 | `install.sh` | Bash installer — renders `hooks/hooks.json` from `hooks/hooks.template.json` (substitutes `__PACK_ROOT__` with the absolute pack path), syncs hooks into `.claude/settings.json`, creates skills symlink. Idempotent. |
| 47 | `install.ps1` | PowerShell installer — parity with `install.sh`. Doubles backslashes in the substituted path so the rendered JSON remains valid. |
| 47a | `scripts/bootstrap.sh` | Cross-platform bootstrap (macOS/Linux) invoked by `/assert-iq-bootstrap`. Flag-driven, idempotent. Supports `--mode={trial,committed,ask}`, `--graduate`, interactive conflict resolver, manifest tracking. |
| 47b | `scripts/bootstrap.ps1` | Cross-platform bootstrap (Windows) invoked by `/assert-iq-bootstrap`. PowerShell parity with `bootstrap.sh`: same flags (`-Mode`, `-Trial`, `-Committed`, `-Graduate`), same manifest format, same `.git/info/exclude` block. |
| 48 | `.github/vscode-readme.md` | Plain-language guide to the Copilot-side of the pack |
| 49 | `.claude/claude-readme.md` | Plain-language guide to the Claude-side of the pack |
| 50 | `.gitignore` | Excludes the rendered `hooks/hooks.json` from version control (per-machine artifact with an absolute path baked in). |
| 51 | `hooks/hooks.template.json` | **Committed source-of-truth** for the hooks configuration. Uses `${CLAUDE_PLUGIN_ROOT:-__PACK_ROOT__}` (bash) and `$env:CLAUDE_PLUGIN_ROOT ?? '__PACK_ROOT__'` (PowerShell) so the rendered output works in both Claude Code (env var wins) and VS Code Copilot (falls back to baked path). |
| — | `hooks/hooks.json` + `hooks/scripts/` | Hooks tree at pack root: `hooks/hooks.json` (**generated by the installer** from `hooks.template.json`; gitignored) + `hooks/scripts/` + `hooks/config/` + `hooks/state/` + `hooks/sessions/` + `hooks/logs/` |

---

**Pack root**: `assert-iq-agent-pack/`
**Skill count**: 23 (in `.github/skills/`)
**Instruction count**: 5 (in `.github/instructions/`)
**Agents (Copilot)**: 2 (in `.github/agents/`) — `Assert-IQ` (default), `Assert-IQ-PLAN` (planner)
**Subagents (Claude)**: 2 (in `.claude/agents/`) — `assert-iq`, `assert-iq-plan`
**Hooks**: SessionStart, PostToolUse, Stop (see `hooks/hooks.json`)

## Notes for v0.9.0

- **Workspace topology (split-repo support).** New `workspace:` block in
  `.assert-iq/config.yaml` introduces `role: monorepo | prod | tests`
  (default `monorepo`) plus an optional `companion_repo` sub-block
  (`path` / `remote` / `fetch: mcp | local_path | manual_paste` /
  `branch`). Lets teams whose tests live in a repo separate from their
  production code wire both halves together without forking the pack.
  Default `monorepo` is backward-compatible — single-repo users see
  zero behavioral change.
- **Centralized topology contract in qi-foundation.** New
  "Workspace topology — read first" section in
  `.github/instructions/qi-foundation.instructions.md` defines the
  fetch fallback chain (MCP → local path → manual paste) and the
  UNGRADED contract: when the companion is unset or unreachable, the
  affected signal layer is reported as UNGRADED with
  `reason: "companion_repo_unset"` (or `"companion_repo_unreachable"`)
  per the v0.2 signal-schema `partial_signal_mode: true` rule — never
  silently fabricated.
- **Seven skills made workspace-aware.** Each of `risk-assess-pr`,
  `check-merge`, `release-confidence`, `code-review`,
  `check-test-coverage`, `generate-traceability-matrix`, and
  `analyze-escaped-defect` gained a new customization point that
  names which layer / source degrades to UNGRADED when the companion
  is missing. The full rule lives in qi-foundation; the skills carry
  short pointers, so the contract is not duplicated.
- **Five Whys discipline across diagnostic skills (post-v0.8 commit
  d9bbaee).** `debug-ui-tests`, `analyze-flaky-test`, and
  `analyze-escaped-defect` now enforce a mandatory Five Whys chain
  with evidence required at every link, runaway guard (`max_depth`
  default 7), and a user-gated Anti-Patterns appendix for cumulative
  learning. Configuration knobs under `ui_debug.five_whys`,
  `flake_analysis.five_whys`, and `escape_analysis.five_whys`.
- **Tool entrypoint callouts.** `.github/copilot-instructions.md` and
  `CLAUDE.md` gained parallel "Workspace awareness" sections (mirroring
  the existing "Maturity awareness" pattern) so both Copilot and
  Claude Code surface the topology rule on every interaction.
- **README onboarding step added.** New Step 5 in `README.md` —
  "Pick your workspace topology" — with a three-row setup table
  (monorepo / prod / tests) and a pointer to multi-root VS Code
  workspaces for split-repo teams who want both halves open at once.
- **Version metadata bumped to 0.9.0** in `.claude-plugin/plugin.json`,
  `.claude-plugin/marketplace.json`, `MANIFEST.md`, `README.md`, and
  `README.assert-iq.md` (version banner, install pins, history row).

## Notes for v0.8.0

- **Expanded MCP server catalog.** `.vscode/mcp.json` grew from 3 servers
  (GitHub, ADO, Atlassian) to 20. The 17 additions cover local git
  operations, GitLab, Bitbucket, filesystem access, Postgres, SQLite, AWS
  (AWS Labs server via `uvx`), Sentry, Grafana, Datadog, Honeycomb,
  Playwright, Puppeteer, Notion, Confluence, Slack, and Microsoft Teams.
  All secrets remain outside the file — every credential is routed through
  a VS Code `${input:…}` promptString with `"password": true`, storing
  values in the OS keychain on first use.
- **`.vscode/MCP.md` setup guide.** New file documenting prerequisites,
  VS Code quick start, Claude Code / Claude Desktop equivalents, and a
  per-server card for all 20 entries (what it does, what credentials you
  need, where to get them, troubleshooting).
- **Root `README.md` landing page.** The repo previously had no root
  `README.md`; GitHub fell back to `.github/README.md`. A new root
  `README.md` serves as the directional "Start Here" entry point: QI
  four-layer model overview, Assert.IQ pitch, and a five-step get-started
  guide (install → bootstrap → wire MCP → customize config.yaml → run a
  skill). All deep-dive content deferred to `README.assert-iq.md` and the
  tool-specific READMEs.
- **`.github/README.md` → `.github/vscode-readme.md`** and
  **`.claude/README.md` → `.claude/claude-readme.md`** — renamed so the
  root `README.md` is unambiguously the landing page and GitHub stops
  using the `.github/` fallback. All cross-references updated.
- **Version metadata bumped to 0.8.0** in `.claude-plugin/plugin.json`,
  `.claude-plugin/marketplace.json`, `MANIFEST.md`, and
  `README.assert-iq.md` (version banner, install pins, history row).

## Notes for v0.7.0-pre

- **Portable hooks fix.** VS Code Copilot does not propagate
  `CLAUDE_PLUGIN_ROOT` (or any workspace path) to hook commands, so the
  previous `${CLAUDE_PLUGIN_ROOT}`-based shape resolved to
  `/hooks/scripts/<name>.sh` under Copilot and produced a
  `chmod: No such file or directory` warning at every Stop event.
  Resolved via **install-time path injection**: `hooks/hooks.template.json`
  is the committed source with a `__PACK_ROOT__` sentinel, and
  `install.sh` / `install.ps1` render `hooks/hooks.json` with the
  absolute pack root baked in. The rendered command uses
  `${CLAUDE_PLUGIN_ROOT:-<baked path>}` so Claude Code still wins via
  env var when set. Each hook command also gained a `Test-Path` /
  `[ -f ]` guard so a missing script fails silently instead of erroring.
  **Operational note:** re-run the installer after moving or renaming
  the pack on disk.
- **PowerShell hook syntax fixed.** Windows hook commands now use
  `powershell -NoProfile -ExecutionPolicy Bypass -Command "& { ... }"`
  with `$env:CLAUDE_PLUGIN_ROOT`. The previous `-File` +
  `%CLAUDE_PLUGIN_ROOT%\...` form silently broke when VS Code spawned
  PowerShell directly (cmd-style `%VAR%` expansion requires cmd.exe in
  the pipeline).
- **Universalized `hooks/config/`.** `skill-improve.config.json`
  defaults shrunk to a single generic `customization_roots` entry
  (`~/.agents/skills`) — no more MDA-specific paths. `hooks/config/README.md`
  rewritten so every example uses `<pack-root>/hooks/...` or generic
  `~/code/my-app/...` placeholders and every command shows both bash
  and PowerShell forms.

## Notes for v0.6.0

- **Now installable as a cross-tool plugin** using the Claude plugin
  format (`.claude-plugin/plugin.json` + `hooks/hooks.json`). VS Code
  Copilot auto-detects this layout, so a single install path works for
  both Copilot and Claude Code.
- **Portable hook scripts.** ~~Hook commands in `hooks/hooks.json` use
  `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/...` (and `%CLAUDE_PLUGIN_ROOT%`
  for Windows), so the bundled scripts work out-of-the-box from
  whichever directory the plugin manager installs into — no more
  hardcoded `$HOME/.agents/...` paths.~~ **Superseded in v0.7.0-pre** —
  see above; the env-var-only approach broke under VS Code Copilot.
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
