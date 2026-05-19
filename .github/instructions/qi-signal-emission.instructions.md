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

1. Add a final step that publishes the outcome payload to the configured sink
   (file artifact, webhook, or telemetry endpoint per `config.yaml`).
2. The payload must include:
   - `run_id`, `commit_sha`, `branch`, `pr_id` (if applicable)
   - `change_layer`: { files_changed, services_touched, churn, late_changes }
   - `protection_layer`: { tests_executed, coverage_pct, traceability_pct }
   - `trust_layer`: { flaky_count, blocked_count, env_uptime_pct }
   - `outcome_layer`: { defects_open, escapes_30d, telemetry_alerts }
   - `decision_layer`: { release_confidence, mitigation_required }
3. Mask secrets. Never include raw stack traces with file paths from secret stores.
4. Tag the run with the maturity tier from `.assert-iq/config.yaml` so consumers
   can interpret which signals are available.
