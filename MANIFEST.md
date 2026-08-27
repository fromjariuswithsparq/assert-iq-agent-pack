# Assert.IQ Agent Pack — File Manifest

**Version**: v2.1.1
**Generated**: 2026-08-11
**Total files (top-level inventory)**: 68 + dreaming tree + tests scaffolding (includes 8 specialist agents, measure-qi-impact skill, and business-metrics infrastructure)

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
| 4a | `.assert-iq/.install-manifest.json` | **Generated at bootstrap time.** Records `{version, installed_at, mode, paths[]}` for the install. Trial mode uses this to wire `.git/info/exclude`; `--graduate` flips `mode` to `committed`; `--uninstall` reads it to drive the reverse. |
| 5 | `VERSION` | Canonical pack version (read by `scripts/bootstrap.{sh,ps1}` when stamping the install manifest). |
| 5a | `.github/agents/Assert-IQ.agent.md` | Default front-door agent (Copilot) — full tools, routes to skills |
| 5b | `.github/agents/Assert-IQ-PLAN.agent.md` | Read-only planning sibling (Copilot) — ends with Start Implementation handoff to Assert-IQ |
| 5c | `.github/agents/specialists/*.agent.md` | **GENERATED — do not hand-edit.** 8 Copilot specialist agents rendered from `.claude/agents/specialists/*.md` by `scripts/sync-agents.{sh,ps1}`, with Claude→Copilot tool-name mapping. Freshness enforced by check P5 in `e2e-agent-parity.sh`. |
| 6 | `.github/copilot-instructions.md` | Always-on QI guidance loaded by Copilot |
| 7 | `.github/instructions/qi-foundation.instructions.md` | Instruction file (auto-loaded by Copilot via `applyTo` glob) |
| 8 | `.github/instructions/qi-manual-test-design.instructions.md` | Instruction file (auto-loaded by Copilot via `applyTo` glob) |
| 9 | `.github/instructions/qi-signal-emission.instructions.md` | Instruction file (auto-loaded by Copilot via `applyTo` glob) |
| 10 | `.github/instructions/qi-test-design.instructions.md` | Instruction file (auto-loaded by Copilot via `applyTo` glob) |
| 11 | `.github/instructions/qi-traceability.instructions.md` | Instruction file (auto-loaded by Copilot via `applyTo` glob) |
| 11a | `.github/instructions/qi-oracle.instructions.md` | Instruction file — Oracle layer rubrics and verdict weighting (v1.6.0+) |
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
| 33b | `.github/skills/generate-hotspot-map/SKILL.md` | Skill: `/generate-hotspot-map` — audits churn, structural complexity, and historical defect density to produce a Hotspot Risk Index registry consumed by `/risk-assess-pr`, `/check-test-coverage`, `/release-confidence`. Mid+ tier full registry; Early tier degrades to a churn-only Volatility Watchlist. |
| 33a | `.github/skills/assert-iq-bootstrap/SKILL.md` | Skill: `/assert-iq-bootstrap` — cross-platform bootstrap for new workspaces. Three install modes (`trial` / `committed` / `ask`), per-file conflict resolver with SHA256 fast-path, manifest tracking, `--graduate` to reverse trial mode. |
| 34 | `.vscode/mcp.json` | MCP wiring for 20 servers: GitHub, ADO, Jira/Atlassian, git, GitLab, Bitbucket, filesystem, Postgres, SQLite, AWS, Sentry, Grafana, Datadog, Honeycomb, Playwright, Puppeteer, Notion, Confluence, Slack, Teams. All credentials via `${input:…}` prompts — file is safe to commit. |
| 34a | `.vscode/MCP.md` | Per-server setup guide: prerequisites (`uv`, `node`), VS Code quick start, Claude Code / Claude Desktop equivalents, credential sourcing, and troubleshooting for every MCP server in `mcp.json`. |
| 35 | `.vscode/settings.json` | VS Code config to wire skills/ into Copilot |
| 36 | `MANIFEST.md` | This file — full file listing, visible to all file browsers |
| 36a | `README.md` | Repo landing page ("Start Here"). QI overview, Assert.IQ pitch, three-step get-started, annotated directory tree, upgrade steps, and links to all deep-dive docs. Replaces the `.github/README.md` fallback GitHub previously displayed. |
| 37 | `README.assert-iq.md` | Full reference doc: detailed install options, drop-in / air-gapped path, skill reference, maturity tier matrix, MCP inventory, Dreaming architecture, release history. |
| 38 | `tests/_qi/automated/.gitkeep` | Placeholder so the empty test directory is preserved by git |
| 39 | `tests/_qi/exploratory/.gitkeep` | Placeholder so the empty test directory is preserved by git |
| 40 | `tests/_qi/manual/.gitkeep` | Placeholder so the empty test directory is preserved by git |
| 41 | `CLAUDE.md` | Claude Code entrypoint — mirrors Copilot guidance + `@`-imports scoped instructions |
| 42 | `AGENTS.md` | Generic agent-spec pointer (Codex CLI, Cursor, Aider) |
| 43 | `.claude/agents/assert-iq.md` | Claude Code default Assert.IQ subagent (mirror of Copilot Assert-IQ) |
| 43a | `.claude/agents/assert-iq-plan.md` | Claude Code planning sibling (mirror of Copilot Assert-IQ-PLAN) |
| 44 | `.claude/settings.json` | Claude Code settings — embeds hooks block (synced by installer) |
| 45 | `.claude/skills` | Symlink → `../.github/skills/` so Claude discovers the same skills as Copilot |
| 46 | `install.sh` | Bash installer — renders `.assert-iq/dreaming/session-events.json` from its template (substitutes `__PACK_ROOT__` with the absolute pack path), syncs it into `.claude/settings.json`, scaffolds `.assert-iq/memory/`, creates skills symlink. Idempotent. |
| 47 | `install.ps1` | PowerShell installer — parity with `install.sh`. Doubles backslashes in the substituted path so the rendered JSON remains valid. |
| 47d | `scripts/sync-agents.sh` | Renders the Copilot specialist agents from the Claude sources (single source of truth). `--check` verifies freshness; `--print-map` emits the tool map. |
| 47e | `scripts/sync-agents.ps1` | Windows-native twin of `sync-agents.sh`; produces byte-identical output. Tool-map agreement between the two is enforced by check P6 in `e2e-agent-parity.sh`. |
| 47f | `.assert-iq/tests/_qi/automated/lib/aiq-test-lib.sh` | Shared test helpers: resolves a working Python 3 (`python3` → `python` → `py -3`, probing by execution) and provides the JSON assertions that replaced the former `jq` dependency. |
| 47g | `.assert-iq/tests/_qi/automated/unit-doc-parity.py` | Enforces the HTML/MD parity rule: compares heading trees (text and depth) for all 7 markdown/HTML doc pairs. Deliberate differences are declared in `ACCEPTED` with a reason; a stale declaration also fails. Note `build-search-index.py` indexes h1–h3 only, so a section demoted to h4 in HTML silently drops out of the site search. |
| 47h | `.assert-iq/tests/_qi/automated/unit-hook-schema.py` | Guards the two-harness hook contract: Copilot gets flat handlers with platform overrides, Claude Code gets matcher groups with a `shell` field and a native (non-nested) command body, both Claude templates cover the same events, and all four installers render the Claude-shaped template. |
| 47i | `.assert-iq/tests/_qi/automated/unit-dreaming-gate.sh` | Pins `aiq_enabled()` semantics with NO interpreter on PATH: default-on, honours `dreaming.enabled: false`, ignores a NESTED `enabled: false` (the optional background dreamer), ignores other sections, honours the `AIQ_DREAMING_DISABLED` kill switch. |
| 47j | `.assert-iq/tests/_qi/automated/unit-gitignore-hygiene.sh` | Fails on any negation pattern in a pack-shipped `.gitignore`. A deeper `.gitignore` outranks `.git/info/exclude`, so `!file` defeats a trial-mode install. |
| 47k | `.assert-iq/tests/_qi/automated/unit-script-portability.py` | Guards the two encoding rules that make the pack work on Windows: every shipped `.ps1` is ASCII-only or BOM-marked (Windows PowerShell 5.1 reads a BOM-less file as cp1252 and can fail to *parse* it), and every tracked `.sh`/`.py` is LF in the index and pinned `eol=lf` by `.gitattributes` (bash rejects CRLF). |
| 47p | `.assert-iq/tests/_qi/automated/unit-generated-docs-current.py` | Freshness gate for the GENERATED `docs/html/` set, mirroring check P5's role for the generated Copilot agents. Regenerates into a throwaway copy and diffs against the committed output, ignoring only the volatile `Generated:` stamp. Added because that doc set had been stale since before v2.0.0 ("Skills (22)" vs 30, `v2.0.0` vs `v2.0.2`, missing the specialist-agents row) with nothing to catch it. |
| 47o | `.assert-iq/tests/_qi/automated/integration-doc-integrity.sh` | Runs `scripts/validate-documentation-integrity.sh` inside the regression gate, and fails if it emits fewer than 5 check lines — the validator used to exit 1 after its FIRST check (`set -e` + `((PASSED++))`) and nothing ran it, because `run-all.sh` only discovers tests in its own directory. |
| 47n | `.assert-iq/tests/_qi/automated/e2e-hook-execution.py` | Behavioral hook coverage for BOTH harnesses on the current platform: extracts the command each one would run (Copilot's `osx`/`linux`/`windows` override; Claude Code's matcher-group body plus its declared `shell`), executes it, and asserts the observable state change. `CLAUDE_PLUGIN_ROOT` is left unset so the baked-in fallback path is what gets tested. Catches the two failure modes that every structural check missed: a shape the harness silently ignores, and a wrongly-rendered pack root that makes the handler `exit 0` having done nothing. |
| 47m | `.assert-iq/tests/_qi/automated/unit-install-settings-merge.sh` | Pins the `.claude/settings.json` merge contract in `install.sh`: fresh install writes the matcher-group shape, re-runs merge (other keys survive), re-runs still work with `jq` unavailable, and with no JSON tool at all it fails loudly leaving the file byte-identical. The merge was jq-only, which made the installer work exactly once on stock macOS (Python 3 but no jq). |
| 47l | `scripts/check-environment.sh` + `scripts/check-environment.ps1` | User-facing environment doctor, run before installing. Reports host/shell version, git, a working Python 3 (probing `python3` → `python` → `py -3` by execution), jq, symlink capability, shell line endings, and the shape of an existing `.claude/settings.json`. Exits non-zero only on blocking issues; warnings mark reduced functionality. |
| 51a | `.assert-iq/dreaming/claude-hooks.posix.template.json` + `claude-hooks.windows.template.json` | **Committed sources** for `.claude/settings.json`. Claude Code hook schema (matcher groups, `shell` field, no platform keys) -- deliberately NOT the same shape as `session-events.template.json`, which is Copilot-shaped. |
| 47a | `scripts/bootstrap.sh` | Cross-platform bootstrap (macOS/Linux) invoked by `/assert-iq-bootstrap`. Flag-driven, idempotent. Supports `--mode={trial,committed,ask}`, `--graduate`, interactive conflict resolver, manifest tracking. |
| 47b | `scripts/bootstrap.ps1` | Cross-platform bootstrap (Windows) invoked by `/assert-iq-bootstrap`. PowerShell parity with `bootstrap.sh`: same flags (`-Mode`, `-Trial`, `-Committed`, `-Graduate`), same manifest format, same `.git/info/exclude` block. |
| 48 | `.github/vscode-readme.md` | Plain-language guide to the Copilot-side of the pack |
| 49 | `.claude/claude-readme.md` | Plain-language guide to the Claude-side of the pack |
| 50 | `.gitignore` | Excludes the rendered `.assert-iq/dreaming/session-events.json`, the dream state lock, and `transcripts/` from version control (per-machine / raw artifacts). The `.assert-iq/memory/` store itself IS committed. |
| 50a | `.gitattributes` | Line-ending policy. Pins `*.sh`/`*.py` to `eol=lf` and `*.ps1` to `eol=crlf` so a checkout is byte-correct regardless of the user's `core.autocrlf`. Without it, Git's Windows default rewrote every shell script to CRLF, which bash on Linux/WSL/macOS refuses (`$'\r': command not found`). Enforced by `unit-script-portability.py`. |
| 51 | `.assert-iq/dreaming/session-events.template.json` | **Committed source-of-truth** for the Dreaming session-event wiring. Uses `${CLAUDE_PLUGIN_ROOT:-__PACK_ROOT__}` (bash) and `$env:CLAUDE_PLUGIN_ROOT ?? '__PACK_ROOT__'` (PowerShell) so the rendered output works in both Claude Code (env var wins) and VS Code Copilot (falls back to baked path). |
| 52-59 | `.claude/agents/specialists/*.md` | **v2.0+** Eight specialist subagents (isolated, JSON-only output): risk-scorer, coverage-analyst, flake-adjudicator, oracle-grader, calibration-specialist, memory-curator, traceability-auditor, hotspot-analyzer. Lead agent orchestrates in parallel batch then serial chain. |
| 60 | `.github/skills/measure-qi-impact/SKILL.md` | **v2.0+** Skill: `/measure-qi-impact` — Convert QI verdicts + baseline metrics into quarterly business impact dashboards. Generates escape reduction %, triage hours saved, cycle-time improvement, and total economic ROI for VP presentations. |
| 61 | `.assert-iq/business-metrics/baseline.json` | **v2.0+** Pre-QI baseline metrics template (escape rate/quarter, triage hours/quarter, cycle-time days). Baseline for `/measure-qi-impact` delta calculations. |
| 62 | `.assert-iq/business-metrics/reports/` | **v2.0+** Output directory for quarterly HTML dashboards and JSON reports. Excluded from git. |
| 63 | `.assert-iq/agent-runs/` | **v2.0+** Orchestration artifact tracking: specialist outputs, aggregation metadata, run index. Excluded from git. |
| 64 | `.assert-iq/agent-runs/index.json` | **v2.0+** Orchestration run index tracking. |
| 65 | `.assert-iq/tests/_qi/automated/e2e-specialist-orchestration.sh` | **v2.0+** E2E test suite for specialist orchestration (30+ assertions). |
| 66 | `.assert-iq/tests/_qi/automated/COMPREHENSIVE-TEST-REPORT.md` | **v2.0+** Full v2.0 test report (10 suites, 40+ assertions, 100% pass rate). |
| 67 | `.assert-iq/tests/_qi/automated/FINAL-TESTING-SUMMARY.md` | **v2.0+** Executive testing summary and production readiness checklist. |
| 68 | `.assert-iq/business-metrics/reports/SAMPLE-2026-Q3-report.html` | **v2.0+** Sample generated dashboard template for measure-qi-impact skill. |
| — | `.assert-iq/dreaming/` + `.assert-iq/memory/` | Dreaming feature: `dreaming/scripts/` (waking recorder + gate + lib), `dreaming/service/dreaming_service.py` (optional cron dreamer), `dreaming/session-events.json` (**generated by the installer**; gitignored) + the memory store `memory/MEMORY.md`, `memory/topics/`, `memory/logs/`, `memory/.dream/state.json`. The `/dream` skill (`.github/skills/dream/SKILL.md`) consolidates the store. |

