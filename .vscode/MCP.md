# MCP server setup guide

This folder's `mcp.json` wires 20 Model Context Protocol (MCP) servers into
VS Code Copilot Chat. Each server gives the agent a new tool surface —
GitHub, Jira, Playwright, Sentry, etc. This file explains how to turn each
one on.

> `mcp.json` only tells your editor **how** to launch / connect to each
> server. The servers themselves are remote services or npm/Python
> packages downloaded on demand. Removing an entry does not uninstall
> anything.

---

## Quick start (VS Code)

1. **Install the launchers** the servers depend on:
   ```bash
   # macOS
   brew install node uv          # node gives you npx; uv gives you uvx
   # verify
   node -v && npx -v && uvx --version
   ```
2. **Open the workspace** in VS Code. Make sure the GitHub Copilot Chat
   extension is installed and you're signed in.
3. **Open the MCP panel:** `Cmd+Shift+P` → **MCP: List Servers**. You should
   see all 20 entries from `mcp.json`. Most will be marked *Needs input*
   until you provide credentials.
4. **Start the credential-free ones first** to confirm your toolchain
   works: click **Start** on `git` and `playwright`. They should turn
   *Ready* and expose tools (e.g. `git_log`, `browser_navigate`).
5. **Enable the rest as you need them.** Click **Start** — VS Code will
   prompt for each `${input:…}` value. Secrets (marked with the lock icon)
   are stored in your OS keychain, not in `mcp.json`.

> To wipe a stored secret: `Cmd+Shift+P` → **MCP: Reset Inputs**.

---

## Quick start (Claude Code / Claude Desktop)

VS Code's `mcp.json` is not read by Claude. To use the same servers
there:

- **Claude Code (CLI):** for each server below, run
  ```bash
  claude mcp add <name> -- <command> <args...>
  ```
  Set env vars with `-e KEY=VALUE`. Example:
  ```bash
  claude mcp add git -- uvx mcp-server-git --repository "$PWD"
  claude mcp add sentry -e SENTRY_AUTH_TOKEN=... -e SENTRY_ORG=... -- uvx mcp-server-sentry
  ```
  List with `claude mcp list`, remove with `claude mcp remove <name>`.

- **Claude Desktop:** edit
  `~/Library/Application Support/Claude/claude_desktop_config.json` and add
  entries under `mcpServers`. Same `command` / `args` / `env` shape as
  `mcp.json`, but **no `${input:…}` substitution** — paste secrets
  literally (the file is local-only) or use shell env vars.

For each server below, the VS Code `mcp.json` block is the source of
truth; the Claude equivalent is the same command + args + env.

---

## The 20 servers

Servers are grouped by purpose. For each: what it does, what you need,
and where to get it.

### Code hosts & trackers

#### `github` — GitHub repos, PRs, issues
- **Transport:** remote HTTP (`api.githubcopilot.com/mcp/`).
- **You need:** GitHub personal access token (classic or fine-grained)
  with `repo`, `read:org`, `workflow` scopes.
- **Get it:** https://github.com/settings/tokens
- **Prompt:** `github_pat` (secret).

#### `azure-devops` — Azure DevOps work items, repos, pipelines
- **You need:** ADO org URL (e.g. `https://dev.azure.com/contoso`) and a
  PAT with **Work Items: Read & Write**, **Code: Read**, **Build: Read**.
- **Get it:** ADO → User settings → Personal access tokens.
- **Prompts:** `ado_org`, `ado_pat` (secret).

#### `atlassian` — Jira issues (and Confluence via the official server)
- **You need:** Jira site URL (`https://acme.atlassian.net`), your account
  email, and an API token.
- **Get token:** https://id.atlassian.com/manage-profile/security/api-tokens
- **Prompts:** `jira_base_url`, `jira_email`, `jira_api_token` (secret).

#### `gitlab` — GitLab projects, MRs, issues
- **You need:** GitLab PAT with `api` scope, and the API URL
  (`https://gitlab.com/api/v4` for SaaS, or your self-hosted URL).
- **Get it:** GitLab → Edit profile → Access tokens.
- **Prompts:** `gitlab_pat` (secret), `gitlab_api_url`.

#### `bitbucket` — Bitbucket Cloud workspaces, repos, PRs
- **You need:** workspace slug, your Bitbucket account email, and an
  **app password** with Repositories: Read, Pull requests: Read scopes.
- **Get it:** https://bitbucket.org/account/settings/app-passwords/
- **Prompts:** `bitbucket_workspace`, `bitbucket_email`,
  `bitbucket_app_password` (secret).
- **Note:** community package; multiple impls exist — see `mcp.json` for
  which one is wired.

### Local & filesystem

#### `git` — local git operations on this repo
- **Launcher:** `uvx` (install `uv` first).
- **You need:** nothing. Uses `${workspaceFolder}`.
- Exposes `git_log`, `git_diff`, `git_show`, `git_status`, etc. Useful
  for the QI four-layer "change risk" reasoning.

#### `filesystem` — scoped read/write to a directory
- **You need:** an absolute path the agent may touch. Pick something
  outside the repo if you want shared notes (e.g. `/Users/me/notes`),
  or the workspace itself if you want a second editing surface.
- **Prompt:** `fs_allowed_path`.
- **Warning:** the agent gets read+write on that path. Don't point it
  at your home directory.

### Databases

#### `postgres` — Postgres schema introspection + read-only queries
- **You need:** a connection string,
  `postgresql://user:pass@host:5432/db`. Prefer a read-only role.
