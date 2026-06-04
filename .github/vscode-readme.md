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
root. See [`.claude/claude-readme.md`](../.claude/claude-readme.md) for the Claude
side. You can use either tool — they share the same skills, instructions,
and hooks.

---

## Uninstalling the pack

There are exactly two install paths and each has a matching uninstall.

**Path A — pack-as-workspace** (`bash install.sh` / `pwsh ./install.ps1`
at the root of the cloned pack):

```bash
bash install.sh --uninstall          # macOS / Linux / WSL
pwsh ./install.ps1 -Uninstall        # Windows
```

That removes `.claude/skills`, the rendered `hooks/hooks.json`, and the
`hooks` key from `.claude/settings.json` (preserving any other keys you
had). The committed pack files (`.github/`, `CLAUDE.md`, `AGENTS.md`,
the `hooks/` scripts and template) remain — delete them or `git rm`
them when you're done with the clone.

**Path B — codebase install** (`/assert-iq-bootstrap` or
`bash scripts/bootstrap.sh --mode=trial` inside your target repo):

```bash
bash scripts/bootstrap.sh --uninstall            # macOS / Linux
bash scripts/bootstrap.sh --uninstall --user     # also remove user-global copies
bash scripts/bootstrap.sh --uninstall --dry-run  # preview without changes
pwsh -File scripts/bootstrap.ps1 -Uninstall      # Windows
```

The uninstall reads `.assert-iq/.install-manifest.json`, restores any
pre-existing files from their `<file>.assert-iq.pre-install` snapshots,
removes pack-owned files (including `.github/skills/`, `.github/agents/`,
`.claude/agents/`, and the `.claude/skills` symlink), strips the
trial-mode block from `.git/info/exclude`, and clears `hooks/state`,
`hooks/logs`, and `hooks/sessions`. Files you edited post-install are
preserved at `<file>.assert-iq.uninstall-saved` so nothing is silently
lost.

---

## What the bootstrap does **not** auto-wire — and how to fix it

The bootstrap delivers **every file in the pack to disk** at the right
location, but VS Code and Copilot only auto-load some of them from a
specific set of paths. Eight surfaces have to live in the **workspace**
(or a user-global slot) to be picked up:

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

**Run the bootstrap script once per new workspace.** From a terminal
inside your target repo:

```bash
bash /path/to/assert-iq-agent-pack/scripts/bootstrap.sh --mode=trial
# Windows: pwsh -File <pack>\scripts\bootstrap.ps1 -Mode trial
```

The script walks you through where each surface should live (workspace
/ user-global / skip), supports `solo`, `pod`, and `portable` presets,
and copies the templates from the cloned pack into the right places.
Cross-platform (macOS, Linux, Windows). Pre-existing files are
preserved (SHA256 compare + interactive resolver); JSON settings files
are deep-merged and snapshotted to `<file>.assert-iq.pre-install` for
clean uninstall.

> **Skills in every workspace, no per-repo install?** Use
> `--preset=portable` (or `--skills-scope=user`) to land skills at
> `~/.agents/skills/` (VS Code Copilot Chat). The workspace still gets
> `.github/agents/`, `.claude/agents/`, and the install manifest, but
> instructions, hooks, settings, and MCP config stay out.

> If the cloned pack itself is open in VS Code, or its skills are
> installed user-globally to `~/.agents/skills/`, the same wizard is
> available from chat as `/assert-iq-bootstrap`.
Safe to re-run.

---

## Something feels off?

- Skill isn't appearing in `/` autocomplete? Make sure VS Code is reading
  this folder — open the repository at its root, not a subfolder.
- Need the full file map? See [`../MANIFEST.md`](../MANIFEST.md).
- Need the day-one onboarding doc? See
  [`../README.assert-iq.md`](../README.assert-iq.md).
