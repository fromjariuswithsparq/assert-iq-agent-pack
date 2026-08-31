# Kiro harness contract

**Read this before changing anything under `.kiro/`.** Every claim below was
verified against a real Kiro install — `1.0.337`, Windows — by reading the
zod schemas and system prompts inside
`resources/app/extensions/kiro.kiro-agent/dist/extension.js`, **not** from
kiro.dev docs. Where the two disagree, this file records the binary and says
so. The docs are wrong in at least three places that would have shipped
broken files.

Kiro is the pack's **third harness**, alongside Claude Code and VS Code
Copilot. It reads none of `.github/*`, none of `.claude/*`, and no
`CLAUDE.md`. The only surface the pack already had that Kiro reads natively
is the root `AGENTS.md`.

---

## 1. Where Kiro reads from

| Surface | Workspace | User-global |
|---|---|---|
| Steering (instructions) | `.kiro/steering/*.md` | `~/.kiro/steering/` |
| Skills | `.kiro/skills/<name>/SKILL.md` | `~/.kiro/skills/` |
| Agents | `.kiro/agents/*.md` | `~/.kiro/agents/` |
| Hooks | `.kiro/hooks/*.json` | `~/.kiro/hooks/` |
| MCP | `.kiro/settings/mcp.json` | `~/.kiro/settings/mcp.json` |
| Specs | `.kiro/specs/<feature>/` | — |
| AGENTS.md | workspace root + subdirectories | `~/.kiro/steering/` |

Workspace beats user-global on conflict.

---

## 2. Steering

Frontmatter schema (`SteeringContextFrontMatterSchema`) — every field
optional/nullable:

```
inclusion:        "always" | "fileMatch" | "manual" | "auto"
fileMatchPattern: string | string[]
name:             string
description:      string
```

- **Absent `inclusion` means `always`.** The filter is
  `config?.inclusion === "always" || !config?.inclusion`.
- `fileMatch` **requires** `fileMatchPattern`; a sibling schema enforces
  `"fileMatchPattern required when inclusion is fileMatch"`. A `fileMatch`
  file without a pattern is inert.
- `auto` **requires `description`** — without one, Kiro logs
  `Progressive steering file missing description` and **drops the file
  silently**. The pack does not use `auto` for that reason.
- `manual` files become slash commands, surfaced as `#name` in chat.
- `fileMatchPattern` accepts a string **or an array**. The pack always emits
  an array, even for one pattern, so the shape never varies.

### `#[[file:<relative_path>]]`

A context-reference mechanism (supports `:startLine-endLine`). The pack
**does not use it** to point steering at `.github/instructions/`. A dangling
reference — a Kiro-only consumer who never installed `.github/` — degrades
silently, which is the failure mode this pack has been bitten by repeatedly
(Dreaming dead under Claude Code while alive under Copilot; the pack test
suite reporting 9 false failures in consumer workspaces). Generated steering
plus a `--check` mode fails **loudly** instead. See §7.

### AGENTS.md

Kiro discovers `AGENTS.md` at the workspace root and in subdirectories, and
treats it as steering with `source: "agents-md"`. A **root** `AGENTS.md` gets
`inclusion: always`; a **nested** one gets `inclusion: fileMatch` scoped to
its own directory. AGENTS.md does not support inclusion modes of its own.

### Not an import path

Kiro ships an `import-steering` feature, but `AI_ASSISTANT_CONFIGS` covers
only Cursor, Windsurf, Amazon Q and Cline — and
`getAvailableAIAssistantTypes()` filters to entries that have a `parser`, so
**only Cursor is actually importable**. There is no Copilot
(`.github/instructions/`) or Claude (`CLAUDE.md`) importer. Nothing to lean
on; the pack generates its own steering.

---

## 3. Agents

**The public docs say `.kiro/agents/*.json`. The binary disagrees**, and
Kiro's own bundled agent-authoring guidance is explicit:

> "IMPORTANT: Agent files MUST be markdown files with .md extension"

Agents are **markdown with YAML frontmatter**, parsed by
`custom-agent-parser`. Empty frontmatter is a hard error
(`"No front matter found"`). This is why the pack's Kiro specialists are
generated as `.md`, not JSON — and why the generator is a frontmatter
transform rather than a format conversion.

Frontmatter schema (`R31`):

```
name?           string (min 1)
description?    string
tools?          string | string[]
excludedTools?  string[]
model?          string
effortLevel?    string
includeMcpJson? boolean  (default false)
includePowers?  boolean  (default false)
mcpServers?     object
resources?      unknown[]   -- invalid entries are DROPPED SILENTLY
permissions?    { rules: [{capability, match?, exclude?, effect: allow|deny|ask}], policies?: string[] }
welcomeMessage? string
dispatchKind?   "sub-agent" | "custom-agent" | "spec"
hooks?          object
```

