# QI Signal Aggregator — Samples

A self-contained fixture pack that exercises the server end-to-end with
**zero external dependencies, no secrets, no network**. Use it to:

- Verify the server is installed and wired correctly to your client.
- Demonstrate the four-layer model to a team.
- Smoke-test changes during development.

## What's here

| PR fixture        | Expected verdict       | Why                                              |
|-------------------|------------------------|--------------------------------------------------|
| `pr-001-green`    | `GREEN`                | Small clean diff, full signal, no issues.        |
| `pr-042-amber`    | `AMBER` (mitigation)   | Touches payment path (Change WEAK).              |
| `pr-099-red`      | `RED` (HOLD)           | Late-breaking shared-infra change + active P1.   |

All adapters are in **fixture mode** — they read JSON/XML from
`fixtures/` instead of hitting GitHub / Sentry / Jira.

## Recipe

From the repo root:

```bash
qi-signal-aggregator --config mcp/qi-signal-aggregator/samples/config.yaml demo
```

Expected output (last column trimmed):

```
PR                   VERDICT                STATES (C/P/T/O)
pr-001-green         GREEN                  S/S/S/S
pr-042-amber         AMBER                  W/S/S/S
pr-099-red           RED                    W/S/S/W
```

To exercise a single PR through the JSON-emitting CLI (CI path):

```bash
qi-signal-aggregator \
  --config mcp/qi-signal-aggregator/samples/config.yaml \
  emit --scope pr --id pr-042-amber
```

To run the MCP server against the samples and exercise it from a chat
client, point your client's MCP config at:

```
command: qi-signal-aggregator
args:    ["--config", "${workspaceFolder}/mcp/qi-signal-aggregator/samples/config.yaml"]
```

Then call `get_decision_confidence(scope="pr", identifier="pr-042-amber")`.

## Partial-signal proof

Disable any adapter in `samples/config.yaml` (comment its name out of
`signal_aggregator.adapters`) and re-run. The affected layer flips to
`UNGRADED`, `partial_signal_mode` becomes `true`, and the verdict is
capped at `AMBER` / `GO_WITH_MITIGATION` per the integrity rule.
