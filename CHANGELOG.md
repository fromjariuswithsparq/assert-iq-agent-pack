# Changelog

All notable changes to the Assert.IQ Agent Pack are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.6.1] — 2026-08-11

### Fixed
- **Bootstrap uninstall cleanup.** Oracle directories (`.assert-iq/oracles/{outcomes,rubrics,schemas}/`) were not removed during uninstall due to missing entries in cleanup arrays. Added oracle directory to `tree_roots` and `empty_dirs` in `scripts/bootstrap.sh` for both workspace and user-scope installations. Verified clean removal in test workflow.

### Added
- **Oracle grading routing across 15 core skills.** Comprehensive integration of oracle layer into generation, review, healing, and routing workflows:
  - **Generation:** `/generate-automated-unit-test`, `/generate-bug-report`, `/generate-test-plan`, `/generate-automated-api-test`, `/generate-automated-ui-test`, `/generate-manual-test-case` now include post-artifact oracle grading guidance with specific rubric IDs.
  - **Review & Analysis:** `/code-review`, `/review-test-quality`, `/analyze-flaky-test`, `/analyze-escaped-defect` now surface oracle as complementary quality signal with maturity tier behavior.
  - **Healing:** `/agentic-heal` now includes post-heal oracle verification to detect quality regressions (assertion clarity, independence, determinism, focus).
  - **Routing & Gates:** `/generate-tests-from-ac`, `/risk-assess-pr`, `/new-pull-request` now surface oracle verdicts in workflow and pre-flight checks.
  - **Diagnostics:** `/debug-ui-tests` now includes oracle brittleness verification post-fix.
  - All additions reference v1.6.0+ oracle layer, include maturity tier gating (early/mid/higher), and specify rubric IDs for recommended grading runs.

### Documentation
- Oracle integration guide added across all 15 affected skills showing rubric ID, expected verdict types, and per-tier behavior.

## [1.6.0] — 2026-08-11

### Added
- **Oracle Layer — rubric-based independent quality verification.** New skills:
  - `/define-quality-rubric` — guided interview for authoring versioned quality rubrics (acceptance contracts with dimensions, levels, passing criteria)
  - `/grade-with-rubric` — independent artifact grading in isolated grader agent context (PASS/CONDITIONAL/FAIL verdicts with evidence)
- **Grader agent** (`.claude/agents/grader.md`) — isolated evaluation context with no access to generator reasoning; produces evidence-driven verdicts with per-dimension scoring
- **Oracle registry** (`.assert-iq/oracles/`) — schemas, sample rubrics (unit test, integration test, bug report, plan), verdict storage with full lineage (append-only history)
- **Oracle governance** (`.github/instructions/qi-oracle.instructions.md`) — rubric authorship rules, grading standards, maturity gating, immutability contract
- **Oracle integration** — `/check-merge` and `/release-confidence` now consume oracle verdicts in Outcome layer with maturity-tier weighting (early: 0%, mid: 20%, higher: 50%)
- **Documentation** — `ORACLE_QUICK_START.md` (5-step workflow), oracle sections in `README.md` and `README.assert-iq.md`, oracle grading examples
- **Config updates** — `.assert-iq/config.yaml` now includes `oracle:` block (grader model, defaults by artifact type, verdict_sink, maturity_gating)
- **Skill count:** 27 → 29 total (added 2 oracle skills)

### Positioning
- **Rubric authorship** (not test generation) is the defensible differentiator
- **Independent grading** — grader has zero access to how artifacts were produced
- **Immutable, versioned specs** — rubrics are treated as acceptance contracts, not templates
- **Evidence-driven verdicts** — every verdict cites specific evidence (line numbers, patterns, reasoning)

## [1.5.8] — 2026-08-11

