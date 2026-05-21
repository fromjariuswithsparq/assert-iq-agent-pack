# qi-signal-aggregator

A Model Context Protocol (MCP) server that produces decision-grade Quality
Intelligence signals from your repo. Implemented in Go; distributed as a
single static binary.

## Install

The pack's `install.sh` / `install.ps1` will fetch the latest release for
your platform automatically. To install manually:

```bash
# Pick your platform asset from https://github.com/assert-iq/qi-signal-aggregator/releases
curl -fsSL -o qisa.tgz \
  https://github.com/assert-iq/qi-signal-aggregator/releases/latest/download/qi-signal-aggregator_darwin_arm64.tar.gz
tar -xzf qisa.tgz
chmod +x qi-signal-aggregator
xattr -d com.apple.quarantine qi-signal-aggregator  # macOS only
mv qi-signal-aggregator ~/.local/bin/
```

To build from source (requires Go 1.23+):

```bash
cd mcp/qi-signal-aggregator
go build -o ~/.local/bin/qi-signal-aggregator ./cmd/qi-signal-aggregator
```

## Wire to your client

Copy the snippet for your tool from `clients/`:

- VS Code / Copilot: `clients/vscode-mcp.json` → `.vscode/mcp.json`
- Claude Code: `clients/claude-code.json` → `.mcp.json` (workspace) or `~/.claude.json`
- Codex CLI: paste the block in `clients/codex-cli.toml` into `~/.codex/config.toml`

## Test it

```bash
qi-signal-aggregator --config samples/config.yaml demo --id PR-001
qi-signal-aggregator health
```

`demo` runs a one-shot assessment against the fixture data in `samples/` and
prints the verdict as JSON. `health` reports configured adapters.

## Tools exposed (MCP)

| Tool | Returns |
|------|---------|
| `get_decision_confidence` | Full payload — all four layers + verdict + red flags |
| `assess_change` | Change layer only |
| `assess_protection` | Protection layer only |
| `assess_trust` | Trust layer only |
| `assess_outcome` | Outcome layer only |
| `emit_signal` | Record post-decision outcome (escape/hotfix/clean/rollback) |
| `health` | Server health + adapter inventory |

## Adapters (v0.1)

| Name | Layer | Mode |
|------|-------|------|
| `github` | change | fixture (v0.1) / live (v0.2) |
| `coverage_xml` | protection | reads Cobertura XML |
| `qi_traceability_scan` | protection | filesystem scan for `qi-trace:` markers |
| `junit_glob` | trust | aggregates JUnit XML across a glob |
| `sentry` | outcome | fixture (v0.1) / live (v0.2) |
| `jira` | outcome | fixture (v0.1) / live (v0.2) |

## Verdict integrity rule

A verdict is GREEN/GO only when **all four layers are STRONG and zero red
flags fire**. Any UNGRADED layer caps the verdict at AMBER/GO_WITH_MITIGATION.
Early-tier programs (per `.assert-iq/maturity-profile.md`) have all
GREEN/GO outputs further capped per CLAUDE.md.

## Parity

Six canonical scenarios under `testdata/golden/` lock the verdict output.
`go test ./internal/scoring/...` MUST stay green; any rubric change requires
deliberate regoldening.
