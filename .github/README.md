# The `.github/` folder — for GitHub Copilot in VS Code

This folder is the **GitHub Copilot half** of the Assert.IQ Agent Pack.
If you open this repository in Visual Studio Code and use Copilot Chat,
everything in here is loaded automatically.

You don't need to "install" anything — VS Code and Copilot read this
folder on their own.

---

## What's in here, in plain words

| Folder | What it is |
|---|---|
| `copilot-instructions.md` | The always-on guidance Copilot reads at the start of every chat. Think of it as Copilot's "house rules" for this repo. |
| `instructions/` | Extra rule sheets that switch on automatically when you open certain kinds of files (for example, when you're working on tests). |
| `skills/` | Step-by-step playbooks Copilot can run when you ask. Each one is a little expert. Type `/` in chat to see them. Examples: `/generate-bug-report`, `/code-review`, `/risk-assess-pr`. |
| `agents/` | Specialist agents you can pick from the chat agent dropdown. **`Assert-IQ`** is the default front door (full tools, routes to the right skill). **`Assert-IQ-PLAN`** is the read-only planning sibling — researches and writes a plan, then offers a **Start Implementation** button that hands off to `Assert-IQ`. |
| `../hooks/hooks.json` + `../hooks/scripts/` | Small background scripts that fire when Copilot does things (like saving a file). They keep telemetry and help the pack learn from your sessions. You don't interact with these directly. |

---

## How to start using it

1. **Open the repo in VS Code.** That's it for setup on the Copilot side.
2. **Open Copilot Chat** (the chat icon in the sidebar).
3. **Pick the `Assert-IQ` agent** from the agent dropdown at the top of
   the chat panel. It's the front door — it routes your question to the
   right skill and has full tools to act.
4. **Type `/`** to see the list of skills directly, or just ask a
   question in plain English — the right rule sheets will be applied
   automatically based on what file you're looking at.
5. **Want a plan first?** Switch to **`Assert-IQ-PLAN`** in the agent
   dropdown. It researches, writes a plan, then gives you a
   **Start Implementation** button that hands the plan back to
   `Assert-IQ` to execute.

---

## "Will this also work in Claude Code?"

Yes. The same content is mirrored to the `.claude/` folder at the repo
root. See [`.claude/README.md`](../.claude/README.md) for the Claude
side. You can use either tool — they share the same skills, instructions,
and hooks.

---

## Uninstalling the pack

**If you installed the pack as a plugin** (via `Chat: Install Plugin From
Source` or `@agentPlugins`):

1. Open the Extensions view (`⇧⌘X`) and search `@agentPlugins`.
2. In the **Agent Plugins — Installed** section, right-click `assert-iq`
   and choose **Uninstall** (or **Disable** to keep it on disk).
3. Or, from the Chat view: gear icon → **Plugins** → uninstall.
4. If anything sticks, manually delete the cached clone at
   `~/Library/Application Support/Code/agentPlugins/...` (macOS),
   `~/.config/Code/agentPlugins/...` (Linux), or
   `%APPDATA%\Code\agentPlugins\...` (Windows).

**If you installed via `chat.pluginLocations` in `settings.json`**, just
remove the entry (or set its value to `false` to disable).

**If you dropped the pack into the repo as files** (the "drop-in"
model — no plugin install), simply delete `.github/`, `.vscode/mcp.json`,
`.vscode/settings.json`, `hooks/`, `.claude-plugin/`, `.assert-iq/`,
`MANIFEST.md`, `README.assert-iq.md`, `AGENTS.md`, and `CLAUDE.md` from
the repo root.

---

## What the plugin install does **not** auto-wire — and how to fix it

The plugin install delivers **every file in the pack to disk**, but VS
Code and Copilot only auto-load some of them from the plugin install
directory. Eight surfaces have to live in the **workspace** (or a
user-global slot) to be picked up:

- `.github/copilot-instructions.md` — the always-on QI house rules
- `.github/instructions/qi-*.instructions.md` — the five `applyTo`
  rule sheets
- `CLAUDE.md` — the Claude-side always-on guidance (if you also use
  Claude Code)
- `AGENTS.md` — the generic agent-spec pointer
- `.assert-iq/` — per-client config (maturity tier, governance
  posture, signal schema). The `Assert-IQ` agent reads
  `.assert-iq/maturity-profile.md` and `.assert-iq/governance.md` on
  every quality/release question and silently falls back to defaults
  if they're missing.
- `.vscode/settings.json` + `.vscode/mcp.json` — wires Copilot to
  read instructions and prompts from `.github/`, and points
  `chat.hookFilesLocations` at `./hooks/hooks.json`. JSON
  deep-merged into any pre-existing files (additive — your scalar
  values win on conflicts; object keys union from both sides).
- `hooks/` (`scripts/`, `lib/`, `config/`, `hooks.json`) — the hook
  scripts themselves. `hooks.json` is rendered at bootstrap time so
  the script paths resolve to the workspace copies.
- `.claude/settings.json` — Claude Code reads its `hooks` block from
  here. Bootstrap merges only the `hooks` key, preserving anything
  else you have.

**Run `/assert-iq-bootstrap` once per new workspace.** The skill walks
you through where each surface should live (workspace / user-global /
skip), supports `solo` and `pod` presets, and copies the templates
from the plugin install directory into the right places. Cross-platform
(macOS, Linux, Windows). Pre-existing files are preserved (SHA256
compare + interactive resolver); JSON settings files are deep-merged.
Safe to re-run.

---

## Something feels off?

- Skill isn't appearing in `/` autocomplete? Make sure VS Code is reading
  this folder — open the repository at its root, not a subfolder.
- Need the full file map? See [`../MANIFEST.md`](../MANIFEST.md).
- Need the day-one onboarding doc? See
  [`../README.assert-iq.md`](../README.assert-iq.md).