Body after the frontmatter is the system prompt.

### CLI-only fields — do not use in the IDE

`b34 = ["allowedTools", "toolsSettings"]` is the parser's
**`hasCliOnlyFields`** list. Both are ignored by the IDE. The public docs
recommend `allowedTools` for auto-approval and `toolsSettings.subagent` for
`availableAgents`/`trustedAgents`; neither does anything in the IDE. The
pack emits neither. (`keyboardShortcut`, `toolAliases` and
`useLegacyMcpJson` appear in the docs but nowhere in the IDE bundle.)

### Tool tags, not tool names

Kiro's own guidance: *"Use tags exclusively instead of specific tool names.
This ensures your custom agent definitions remain stable as tools are renamed
or reorganized."* Underlying names churn (`fs_write` / `fsWrite` /
`str_replace` all coexist); tags do not.

| Tag | Covers |
|---|---|
| `read` | read_file(s), read_code, list_directory, file_search, grep_search, get_diagnostics |
| `write` | fs_write, fs_append, str_replace, delete_file, edit_code |
| `shell` | execute_bash, control_bash_process, list_processes, get_process_output |
| `web` | web search + fetch tools |
| `spec` | taskList, taskGet, taskUpdate, getUserInput |
| `context` | memory / learnings / steering tools |
| `subagent` | subagent delegation |
| `@builtin` | all built-ins (excludes hooks, mcp, powers) |
| `@mcp`, `@powers` | MCP / Powers tools |
| `*` | everything |

### Subagents — and the trap

`dispatchKind: "sub-agent"` marks an agent as delegable. An orchestrator
needs `subagent` in its own `tools`. Sub-agents run in parallel, each with
its own context window, and the main agent waits for all of them.

**The trap:** custom agents do **not** inherit steering or skills. They load
only what their `resources` list names. An Assert.IQ specialist without

```yaml
resources:
  - "file://.kiro/steering/**/*.md"
  - "skill://.kiro/skills/**/SKILL.md"
```

runs with **no QI rulebook at all** — and because invalid `resources`
entries are dropped silently, a typo there is invisible. Every generated
Kiro agent in this pack carries both globs, and
`unit-kiro-schema.py` fails the build if one is missing.

---

## 4. Hooks

File: `.kiro/hooks/<anything>.json` — the loader accepts any `.json` in the
directory.

Schema (`s5` / `r2`), verified:

```
{
  "version": "v1",                    // literal, required
  "hooks": [                          // min 1 entry
    {
      "name":        "string",        // REQUIRED, min length 1
      "description": "string",        // optional
      "trigger":     "SessionStart",  // REQUIRED
      "matcher":     "regex",         // optional
      "action":      { "type": "command", "command": "..." },
      "timeout":     60,              // optional, integer seconds, >= 0; 0 = no timeout
      "enabled":     true,            // optional
      "confirm":     { ... }          // optional
    }
  ]
}
```

`action` is a discriminated union on `type`:

- `{ "type": "command", "command": <non-empty string> }`
- `{ "type": "agent",   "prompt":  <non-empty string> }`

Triggers (`V2_HOOK_TRIGGERS`):
`PostFileCreate`, `PostFileSave`, `PostFileDelete`, `PreToolUse`,
`PostToolUse`, `UserPromptSubmit`, `SessionStart`, `Stop`, `PreTaskExec`,
`PostTaskExec`, `Manual`.

Blocking: `PreToolUse`, `UserPromptSubmit`, `PreTaskExec`.
Tool-matching: `PreToolUse`, `PostToolUse` (matcher tests the tool name).
File-matching: the three `PostFile*` (matcher tests the file path).

### Naming, which is genuinely confusing

The **file literal is `"version": "v1"`**, but internally Kiro calls this
shape its *v2 schema* (`featureFlags.v2Hooks`, `"Hook file does not match v2
schema"`, `hooksFromNewFormat`). The **deprecated** format — a single
`{when:{type:"fileEdited"...}, then:{type:"askAgent"...}}` object, still
present in the bundle as `extension-resources/hook.json` — is what the code
calls a *v1 hook*, and it is auto-migrated on activation. Write
`"version": "v1"`. Ignore `extension-resources/hook.json`; it is the
schema for the format being migrated away from, and it has no
shell-command action at all.

### Execution contract — matters for Dreaming

Verified at the spawn site:

