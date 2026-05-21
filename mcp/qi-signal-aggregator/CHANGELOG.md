# Changelog — qi-signal-aggregator

## Unreleased

- New adapters: `ado_repos` (Change layer) and `ado_boards` (Outcome layer)
  for Azure DevOps. Both support fixture mode and live HTTP mode (PAT from
  `ADO_TOKEN` by default; configurable via `secret_key`). Emits the same
  canonical metric keys as `github` / `jira` so red-flag detection is
  identical regardless of source.
- `samples/config.yaml` now wires every built-in adapter, including the
  two ADO ones, against bundled fixtures.

## v0.2.0 — Go rewrite

**Breaking:** Python implementation removed. The server is now a single
static Go binary distributed via GitHub Releases. No Python runtime needed.

- Reimplemented in Go 1.23 with the official MCP Go SDK
  (`github.com/modelcontextprotocol/go-sdk`).
- Distribution: GitHub Releases, 5-target matrix
  (darwin-arm64/amd64, linux-amd64/arm64, windows-amd64), SHA256-verified.
- Parity: 6/6 scoring scenarios in `testdata/golden/` reproduce the Python
  reference verbatim (GREEN/AMBER/RED, mitigation flags, tier capping,
  red-flag IDs).
- Adapters compile in (static registry). Custom adapter subprocess
  protocol deferred to v0.3.
- `install.sh` / `install.ps1` detect OS+arch, fetch the right asset,
  verify SHA256, strip macOS quarantine, drop the binary in
  `~/.local/bin/` (Unix) or `%LOCALAPPDATA%\qi-signal-aggregator\bin\` (Windows).

## v0.1.0 — Python reference (deleted)

- Initial release: Python 3.11 + `mcp` SDK, distributed as a pipx-installable
  source tree. Removed in v0.2 because corp Artifactory SSL blocked pip
  installs for some users; the Go binary has no such hop.