- **Prompt:** `pg_connection_string` (secret).

#### `sqlite` — local SQLite inspection
- **Launcher:** `uvx`.
- **You need:** absolute path to a `.sqlite` / `.db` file.
- **Prompt:** `sqlite_db_path`.

### Cloud

#### `aws` — AWS resource lookup (CloudWatch, S3, IAM, etc.)
- **Launcher:** `uvx` (AWS Labs server).
- **You need:** a named profile already present in `~/.aws/credentials`,
  and a default region. Credentials are read from your AWS config — they
  do **not** live in `mcp.json`.
- **Set up profile (once):** `aws configure --profile dev`.
- **Prompts:** `aws_profile`, `aws_region`.

### Observability (QI "outcome evidence" layer)

#### `sentry` — recent issues, events, releases
- **Launcher:** `uvx`.
- **You need:** Sentry auth token with `event:read`, `project:read`,
  `org:read`, and your org slug.
- **Get token:** Sentry → Settings → Auth Tokens.
- **Prompts:** `sentry_token` (secret), `sentry_org`.

#### `grafana` — query dashboards & Prometheus through Grafana
- **You need:** Grafana base URL and a service account API key
  (Viewer role is enough).
- **Get key:** Grafana → Administration → Service accounts.
- **Prompts:** `grafana_url`, `grafana_api_key` (secret).

#### `datadog` — logs, metrics, monitors
- **You need:** Datadog API key + Application key + your site
  (`datadoghq.com`, `datadoghq.eu`, `us3.datadoghq.com`, …).
- **Get keys:** Datadog → Organization Settings → API/Application Keys.
- **Prompts:** `dd_api_key` (secret), `dd_app_key` (secret), `dd_site`.

#### `honeycomb` — traces, queries, SLOs
- **You need:** Honeycomb API key (environment-scoped is preferred).
- **Get it:** Honeycomb → Account → API Keys.
- **Prompt:** `honeycomb_api_key` (secret).

### Browser automation (UI testing)

#### `playwright` — drive a real Chromium/Firefox/WebKit browser
- **You need:** nothing for credentials. First launch downloads browsers
  (~300 MB).
- Direct fit with the `debug-ui-tests` and `generate-automated-ui-test`
  skills.

#### `puppeteer` — lighter headless-Chrome alternative
- **You need:** nothing. Useful when Playwright is overkill.

### Knowledge bases

#### `notion` — pages, databases, search
- **You need:** a Notion **internal integration** token, and you must
  *share* the relevant pages/databases with the integration.
- **Get it:** https://www.notion.so/profile/integrations
- The server expects an `OPENAPI_MCP_HEADERS` JSON string, e.g.
  ```json
  {"Authorization":"Bearer secret_xxx","Notion-Version":"2022-06-28"}
  ```
- **Prompt:** `notion_headers` (secret) — paste the whole JSON blob.

#### `confluence` — Confluence pages and spaces (sibling of `atlassian`)
- **Launcher:** `uvx mcp-atlassian --confluence-only`.
- **You need:** nothing new — reuses the Jira inputs (`jira_base_url`,
  `jira_email`, `jira_api_token`). Make sure your API token has
  Confluence access (default tokens do).

### Communication

#### `slack` — channel history, search, post messages
- **You need:** a Slack bot token (`xoxb-…`) and your workspace's
  team ID (`T0…`).
- **Get bot token:** create an app at https://api.slack.com/apps → add
  bot scopes (`channels:history`, `channels:read`, `chat:write` if
  posting), install to workspace, copy Bot User OAuth Token.
- **Get team ID:** Slack web → workspace URL `https://app.slack.com/client/T0XXXXX/...` (the `T0…` part).
- **Prompts:** `slack_bot_token` (secret), `slack_team_id`.

#### `teams` — Microsoft Teams channels and chats
- **You need:** an Entra app registration with delegated/application
  permissions for Teams (`ChannelMessage.Read.All`,
  `Chat.Read.All` as needed).
- **Set up:** Entra portal → App registrations → New registration →
  copy Application (client) ID, Directory (tenant) ID, and create a
  client secret.
- **Prompts:** `teams_app_id`, `teams_app_password` (secret),
  `teams_tenant_id`.
- **Note:** community package; confirm the impl in `mcp.json` matches
  your auth flow (some variants use device-code instead of client
  secret).

---

## Troubleshooting

- **Server stuck at *Starting…* :** open the MCP server's output panel
  (click the server name in **MCP: List Servers**) for stderr.
- **`uvx: command not found`:** install `uv` (`brew install uv`) and
  restart VS Code.
- **`npx` re-downloading every launch:** that's normal the first time;
  subsequent launches use the npm cache.
- **Auth error after rotating a token:** `MCP: Reset Inputs`, then
  restart the server.
- **Too many tools, agent gets confused:** disable servers you aren't
  using — click **Stop** in the MCP panel. They re-enable in one click.
- **Want to share credentials across machines:** don't put them in
  `mcp.json` (it's committed). Use 1Password / your secret manager and
  paste at prompt time.

---

## Security notes

- `mcp.json` is safe to commit — every secret is referenced via
  `${input:…}` and lives in your OS keychain, not the file.
- Treat every MCP server as having the privileges of the token you
  give it. Prefer **read-only / least-privilege tokens** where the
  agent doesn't need writes.
- The agent will send tool inputs to whatever endpoint the server
  points at. Don't wire production-write tokens to servers you haven't
  vetted.
