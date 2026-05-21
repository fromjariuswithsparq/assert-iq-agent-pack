---
applyTo: ".github/workflows/**, azure-pipelines.yml, **/*.gitlab-ci.yml, Jenkinsfile"
description: "CI must emit QI outcome signals in a standard schema."
---

# Signal emission instructions

**When this applies:** authoring or modifying CI configuration — GitHub
Actions workflows (`.github/workflows/**`), Azure Pipelines
(`azure-pipelines.yml`), GitLab CI (`**/*.gitlab-ci.yml`), or Jenkins
(`Jenkinsfile`). Copilot loads via `applyTo`; Claude Code: apply whenever
the user is editing pipeline definitions.

CI pipelines in this repository must emit a QI outcome payload at the end of
every test run. The payload schema is defined in `.assert-iq/signal-schema.json`.

When generating or modifying CI configuration:

1. **Prefer the QI Signal Aggregator CLI shim** if the
   `qi-signal-aggregator` package is installed on the runner. It produces
   a schema-conformant payload (schema_version `0.2.0`) without
   per-pipeline glue code:

   ```bash
   qi-signal-aggregator emit --scope pr --id "$PR_NUMBER" \
     > qi-signal-$BUILD_ID.json
   ```

   The CLI runs the same orchestrator the MCP server uses (no second
   server), so verdicts in CI match verdicts in the IDE. Install in the
   pipeline by fetching the right asset from the
   [GitHub Releases](https://github.com/assert-iq/qi-signal-aggregator/releases)
   page (single static binary, no runtime). Or build from source with
   `go install github.com/assert-iq/qi-signal-aggregator/cmd/qi-signal-aggregator@latest`.

2. **Fallback (manual payload)** — when the aggregator is unavailable,
   assemble a v0.2 payload yourself. Required fields:
   - `schema_version: "0.2.0"`, `run_id`, `commit_sha`, `scope`,
     `identifier`, `maturity_tier`, `partial_signal_mode`
   - `layers.{change,protection,trust,outcome}` — each with `state`
     (`STRONG | WEAK | UNGRADED`), `metrics`, and `evidence: []`
   - `red_flags: []`
   - `verdict.{band, mitigation_required, rationale}`

3. Publish the payload to the configured sink (file artifact, webhook,
   or telemetry endpoint per `config.yaml`).

4. Mask secrets. Never include raw stack traces with file paths from
   secret stores. The aggregator's audit log already strips secrets.

5. Tag the run with `maturity_tier` from `.assert-iq/config.yaml` so
   consumers can interpret which signals are available.