---

**Pack root**: `assert-iq-agent-pack/`
**Skill count**: 30 (in `.github/skills/`)
**Instruction count**: 6 (in `.github/instructions/`)
**Agents (Copilot)**: 10 (in `.github/agents/`) — `Assert-IQ` (default, delegates via `agent/runSubagent`), `Assert-IQ-PLAN` (planner), plus 8 in `specialists/` **generated** from the Claude sources by `scripts/sync-agents.sh` (do not hand-edit).
**Subagents (Claude)**: 11 (in `.claude/agents/`) — `assert-iq` (lead orchestrator), `assert-iq-plan` (planner), `grader` (Oracle-layer independent grader), plus 8 in `specialists/`: `risk-scorer`, `coverage-analyst`, `flake-adjudicator`, `oracle-grader`, `calibration-specialist`, `memory-curator`, `traceability-auditor`, `hotspot-analyzer`
**Cross-harness parity**: `.claude/skills` is a symlink to `.github/skills`, so skills cannot drift. The specialist tier is generated by `scripts/sync-agents.sh` (+ `.ps1` twin), so it cannot drift either. The lead and planner agents stay hand-authored per harness on purpose — their prose is genuinely harness-specific (Copilot handoff buttons and MCP servers vs. Claude subagent invocation). All of this is enforced by `.assert-iq/tests/_qi/automated/e2e-agent-parity.sh` (P1-P6).
**Dreaming session events**: SessionStart (dream gate), Stop (session recorder) — see `.assert-iq/dreaming/session-events.template.json`

