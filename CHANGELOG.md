# Changelog

All notable changes to the Assert.IQ Agent Pack are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] — 2026-06-09

### Added
- `assert-iq-tailor` skill (`/assert-iq-tailor`) — a guided, evidence-driven
  customization pass that takes a freshly **placed** pack (from
  `/assert-iq-bootstrap`) and **tailors** it to the host codebase. It
  discovers the stack once (languages, test frameworks, CI system,
  tracker, VCS host, API contracts, topology, sensitive paths,
  traceability idiom), presents a Stack Profile at a human-review gate,
  then edits the configurable surfaces in dependency order — keystone
  `config.yaml` first, then `governance.md` + `maturity-profile.md`, the
  five instruction files, a config-driven (light) skills pass, and
  `mcp.json` last. Compliance regimes are **ask-only** (never inferred);
  deep skill-body rewrites are opt-in and gated to `mid`/`higher`
  maturity. Every edited file is snapshotted to
  `<file>.assert-iq.pre-tailor` so the pass is reversible and idempotent.

### Changed
- `assert-iq-bootstrap` skill now closes with a handoff to
  `/assert-iq-tailor` (placement → tailoring) and the surfaces table
  reflects the new count.
- Routing tables in both Copilot agents (`.github/agents/`) and both
  Claude subagents (`.claude/agents/`) gain the `/assert-iq-tailor` row.
- Skill count is now 26 in `.github/skills/`. Note: the published count
  had drifted (narrative docs read 24, `MANIFEST.md` read 23); both are
  reconciled to the true directory count here.
- `bootstrap.sh` / `bootstrap.ps1` now treat `*.assert-iq.pre-tailor`
  snapshots as managed tool artifacts: the glob is added to the always-on
  `.git/info/exclude` block (so tailor snapshots never leak into git), and
  `--uninstall` sweeps any leftover `*.assert-iq.pre-tailor` files under
  `.assert-iq/`, `.github/instructions/`, and `.vscode/` so a full
  uninstall leaves no tailor litter behind. The uninstall confirmation
  prompt lists this step.
- HTML doc snapshots (`README.html`, `README.assert-iq.html`) refreshed:
  skill count → 26, version → v1.3.0, and the install/customize guidance
  now leads with the one-command `/assert-iq-tailor` flow (with a fixed
  callout that was previously nested inside a table) plus a Setup section
  in the skill registry.

## [1.2.0] — 2026-06-06

### Changed
- Restructured the always-on instruction stack to remove duplication
  across `.github/copilot-instructions.md`, `CLAUDE.md`, and `AGENTS.md`.
  Core principles, Maturity awareness, Governance, and Output standards
  now live exclusively in `.github/instructions/qi-foundation.instructions.md`
  (auto-loaded by Copilot via `applyTo: "**"`; @-referenced by
  `CLAUDE.md`). The trio files were rewritten as thin tool-specific
  pointers. `AGENTS.md` was kept self-contained because Codex CLI /
  Cursor / Aider do not reliably load `.github/instructions/`.
  Per-turn savings: Copilot path ~370 tokens, Claude path ~410 tokens.
  Zero behavior change — every rule that loaded before still loads,
  just from a single home.
- Compressed the workspace-topology section in
  `qi-foundation.instructions.md` from ~480 tokens to ~80 tokens. Now a
  pointer to the new lazy-loaded reference doc (see Added). Monorepo
  users (the default) no longer carry split-repo fetch / UNGRADED prose
  on every prompt.