### Fixed
- **Critical documentation integrity failures.** The landing page (README.md) claimed v1.5.7; the full documentation (README.assert-iq.md) header said v1.3.0 and footer said v1.2.0. The version history table ended at v1.2.0 (no entries for 1.3.0–1.5.7). The skill registry listed only 23 skills while prose claimed 26, and 4 critical skills were missing: `/dream` (the flagship differentiator), `/eval-optimizer`, `/assert-iq-bootstrap`, and `/assert-iq-tailor`. The inventory count vs. reality was 23 listed vs. 27 actual. Hindsight Hooks was marked as retired in the Dreaming guide but still referenced as active features in version history. **All signals now reconcile:** version history updated through v1.5.7; skill registry expanded to all 27 skills (5 new rows: Learn + 1, Cross-cutting + 1, new Setup & Meta section + 2); prose skill count corrected to 27; all version banners consistent (v1.5.7). Documentation now exhibits the trustworthiness the pack claims to provide.

## [1.5.7] — 2026-08-08

### Added
- **High-level "Why Dreaming — and how it saves tokens" section** in
  `dreaming-readme.html`. The dreaming guide previously jumped straight into
  operator mechanics (the two loops, files, config); it now opens with a
  plain-English explanation of *what* dreaming is, *why* it's in Assert.IQ, and
  *how* it saves tokens — including a worked token-economics model and a
  matching sidebar nav link. Aimed at readers who don't need what's under the
  hood.

### Fixed
- **Stale hook reference in `README.assert-iq.md`.** The layout notes still said
  `chat.hookFilesLocations` pointed at `./.assert-iq/dreaming/session-events.json`;
  since v1.5.5 it points at `.claude/settings.json` (read natively by both VS Code
  Copilot and Claude Code). Updated to match.

### Changed
- Rebuilt the docs search index (`assets/search-index.js`) to include the new
  dreaming section.

## [1.5.6] — 2026-08-08

### Fixed
- **Uninstall after an upgrade left files behind.** When `--upgrade` overwrote a
  pack-owned file that changed between versions, it created a
  `.assert-iq.pre-install` backup of the old copy. Uninstall then *restored* that
  backup (treating the pack file as if it were your pre-existing file), leaving
  the changed files plus a `.assert-iq.uninstall-saved` sidecar behind — so
  `.assert-iq/` was never fully removed. Upgrade no longer backs up pack-owned
  files (the three-way merge already preserves your edits during the upgrade
  itself), so uninstall removes them cleanly. Ported to `bootstrap.ps1`.
- **Stopped shipping a compiled `.pyc`.** The optional dreaming service's
  `__pycache__/*.pyc` build artifact was committed and installed. It's now
  git-ignored and removed, and the install copy routines skip `*.pyc` /
  `__pycache__/`.

Note: the Dreaming memory store (`.assert-iq/memory/`) is still *intentionally*
preserved on uninstall when it holds real consolidated content (your dreams); a
pristine never-dreamed seed is removed for a clean tree.

## [1.5.5] — 2026-08-07

### Fixed
- **Dreaming now records in VS Code Copilot, not just Claude Code.** The pack
  previously pointed VS Code's `chat.hookFilesLocations` at a custom
  `.assert-iq/dreaming/session-events.json` path and *disabled* the default
  `.claude/settings.json` location. Per the VS Code agent-hooks docs, VS Code
  reads `.claude/settings.json` natively (same Claude hook format), so the pack
  now wires **both** harnesses to that one file — Claude Code reads it directly;
  VS Code loads it from its default location. Its baked
  `${CLAUDE_PLUGIN_ROOT:-<workspace>}` fallback resolves the pack root under
  Copilot, which doesn't set that env var. This is why session logs never
  appeared in a Copilot-only workflow.
- **Off-by-one fallback pack root.** When `AIQ_PACK_ROOT` is unset,
  `dream-utils.{sh,ps1}` computed the pack root three levels up from the lib dir
  (landing on `.assert-iq/`) instead of four (the repo root), which would write
  to a stray `.assert-iq/.assert-iq/memory/` path. Fixed to four levels. (Masked
  in normal use because the hook always exports `AIQ_PACK_ROOT`.)
- **Fragile enabled-check (bash).** With no `dreaming:` block in `config.yaml`,
  `aiq_enabled` scanned the whole file and matched the first unrelated
  `enabled:` line. It now defaults to enabled when the block is absent, matching
  the PowerShell side.

Existing installs: VS Code settings are merged additively (your keys win), so an
upgrade won't rewrite an existing `.vscode/settings.json` — set
`"chat.hookFilesLocations": { ".claude/settings.json": true }` manually (and
reload the window).