## Notes for v2.0.0

- **Multi-Agent Orchestration**: Lead agent delegates to 8 isolated specialists (4 parallel + 4 serial). Each returns JSON; lead synthesizes findings into narrative + decision. Audit trail in `.assert-iq/agent-runs/`.
- **Commercial Instrumentation**: New `/measure-qi-impact` skill converts QI verdicts + baseline metrics into VP-ready HTML dashboards with escape reduction %, triage hours saved, cycle-time improvement, and total economic ROI.
- **Baseline Metrics**: Teams track pre-QI metrics in `.assert-iq/business-metrics/baseline.json`. `/measure-qi-impact` calculates quarterly improvement and economic value.
- **Backward Compatibility**: v2.0 is a strict superset of v1.7.0. All existing features intact, zero breaking changes.

## Notes for v0.9.0

- **Workspace topology (split-repo support).** New `workspace:` block in
  `.assert-iq/config.yaml` introduces `role: monorepo | prod | tests`
  (default `monorepo`) plus an optional `companion_repo` sub-block
  (`path` / `remote` / `fetch: mcp | local_path | manual_paste` /
  `branch`). Lets teams whose tests live in a repo separate from their
  production code wire both halves together without forking the pack.
  Default `monorepo` is backward-compatible — single-repo users see
  zero behavioral change.