- Trimmed the three heaviest skill `description:` blocks: `code-review`
  (1,147 → 520 chars), `eval-optimizer` (1,023 → 584 chars),
  `generate-hotspot-map` (435 → 292 chars). Skill bodies untouched.
  Aggregate skill-routing block dropped from 5,191 → 3,982 chars
  (~300 tokens off every turn that doesn't invoke a skill).
- Updated the seven cross-repo skills (`risk-assess-pr`, `check-merge`,
  `release-confidence`, `code-review`, `check-test-coverage`,
  `generate-traceability-matrix`, `analyze-escaped-defect`) plus
  `generate-hotspot-map` to point to `.assert-iq/workspace-topology.md`
  for the full contract instead of `qi-foundation § Workspace topology`.
- README.md / README.html / MANIFEST.md updated to reference the new
  topology contract location.

### Added
- New `.assert-iq/workspace-topology.md` reference doc carrying the
  full prod / tests fetch fallback chain (MCP → local path → manual
  paste) and the UNGRADED contract (`reason: "companion_repo_unset"` /
  `"companion_repo_unreachable"` per signal-schema
  `partial_signal_mode: true`). The filename does **not** end in
  `.instructions.md`, so it is **not** auto-loaded — skills only pull
  it when `workspace.role != monorepo`.
- New 1.2.0 row in the version-history tables of `README.assert-iq.md`
  and `README.assert-iq.html` (kept in lockstep per HTML/MD parity rule).

## [1.1.11] — 2026-06-05

### Fixed
- Added missing template placeholders (`ci_provider`, `linters`, `review_source`, `test_id_format`, `regression_area_path`, `bug_reporter`, `five_whys`, `targeted_test_command`) to `.assert-iq/config.yaml` so they are immediately visible to users configuring the pack out of the box without the agent needing to infer them.

## [1.1.10] — 2026-06-04

### Fixed
- Fixed an accidental HTML structure malformation in `README.html` introduced during the previous documentation injections, which broke the rendering of both comparison tables on that page.

## [1.1.9] — 2026-06-04

### Added
- Added an explicit "Presets vs Modes" distinction block to documentation to clarify that presets control placement and modes control Git visibility.

## [1.1.8] — 2026-06-04

### Added
- Added a "Compare the Presets" table to all documentation files to explicitly disambiguate `--preset=pod`, `--preset=solo`, and `--preset=portable` regarding where instructions and skills land permanently.

## [1.1.7] — 2026-06-04

### Fixed
- Restored missing `--preset=solo|pod` clarification block in `README.md` and `README.html` that had only been present in the verbose `README.assert-iq` documentation.

## [1.1.6] — 2026-06-04

### Added
- Added missing documentation for `/generate-hotspot-map` skill in skill registries.

## [1.1.5] — 2026-06-04

### Changed
- Updated documentation HTML styling to exactly match the Assert.IQ presentation deck color scheme (dark background `#18191a` + warm orange `#e25232` + secondary teal `#1e8077`).

## [1.1.4] — 2026-06-04

### Changed
- Fixed hooks configuration and telemetry logic to correctly fall back to workspace-relative artifacts directories (`.github/skills` and `.claude/skills`) rather than exclusively tracking user-global `~/.agents/skills`.


## [1.1.3] — 2026-06-04

### Fixed
- Fixed CSS grid overflow issue causing `Path A / Path B` comparison cards to slightly overflow offscreen.


## [1.1.2] — 2026-06-04

### Changed
- Pointed GitHub Pages landing redirect to `README.html` instead of `README.assert-iq.html`.


## [1.1.1] — 2026-06-04

Patch release. Hides Hindsight Hooks runtime artifacts from git so
workspaces that install the pack don't see hook state files appear as
untracked changes.

### Fixed

- `hooks/state/.dedup-<hash>` markers (atomic locks created by
  `si_dedup_or_exit` to suppress double-fires) and `hooks/state/.last-janitor`
  no longer surface in `git status` after install. Per-directory
  `.gitignore` files now ship inside `hooks/state/`, `hooks/logs/`, and
  `hooks/sessions/` at the pack source. `copy_tree()` in
  `scripts/bootstrap.{sh,ps1}` already copies dotfiles, so the ignore
  rules propagate verbatim into every workspace install — no mutation of
  the workspace `.gitignore` required (consistent with the design rule
  that bootstrap never touches the user's `.gitignore`).
- Untracked the previously-committed runtime seeds
  `hooks/logs/skill-improve.log` and `hooks/state/.last-janitor`. The
  structural seeds `hooks/state/dismissed-lessons.json` and
  `hooks/state/edit-frequency.json` remain tracked.

### Verified

- `tests/_qi/automated/e2e-hooks.sh`: 15/15 PASS.
- `tests/_qi/automated/e2e-bootstrap.sh`: 23/23 PASS.

## [1.1.0] — 2026-06-04

Hindsight Hooks become scope-aware and double-fire-safe. Power users can
now install hooks once at the user level (`~/.agents/hooks/`) and have
them fire across every VS Code workspace; the existing per-workspace
install path is unchanged and remains the default.

### Added

- **`--hooks=user` / `-Hooks user` install mode** in
  `scripts/bootstrap.{sh,ps1}`. Copies hook scripts, lib, config, state,
  and logs to `$HOME/.agents/hooks/`, creates `sessions/`, renders
  `hooks.json` so the wrapper resolves `__PACK_ROOT__` to the user-global
  pack root, and prints the VS Code USER `settings.json` block needed to
  register the hook file across all workspaces. Manifest entries scoped
  `user`, with full uninstall support via `--uninstall --user`.
- **`si_dedup_or_exit` / `Invoke-SiDedupOrExit`** helpers in the shared
  hook lib. Suppress double-fires of the same `(session_id, event)`
  pair within `SKILL_IMPROVE_DEDUP_WINDOW_SECONDS` (default 5; set to 0
  to disable). Atomic claim via `set -o noclobber` (bash) /
  `FileMode.CreateNew` (PowerShell). Wired into SessionStart and Stop
  only — PostToolUse legitimately fires once per tool call.
- **Hooks E2E suite** (`tests/_qi/automated/e2e-hooks.sh`) — 15 cases
  covering workspace + user install layouts, SessionStart routing,
  PostToolUse telemetry + detect, Stop log entry,
  `config.enabled=false` no-op, `SKILL_IMPROVE_DISABLED=1` no-op,
  double-fire dedup, dedup-window-disabled override, per-event dedup
  independence, marker creation under `state/`, workspace/user install
  isolation, and user uninstall. Workspace and `$HOME` are
  mktemp-isolated.

### Changed

- Hook scripts resolve `SKILL_IMPROVE_ROOT` from the environment (set by
  the `hooks.json` wrapper based on install scope) instead of hardcoding
  `$HOME/.agents/hooks`. Default falls back to `$HOME/.agents/hooks` for
  back-compat with existing installs.
- `hooks/hooks.template.json` wrappers now `export SKILL_IMPROVE_ROOT`
  before invoking the script so workspace installs route to
  `<workspace>/hooks/` and user installs route to `~/.agents/hooks/`
  deterministically.
- Five hardcoded `~/.agents/hooks/config/skill-improve.config.json`
  lookups (in `skill-improve-session-start.sh`,
  `skill-improve-session-end.sh`, `lib/correction-signatures.sh`)
  replaced with env-var fallbacks.
- Janitor sweep now prunes stale `.dedup-*` markers older than 1 hour
  in addition to its existing session and log retention passes.
- `VERSION` bumped to `1.1.0`.

### Verified

- `tests/_qi/automated/e2e-hooks.sh`: 15/15 PASS on macOS bash.
- `tests/_qi/automated/e2e-bootstrap.sh`: 23/23 PASS (no regressions).

## [1.0.0] — 2026-06-04

First stable release. The pack is now considered API-stable: bootstrap CLI
flags, manifest schema, skill names, and workspace surface layout will not
change in incompatible ways without a major-version bump.

### Added

- **E2E regression suite** (`tests/_qi/automated/e2e-bootstrap.sh`) — 23 cases
  covering pod / solo / portable presets, committed / trial / ask modes,
  skills-scope workspace / user / both, idempotent reinstall, conflict +
  backup + restore round-trip, dry-run, and invalid-arg rejection. Workspace
  and `$HOME` are mktemp-isolated so the suite is safe to run on a developer
  machine.
- `assert-iq-bootstrap` skill — `/assert-iq-bootstrap` slash command for
  installing the pack into an arbitrary repository.
- `generate-hotspot-map` skill — churn × complexity × defect-density audit
  that produces a Hotspot Risk Index registry for test prioritization.
- HTML snapshots of the README family (`README.html`, `README.assert-iq.html`,
  `claude-readme.html`, `vscode-readme.html`, `hooks-readme.html`, `MCP.html`)
  for environments that don't render Markdown natively.
- Solo-preset callout and "HTML files are rendered snapshots" note in
  `README.assert-iq.md`.

### Changed

- **Bootstrap (bash + PowerShell, parity-preserving):**
  - JSON merge no-op short-circuit consolidated into a single helper
    (`write_or_skip_if_unchanged` / `Write-OrSkipIfUnchanged`); previously
    duplicated at four call sites.
  - Manifest action vocabulary centralized; `manifest_add` /
    `Add-ManifestEntry` reject unknown actions at call time instead of
    silently writing typos that downstream predicates would never match.
  - Uninstall gains a manifest-derived ancestor-dir sweep as a safety net
    so future surface additions don't have to update the hardcoded prune
    lists. PowerShell version sorts deepest-first by path-segment depth
    (not string length) for correctness on uneven path widths.
- `mk_pack_copy()` in the e2e driver now wraps the tar pipe in a
  `set -o pipefail` subshell so silent tar failures surface immediately.
- `VERSION` bumped to `1.0.0`.

### Verified

- 23/23 PASS on macOS bash. PowerShell e2e on Windows is the deferred
  follow-up.

## [0.9.0] — 2026-06-03

### Added

- `VERSION` file as the sole source of truth for the pack version
  (replaces `.claude-plugin/*.json`).
- Two install paths:
  - **Path A (pack-as-workspace):** `install.sh` / `install.ps1` at pack root.
  - **Path B (codebase bootstrap):** `scripts/bootstrap.sh` / `.ps1` invoked
    via `/assert-iq-bootstrap`.
- Both paths support `--uninstall` (`-Uninstall`) with `--yes` / `--user` /
  `--dry-run`. Bootstrap snapshots pre-existing user files to
  `<file>.assert-iq.pre-install` for byte-for-byte restore on uninstall.
- Four new workspace surfaces: `.github/skills/`, `.github/agents/`,
  `.claude/agents/`, and `.claude/skills` (symlink, copy fallback on Windows
  without Developer Mode) — twelve total workspace-loaded surfaces.
- Shared `hooks/scripts/lib/render-hooks.{sh,ps1}` library for
  `hooks.json` rendering.
- Workspace topology + Five Whys discipline.

### Changed

- Skill count 23 → 24 (adds `assert-iq-bootstrap`).
- `--yes` / `-Yes` accepted as no-op on installers for parity with bootstrap.

### Verified

- Full uninstall round-trip on bash + pwsh (Path A and Path B): 0 leftover
  files, 0 exclude residue.

## [0.8.0] and earlier

See git history (`git log v0.8.0`). Releases prior to 1.0.0 are pre-stable.

[1.1.1]: https://github.com/fromjariuswithsparq/assert-iq-agent-pack/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/fromjariuswithsparq/assert-iq-agent-pack/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/fromjariuswithsparq/assert-iq-agent-pack/compare/v0.9.0...v1.0.0
[0.9.0]: https://github.com/fromjariuswithsparq/assert-iq-agent-pack/compare/v0.8.0...v0.9.0