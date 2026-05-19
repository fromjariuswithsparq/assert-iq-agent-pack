# The `.claude/` folder — for Claude Code

This folder is the **Claude Code half** of the Assert.IQ Agent Pack.
If you use [Claude Code](https://docs.claude.com/claude-code) on this
repository, this is where Claude looks for its subagents, skills, and
hook settings.

---

## What's in here, in plain words

| Item | What it is |
|---|---|
| `agents/assert-iq.md` | The **default Assert.IQ subagent** — Quality Intelligence front door with full tools. Routes to the right skill and executes. Invoke with `@assert-iq`. |
| `agents/assert-iq-plan.md` | The **planning sibling** of `assert-iq`. Read-only — researches, writes a plan, and waits for your approval before handing off. Invoke with `@assert-iq-plan` when the task is large or risky. |
| `skills/` | Step-by-step playbooks Claude can run when you ask. This is a **symlink** to `.github/skills/`, so Copilot and Claude share the exact same set. Examples: `/generate-bug-report`, `/code-review`. |
| `settings.json` | Claude Code's settings file. The pack installer fills in the hooks section here (small background scripts that fire when Claude does things, like saving a file). |

The instructions ("house rules") that Copilot reads from
`.github/copilot-instructions.md` are mirrored for Claude in
`../CLAUDE.md` at the repo root.

---

## How to start using it

1. **Install Claude Code** if you haven't yet — see the
   [Claude Code docs](https://docs.claude.com/claude-code).
2. **Run the installer once**, from the repo root, to wire up hooks and
   skills:
   - macOS / Linux: `./install.sh`
   - Windows: `pwsh ./install.ps1`
   The installer is safe to re-run. It only updates this folder.
3. **Open the repo in Claude Code** and start chatting. Type `/` to see
   available skills, or `@assert-iq` to use the default Assert.IQ
   subagent. For plan-first behavior on a larger task, use
   `@assert-iq-plan` instead.

---

## "Will this also work in GitHub Copilot?"

Yes. The same content is mirrored to the `.github/` folder at the repo
root, and Copilot reads it automatically — no installer needed for the
Copilot side. See [`../.github/README.md`](../.github/README.md).

You can use either tool — they share the same skills, instructions, and
hooks.

---

## Uninstalling the pack

**If you installed the pack as a Claude Code plugin**, use the
`/plugin` slash command in Claude Code to list and remove it, or
manually delete the plugin from `~/.claude/plugins/`.

**If you installed the pack as files** (the "drop-in" model), just
delete `.claude/`, `CLAUDE.md`, and any of the shared roots (`.github/`,
`.vscode/`, `hooks/`, `.claude-plugin/`, `.assert-iq/`,
`README.assert-iq.md`, `AGENTS.md`, `MANIFEST.md`) you no longer need.

To disable just the hooks without removing the pack: open
`.claude/settings.json` and delete the `hooks` block (or set the
relevant matchers to `[]`). The installer will re-add them next time it
runs — if you want them gone permanently, also delete `hooks/hooks.json`.

---

## What the plugin install does **not** auto-wire — and how to fix it

The Claude plugin install delivers **every file in the pack to disk**,
but Claude Code only auto-loads some of them from the plugin install
dir. Three surfaces have to live in the **workspace** (or a user-global
slot) to be picked up:

- `CLAUDE.md` — the always-on QI guidance (and the `@`-imports it
  pulls in from `.github/instructions/qi-*.instructions.md`)
- `AGENTS.md` — the generic agent-spec pointer
- `.assert-iq/` — per-client config (maturity tier, governance
  posture, signal schema). The `assert-iq` subagent reads
  `.assert-iq/maturity-profile.md` and `.assert-iq/governance.md` on
  every quality/release question and silently falls back to defaults
  if they're missing.

**Run `/assert-iq-bootstrap` once per new workspace.** The skill walks
you through where each surface should live (workspace / user-global /
skip), supports `solo` and `pod` presets, and copies the templates
from the plugin install dir into the right places. Cross-platform
(macOS, Linux, Windows). Always skip-if-exists — safe to re-run.

---

## Something feels off?

- Skills not showing up? Make sure you ran `./install.sh` (or
  `install.ps1`) once. The skills folder here should be a link, not
  empty.
- Hooks not firing? Open `settings.json` and check the `hooks` section
  is filled in. If it's missing, re-run the installer.
- Need the full file map? See [`../MANIFEST.md`](../MANIFEST.md).
- Need the day-one onboarding doc? See
  [`../README.assert-iq.md`](../README.assert-iq.md).