- **`${WORKSPACE_ROOT}` is substituted** into `action.command` (replaced with
  the hook's `cwd`). It is the **only** substitution. This is Kiro's
  equivalent of `CLAUDE_PLUGIN_ROOT`, and it means the pack root does **not**
  have to be baked in at install time the way the Copilot `session-events`
  path does — provided the pack is installed in the workspace.
- There is **no `KIRO_*` env var** carrying the workspace or plugin root.
- Commands run with **`shell: true`** — so `cmd.exe` on Windows and `/bin/sh`
  on POSIX. Neither bash-isms nor PowerShell syntax are safe unquoted. The
  pack's hook commands name their interpreter explicitly, and the installer
  renders a POSIX or Windows variant accordingly.
- `cwd` is the workspace root; env is inherited (`{...process.env}`).
- The hook receives the **session context as JSON on stdin**
  (`session_id`, `hook_event_name`, `cwd`, plus per-trigger fields).
- `timeout` is **seconds** (converted to ms; `0` disables).

### Hooks do not run in an untrusted workspace

`hooks.v2.executionDisabledUntrustedWorkspace` — if the user has not trusted
the folder, hooks silently do not execute. Any "Dreaming isn't recording"
report under Kiro should check workspace trust first.

---

## 5. MCP

`.kiro/settings/mcp.json`. Top-level key is **`mcpServers`** (VS Code uses
`servers`). Per-server:

- local: `command` (required), `args`, `env`, `disabled`, `autoApprove`,
  `disabledTools`
- remote: `url` (required), `headers`, `oauth`, plus the same three

There is **no `type` field** — stdio vs http is inferred from
`command` vs `url`. Workspace merges over user-global.

**No `${input:...}`.** VS Code's `mcp.json` prompts the user for
`${input:github_pat}` and friends; Kiro has no equivalent, only `${VAR}`
environment expansion. The pack's Kiro `mcp.json` therefore ships every
server `disabled: true` with `${ENV_VAR}` placeholders and a header
explaining which variables to export. Silently emitting `${input:...}` into
a Kiro config would produce servers that fail to authenticate with no
indication why.

---

## 6. Skills

`.kiro/skills/<name>/SKILL.md`. Kiro implements the Agent Skills standard:

- Required frontmatter: `name` (≤64 chars, must match the folder name) and
  `description` (≤1024 chars, states when to use it).
- Invoked automatically when a request matches the description, or manually
  as `/<name>`.
- **Default agents load skills automatically. Custom agents do not** — see
  the §3 trap.

Because the contract matches `.github/skills/` exactly, `.kiro/skills` is a
**symlink to `../.github/skills`**, same as `.claude/skills`, with a copy
fallback where symlinks are unavailable. Skills cannot drift across three
harnesses.

---

## 7. What is generated, and what is hand-authored

| Path | Source of truth | Generator |
|---|---|---|
| `.kiro/steering/qi-*.md` | `.github/instructions/*.instructions.md` | `scripts/sync-kiro.sh` / `.ps1` |
| `.kiro/agents/<specialist>.md` | `.claude/agents/specialists/*.md` | `scripts/sync-kiro.sh` / `.ps1` |
| `.kiro/steering/00-assert-iq.md` | itself — hand-authored | — |
| `.kiro/agents/assert-iq.md` | itself — hand-authored | — |
| `.kiro/agents/assert-iq-plan.md` | itself — hand-authored | — |
| `.kiro/hooks/*.json` | `.assert-iq/dreaming/kiro-hooks.*.template.json` | installer |
| `.kiro/settings/mcp.json` | `.vscode/mcp.json` (translated once) | hand-maintained |

The lead and planner are **not** generated, for the same reason they are not
generated for Copilot: their prose is harness-specific — Kiro has specs,
`#[[file:]]`, `dispatchKind` and Powers with no Claude equivalent. Rendering
one from the other would destroy correct hand-authored content. Their one
mechanical property — that every shipped skill is routable — is enforced by
check P3 in `e2e-agent-parity.sh`.

Staleness is enforced by `sync-kiro.sh --check` and by checks **P7/P8** in
`.assert-iq/tests/_qi/automated/e2e-agent-parity.sh`. Edit the source, then
re-run the sync. Never edit a generated file: the header says so, and the
next sync reverts it.

---

## 8. Known gaps and unverified claims

- `effortLevel` accepts a string; the valid values are not enumerated in the
  bundle. The pack does not set it.
- `permissions.rules[].capability` values are typed as bare `string` in the
  IDE parser, so the doc list (`fs_read`, `fs_write`, `shell`, `web_fetch`,
  `web_search`, `mcp`, `subagent`) is unvalidated there. The pack does not
  set `permissions`.
- `includePowers` / `@powers` — Kiro Powers are out of scope for this pack.
- Brace expansion in `fileMatchPattern` (`**/*.{ts,tsx}`) is **not**
  confirmed. `sync-kiro` expands braces into explicit array entries rather
  than betting on it. This matters for the traceability instruction, whose
  `applyTo` is one 22-extension brace group.
- Whether `~/.kiro/steering/` and workspace steering are additive or
  last-write-wins per file **name** is not verified. The pack prefixes its
  steering files (`qi-`, `00-assert-iq`) to make collisions unlikely.