- **Centralized topology contract in `.assert-iq/workspace-topology.md`.**
  Lazy-loaded reference doc (not auto-loaded into every prompt) defines
  the fetch fallback chain (MCP → local path → manual paste) and the
  UNGRADED contract: when the companion is unset or unreachable, the
  affected signal layer is reported as UNGRADED with
  `reason: "companion_repo_unset"` (or `"companion_repo_unreachable"`)
  per the v0.2 signal-schema `partial_signal_mode: true` rule — never
  silently fabricated. `qi-foundation.instructions.md` carries an
  80-token pointer to this file so monorepo users (the default)
  don't pay for split-repo mechanics on every turn.
- **Seven skills made workspace-aware.** Each of `risk-assess-pr`,
  `check-merge`, `release-confidence`, `code-review`,
  `check-test-coverage`, `generate-traceability-matrix`, and
  `analyze-escaped-defect` gained a new customization point that
  names which layer / source degrades to UNGRADED when the companion
  is missing. The full rule lives in `.assert-iq/workspace-topology.md`;
  the skills carry short pointers, so the contract is not duplicated.
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
- **Install model reworked into two paths.** Plugin install removed.
  Path A is pack-as-workspace (clone the pack, run `install.sh` /
  `install.ps1` at the pack root, open the pack folder as the VS
  Code / Claude Code workspace); Path B is codebase install
  (`/assert-iq-bootstrap` or `bash scripts/bootstrap.sh --mode=trial`
  inside the target repo). The `.claude-plugin/` directory
  (`plugin.json`, `marketplace.json`) is deleted. Both installers
  gain `--uninstall` (`-Uninstall` on Windows) with `--user`,
  `--yes`, `--dry-run`; bootstrap snapshots any pre-existing user
  files to `<file>.assert-iq.pre-install` so uninstall can restore
  byte-for-byte. Bootstrap now also delivers four additional
  workspace surfaces — `.github/skills/`, `.github/agents/`,
  `.claude/agents/`, and the `.claude/skills` symlink (copy fallback
  on Windows without Developer Mode) — bringing the total to twelve
  workspace-loaded surfaces. New `hooks/scripts/lib/render-hooks.{sh,ps1}`
  shared library renders `hooks/hooks.json` from the template at
  install time.
- **Skill count grew from 23 to 24** with the addition of the
  `assert-iq-bootstrap` skill itself in `.github/skills/`.
- **Version metadata centralized.** New `VERSION` file at the repo
  root is the sole source of truth; `scripts/bootstrap.{sh,ps1}`
  read it when stamping `.assert-iq/.install-manifest.json`. Banners
  updated in `MANIFEST.md`, `README.md`, and `README.assert-iq.md`.

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