## [1.5.4] — 2026-08-07

### Changed
- **`MEMORY.md` is now git-ignored.** The pack-as-workspace memory index is no
  longer committed, so maintainers can run `/dream` freely without their
  working memory ever shipping to installers. The memory store now ships only
  `README.md` and the empty-dir `.gitkeep`s (`topics/*.md`, `logs/`,
  `.dream/state.json`, and now `MEMORY.md` are all local-only). Both installers
  (`install.sh` / `install.ps1`) seed a clean `MEMORY.md` index when a clone
  doesn't have one, so a fresh Path-A install still gets an index; `bootstrap`
  already generated one inline.

## [1.5.3] — 2026-08-06

### Fixed
- **Malformed shebangs in the Dreaming scripts.** Every shell/python script
  under `.assert-iq/dreaming/` (and the e2e driver) shipped with an escaped
  shebang — `#\!/bin/bash` instead of `#!/bin/bash` — an artifact of how the
  files were generated. The waking loop still ran because the hook template
  invokes the scripts via `bash -c … "$S"` (bash re-execs on `ENOEXEC` and
  line 1 is a comment), but a direct `./script.sh` invocation relied on that
  fallback. Shebangs are now byte-correct so the scripts run standalone. Also
  fixed the same escape in a `[ ! -t 0 ]` stdin test and in the `<!--` HTML
  comments of `MEMORY.md` and the `/dream` skill (which previously rendered as
  visible text instead of a comment).

## [1.5.2] — 2026-08-06

### Fixed
- **Trial-mode upgrades no longer leak files into git.** On `--upgrade`,
  files the previous install hid via `.git/info/exclude` that aren't touched
  in the current run — a conflict-kept original whose only new manifest entry
  is its `.assert-iq-new` sidecar, and orphaned files from a retired feature
  (e.g. the old `hooks/` tree) — dropped out of the regenerated exclude block
  and surfaced in `git status`. The exclude writer now unions the previous
  manifest's workspace paths so everything that was hidden stays hidden.

### Changed
- **Upgrades now install newly-added surfaces.** Previously `--upgrade` only
  refreshed surfaces already present in the recorded manifest, so upgrading a
  pre-Dreaming install did not install the Dreaming machinery or seed the
  memory store. New surfaces absent from an older manifest now default to the
  scope where the pack itself lives (`.assert-iq`), so upgrading picks up
  Dreaming, the memory store, and session-event wiring.

## [1.5.1] — 2026-08-06

### Added
- **Install-time base cache for durable upgrades.** Every install now
  snapshots each pack-owned file's pristine content under `.assert-iq/.base/`
  (git-ignored, removed on uninstall). On a later `--upgrade` this cache is the
  preferred three-way merge baseline, so upgrades preserve user edits **even
  when the source repo has no matching version tag or no git history at all**
  (offline installs, release zips, shallow clones). Git-tag reconstruction is
  now the fallback, and a successful tag reconstruction re-seeds the cache so
  the next upgrade never needs the tag again. The three markdown-allowlist
  files keep their dedicated marker-block merge. Ported to both `bootstrap.sh`
  and `bootstrap.ps1`.
- Backfilled release tags `v1.2.0`, `v1.3.0`, `v1.4.0` on their release commits
  so pre-1.5 installs can reconstruct a baseline and get line-level merges on
  their first upgrade (previously these versions had no tag, forcing a
  whole-file keep/overwrite choice).
- E2E cases 38 (tagless upgrade via base cache) and 39 (cache-less older
  install falling back to tag reconstruction).

### Fixed
- The base-cache lookup could return a non-zero status when the cache was
  absent, which under `set -e` aborted the entire upgrade after the banner —
  breaking exactly the cache-less (retroactive) path. `base_lookup` now always
  returns success.

## [1.5.0] — 2026-08-06

### Added
- **`bootstrap --upgrade` engine (three-way merge).** A new upgrade path that
  refreshes an existing install in place while preserving your edits.
  Reconstructs the install-time baseline from the pack's git history
  (`git show v<installed-version>:<path>`) and runs a `git merge-file`
  three-way merge: non-overlapping pack + user edits both land automatically,
  overlapping edits fall back to a `.assert-iq-new` sidecar (your file is
  never clobbered). Mode is pinned to the recorded install (never flips
  trial↔committed), the refreshed surface set is derived from the manifest,
  and files the new pack no longer ships are surfaced as orphans (prompt-each
  interactively; report-only under `--yes`). The install manifest now records
  a per-file `sha` so unedited files can be refreshed outright. Ported to both
  `bootstrap.sh` and `bootstrap.ps1`.
