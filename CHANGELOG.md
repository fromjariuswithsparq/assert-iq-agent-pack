# Changelog

All notable changes to the Assert.IQ Agent Pack are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.0.0]: https://github.com/fromjariuswithsparq/assert-iq-agent-pack/compare/v0.9.0...v1.0.0
[0.9.0]: https://github.com/fromjariuswithsparq/assert-iq-agent-pack/compare/v0.8.0...v0.9.0
