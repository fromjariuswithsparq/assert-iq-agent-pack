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
| `skills/` | Step-by-step playbooks Claude can run when you ask. This is a **symlink** to `.github/skills/`, so Copilot and Claude share the exact same set. Examples: `/generate-bug-report`, `/code-review`. On **Windows without Developer Mode**, the installer falls back to copying the folder — in that case, re-run `install.ps1` after editing any skill. See [README.assert-iq.md → Platform notes](../README.assert-iq.md#platform-notes-claudeskills-symlink) for the full matrix. |
| `settings.json` | Claude Code's settings file. The pack installer fills in the hooks section here (small background scripts that fire when Claude does things, like saving a file). |

The instructions ("house rules") that Copilot reads from
`.github/copilot-instructions.md` are mirrored for Claude in
`../CLAUDE.md` at the repo root.

---

## How to start using it

1. **Install Claude Code** if you haven't yet — see the
   [Claude Code docs](https://docs.claude.com/claude-code).
2. **Pick an install path.** The pack ships two paths and you only ever
   need one of them:
   - **Path A — try it on the pack repo itself.** From the cloned pack
     root, run `./install.sh` (macOS/Linux) or `pwsh ./install.ps1`
     (Windows). Then open the **pack folder** itself in Claude Code.
     Your team's codebase is never touched.
   - **Path B — install it into your codebase.** Open your target repo
     in Claude Code and run `/assert-iq-bootstrap`. Choose `trial` to
     keep the pack invisible to your team via `.git/info/exclude`, or
     `committed` to check it in. Either way, bootstrap copies skills,
     agents, instructions, hooks, and config into the workspace.
   Both installers are safe to re-run.
3. **Start chatting.** Type `/` to see available skills, or `@assert-iq`
   to use the default Assert.IQ subagent. For plan-first behavior on a
   larger task, use `@assert-iq-plan` instead.

---

## "Will this also work in GitHub Copilot?"

Yes. The same content is mirrored to the `.github/` folder at the repo
root, and Copilot reads it automatically — no installer needed for the
Copilot side. See [`../.github/vscode-readme.md`](../.github/vscode-readme.md).

You can use either tool — they share the same skills, instructions, and
hooks.

---

## Uninstalling the pack

Match the uninstall to the install path you used.

**Path A — pack-as-workspace** (`bash install.sh` / `pwsh ./install.ps1`
at the root of the cloned pack):

```bash
bash install.sh --uninstall          # macOS / Linux / WSL
pwsh ./install.ps1 -Uninstall        # Windows
```

That removes `.claude/skills`, the rendered `hooks/hooks.json`, and the
`hooks` key from `.claude/settings.json` (preserving any other keys you
had). The committed pack files (`CLAUDE.md`, `.github/`, `AGENTS.md`,
the `hooks/` scripts and template) remain — delete or `git rm` them
when you're done with the clone.

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
`.claude/agents/`, and the `.claude/skills` symlink), and strips the
trial-mode block from `.git/info/exclude`. Files you edited
post-install are preserved at `<file>.assert-iq.uninstall-saved` so
nothing is silently lost.

To disable just the hooks without uninstalling: open
`.claude/settings.json` and delete the `hooks` block (or set the
relevant matchers to `[]`).

---

## What the bootstrap does **not** auto-wire — and how to fix it

The bootstrap delivers **every file in the pack to disk** at the right
location, but Claude Code only auto-loads some of them from a specific
set of paths. Several surfaces have to live in the **workspace** (or a
user-global slot) to be picked up:

- `CLAUDE.md` — the always-on QI guidance (and the `@`-imports it
  pulls in from `.github/instructions/qi-*.instructions.md`)
- `AGENTS.md` — the generic agent-spec pointer
- `.assert-iq/` — per-client config (maturity tier, governance
  posture, signal schema). The `assert-iq` subagent reads
  `.assert-iq/maturity-profile.md` and `.assert-iq/governance.md` on
  every quality/release question and silently falls back to defaults
  if they're missing.
- `.claude/settings.json` — Claude reads its `hooks` block here.
  Bootstrap merges only the `hooks` key, preserving anything else you
  already have in the file.
- `hooks/` (`scripts/`, `lib/`, `config/`, `hooks.json`) — the hook
  scripts themselves. `hooks.json` is rendered at bootstrap time so
  the script paths resolve to the workspace copies.

**Run `/assert-iq-bootstrap` once per new workspace.** The skill walks
you through where each surface should live (workspace / user-global /
skip), supports `solo` and `pod` presets, and copies the templates
from the cloned pack into the right places. Cross-platform
(macOS, Linux, Windows). Pre-existing files are preserved (SHA256
compare + interactive resolver); JSON settings files are deep-merged
additively and snapshotted to `<file>.assert-iq.pre-install` for clean
uninstall. Safe to re-run.

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