- E2E coverage for the new behavior in `tests/_qi/automated/e2e-bootstrap.sh`
  (clean-slate seed / no-logs / no-conflict, uninstall-preserves-memory, and a
  full upgrade merge + conflict + orphan case).

### Changed
- **Every install/upgrade starts the Dreaming memory on a clean slate.** The
  pack no longer ships or copies its own accumulated dream data. Installers
  now *seed* a fresh memory store (empty `topics/`, `logs/`, a clean
  `MEMORY.md`, and `state.json` at `sessions_since_dream: 0`) instead of
  copying `topics/*.md`, daily `logs/`, or a populated `MEMORY.md`. On
  upgrade the memory store is never touched (it is your data).
- Uninstall now preserves a memory store that holds real consolidated
  content, but removes a pristine never-dreamed seed so the uninstall leaves
  a clean working tree.

### Fixed
- Fresh installs no longer report a bogus merge conflict on
  `.assert-iq/dreaming/session-events.json`. The rendered events file was
  being copied twice (once by the `.assert-iq` tree walk, once by the
  dreaming handler) and then re-rendered; both tree walks now exclude it.
- `.gitignore` hardened so the pack repo can never re-commit its own dream
  activity (`topics/*`, `logs/*` except `.gitkeep`, `.dream/state.json`).

## [1.4.0] — 2026-08-04

### Added
- **Dreaming — markdown memory consolidation.** A new `.assert-iq/memory/`
  store (three-tier: `MEMORY.md` index ≤200 lines, `topics/*.md`, daily
  `logs/`) that the agent consolidates via the new `/dream` skill
  (`.github/skills/dream/SKILL.md`). The four-phase pass (Orient → Gather →
  Consolidate → Prune & Index) resolves contradictions, temporalizes dates,
  prunes stale entries, and dedups — sandboxed to write only inside the
  memory store. A lightweight waking-loop recorder (`dream-record-session`)
  and a dual-gate nudge (`dream-gate`, default ≥24h AND ≥5 sessions) live
  under `.assert-iq/dreaming/scripts/`.
- **Optional background dreamer** (`.assert-iq/dreaming/service/dreaming_service.py`)
  for teams that want "dream while you sleep" via cron. Off by default and
  inert unless `anthropic` is installed and `ANTHROPIC_API_KEY` is set; the
  core `/dream` skill has no dependency on it.
- Maturity-gated dreaming (early: manual `/dream`; mid: gate nudge; higher:
  may auto-fire / optional background service), a `dreaming:` block in
  `config.yaml`, governance sandbox rules, and a startup memory-index pointer
  in `qi-foundation.instructions.md`.
- `tests/_qi/automated/e2e-dreaming.{sh,ps1}` covering the recorder, gate,
  kill-switch, and write-sandbox.

### Changed
- **Retired Hindsight Hooks entirely.** Removed the top-level `hooks/` tree,
  `hooks.template.json`, the `skill-improve-*` / `track-telemetry` scripts,
  and the per-tool-call `PostToolUse` hook — the main token/memory cost this
  release addresses. Session-event wiring now renders from
  `.assert-iq/dreaming/session-events.template.json` into the
  `.claude/settings.json` `hooks` key (`SessionStart` + `Stop` only).
- Installers (`install.sh` / `install.ps1`), bootstrap (`bootstrap.sh` /
  `bootstrap.ps1`, new `--dreaming` flag with `--hooks` alias), `.gitignore`,
  `.vscode/settings.json`, and all docs (`.md` + sister `.html` + search
  index) rebranded from Hindsight Hooks to Dreaming.

### Removed
- The retrospective self-patching feature and its runtime state
  (`dismissed-lessons.json`, `edit-frequency.json`, per-session scratch).
  Cross-session learning now lives in the versioned `.assert-iq/memory/` store.

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