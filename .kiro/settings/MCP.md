# Kiro MCP configuration

Companion to `.kiro/settings/mcp.json`. This is the Kiro counterpart to
`.vscode/MCP.md`, and the two configs are **not interchangeable** — see
"How this differs from `.vscode/mcp.json`" below.

Schema contract: `.assert-iq/kiro-harness.md` §5.

## Everything ships disabled

All 20 servers carry `"disabled": true`. Enable only what you actually use:
each stdio server spawns an `npx` or `uvx` process, and enabling all twenty
would start twenty subprocesses on every session for no benefit. Flip
`disabled` to `false` on the ones you need.

Workspace config merges over user-global (`~/.kiro/settings/mcp.json`), so a
personal credential set can live in your home directory while the workspace
file stays committed and secret-free.

## Two steps, not one — the part that silently fails

Setting the environment variable is **not sufficient**. Kiro expands
`${VAR}` in `mcp.json` only for variables you have **approved**, via the
`kiroAgent.mcpApprovedEnvVars` setting. An unapproved variable is left in
place as the literal string `${ADO_PAT}` — so the server starts, sends
`Authorization: Bearer ${ADO_PAT}`, and fails to authenticate with no
indication that a substitution didn't happen.

So for each server you enable:

1. **Export the variable** in the environment Kiro is launched from.
2. **Approve the variable name** in `kiroAgent.mcpApprovedEnvVars`.

Only `${LETTERS_DIGITS_UNDERSCORE}` is recognized — the expander's pattern is
`\$\{([A-Za-z_][A-Za-z0-9_]*)\}`. No `${input:...}`, no `$VAR`, no
`%VAR%`.

If a tracker lookup fails, check both steps before assuming the server is
broken. And per the QI rules in `.kiro/steering/qi-foundation.md`: a signal
you cannot fetch is **UNGRADED with a reason**, never fabricated.

## Environment variables by server

| Server | Variables |
|---|---|
| `github` | `GITHUB_PAT` |
| `azure-devops` | `ADO_ORG`, `ADO_PAT` |
| `atlassian`, `confluence` | `JIRA_BASE_URL`, `JIRA_API_TOKEN`, `JIRA_EMAIL` |
| `git` | `AIQ_REPO_PATH` |
| `gitlab` | `GITLAB_PAT`, `GITLAB_API_URL` |
| `bitbucket` | `BITBUCKET_WORKSPACE`, `BITBUCKET_EMAIL`, `BITBUCKET_APP_PASSWORD` |
| `filesystem` | `FS_ALLOWED_PATH` |
| `postgres` | `PG_CONNECTION_STRING` |
| `sqlite` | `SQLITE_DB_PATH` |
| `aws` | `AWS_PROFILE`, `AWS_REGION` |
| `sentry` | `SENTRY_TOKEN`, `SENTRY_ORG` |
| `grafana` | `GRAFANA_URL`, `GRAFANA_API_KEY` |
| `datadog` | `DD_API_KEY`, `DD_APP_KEY`, `DD_SITE` |
| `honeycomb` | `HONEYCOMB_API_KEY` |
| `notion` | `NOTION_HEADERS` |
| `slack` | `SLACK_BOT_TOKEN`, `SLACK_TEAM_ID` |
| `teams` | `TEAMS_APP_ID`, `TEAMS_APP_PASSWORD`, `TEAMS_TENANT_ID` |
| `playwright`, `puppeteer` | none |

Which ones QI actually needs: the **tracker** (`azure-devops` /
`atlassian` / `github`) for work-item lookups behind traceability and
`/risk-assess-pr`, and `git` for change-layer signals. Everything else is
optional enrichment for the Outcome layer (`sentry`, `datadog`, `grafana`,
`honeycomb`) or for test execution (`playwright`, `puppeteer`).

## How this differs from `.vscode/mcp.json`

Four differences, each of which breaks the config if carried over unchanged:

| | VS Code | Kiro |
|---|---|---|
| Top-level key | `servers` | **`mcpServers`** |
| Transport | explicit `"type": "stdio"` / `"http"` | **inferred** from `command` vs `url`; no `type` field |
| Credentials | `${input:id}` + an `inputs[]` array that **prompts** the user | **`${ENV_VAR}`**, read from the environment and gated by an approval list |
| Repo path | `${workspaceFolder}` | no equivalent — it would be read as an env var named `workspaceFolder`, not found, and left literal. This config uses `${AIQ_REPO_PATH}` instead. |

The `inputs[]` array is gone entirely: Kiro has no prompt mechanism, so
there is nothing to translate it into. That is the reason credentials moved
to environment variables rather than staying in the file — a committed config
must never carry a token.

## Regenerating

`.kiro/settings/mcp.json` was translated once from `.vscode/mcp.json` and is
now **hand-maintained** — it is not generated, and no `--check` guards it. If
you add a server to the VS Code config and want it on Kiro too, add it here
by hand and follow the table above. Deliberate: the two files have diverged
in credential model, and a generator would have to encode enough judgment
(which env var name, which servers matter) that it would be lying about
being mechanical.
