# The `.kiro/` folder — for Kiro

This folder is the **Kiro half** of the Assert.IQ Agent Pack. If you open
this repository in [Kiro](https://kiro.dev), this is where Kiro looks for
its steering, agents, skills, hooks, and MCP servers.

Kiro reads none of `.github/*`, none of `.claude/*`, and no `CLAUDE.md`.
Everything it needs lives here — plus `AGENTS.md` at the repo root, which
Kiro discovers natively as always-on steering.

**Trust the workspace.** Kiro disables hook execution in an untrusted
folder, and it does so *silently* — no error, no log line. If Dreaming looks
dead, that is the first thing to check. See
[Three things Kiro does differently](#three-things-kiro-does-differently--each-fails-silently).

---

## What's in here, in plain words

| Item | What it is |
|---|---|
| `steering/00-assert-iq.md` | The always-on house rules — the Kiro counterpart to `.github/copilot-instructions.md` and `CLAUDE.md`. Hand-authored, because Kiro has no `CLAUDE.md` equivalent to mirror. |
| `steering/qi-*.md` | Six scoped rule sheets that switch on by file type — tests, traceability, CI config, oracle rubrics, and so on. **Generated** from `.github/instructions/` by `scripts/sync-kiro.sh` (`.ps1` on Windows), which maps each file's `applyTo` glob onto Kiro's `inclusion` / `fileMatchPattern` frontmatter. Don't hand-edit them; the next sync reverts it. |
| `agents/assert-iq.md` | The **default Assert.IQ agent** — the Quality Intelligence front door, full tools. Routes your question to the right skill and executes. Hand-authored: the prose is harness-specific. |
| `agents/assert-iq-plan.md` | The **planning sibling**. Read-only — researches, writes a plan, waits for your approval before anything moves. Reach for it when the task is large or risky. |
| `agents/<specialist>.md` | Eight single-purpose analysts (risk-scorer, coverage-analyst, flake-adjudicator, hotspot-analyzer, oracle-grader, calibration-specialist, memory-curator, traceability-auditor). **Generated** from `.claude/agents/specialists/` by `scripts/sync-kiro.sh`, which translates Claude tool *names* into Kiro tool *tags*. Don't hand-edit. |
| `skills` | A **symlink** to `.github/skills/`, so Copilot, Claude and Kiro share one canonical copy of all 32 skills. On **Windows without Developer Mode** the installer copies the folder instead — in that case re-run the installer after editing any skill. |
| `hooks/assert-iq-dreaming.json` | **Dreaming** for Kiro — rendered by the installer so the script paths point at this workspace. Three hooks: a `SessionStart` gate that nudges you to run `/dream`, a `Stop` recorder, and a `Stop` **agent** hook that captures the turn's facts. |
| `settings/mcp.json` | 20 pre-configured MCP servers in **Kiro's own schema**. Not interchangeable with `.vscode/mcp.json` — different shape, different field names. Everything ships `"disabled": true`; enable only what you use. |
| `settings/MCP.md` | Per-server setup, credentials, and exactly how Kiro's MCP config differs from the VS Code one. |

Per-client configuration — maturity tier, governance posture, signal schema —
lives in `../.assert-iq/`, shared by all three harnesses.

**The contract this folder is built against is
[`../.assert-iq/kiro-harness.md`](../.assert-iq/kiro-harness.md).** It was
verified against the shipped Kiro binary rather than the public docs, which
are wrong in three places that would each have produced a broken file. Read
it before changing anything here; it also records what remains unverified.

---

## How to start using it

1. **Install Kiro** if you haven't yet — see [kiro.dev](https://kiro.dev).
2. **Check your environment.** `bash scripts/check-environment.sh`
   (macOS/Linux/WSL) or `pwsh -File scripts/check-environment.ps1`
   (Windows). It names every requirement and the fix for anything missing.
   Full table: [README → Environment requirements](../README.md#environment-requirements).
3. **Pick an install path.** The pack ships two and you only ever need one:
   - **Path A — try it on the pack repo itself.** From the cloned pack root,
     run `bash install.sh` (macOS/Linux/WSL) or `pwsh -File install.ps1`
     (Windows — **not** Git Bash). Then open the **pack folder** itself in
     Kiro. Your team's codebase is never touched.
   - **Path B — install it into your codebase.** The real deployment path.
     Run the bootstrap from a terminal pointed at your target repo:
     ```bash
     # 1. Clone the pack somewhere (one time, anywhere)
     git clone https://github.com/fromjariuswithsparq/assert-iq-agent-pack ~/assert-iq-agent-pack
     # 2. cd into YOUR repo
     cd ~/code/my-app
     # 3. Run the bootstrap script from the clone
     bash ~/assert-iq-agent-pack/scripts/bootstrap.sh --mode=trial
     # Windows (PowerShell, NOT Git Bash):
     # pwsh -File $HOME/assert-iq-agent-pack/scripts/bootstrap.ps1 -Mode trial
     ```
     `--mode=trial` keeps the pack invisible to your team via
     `.git/info/exclude`; `--mode=committed` checks it in. Pass
     `--kiro=skip` (`-Kiro skip`) if you want everything *except* this
     folder.
   Both installers are safe to re-run.
4. **Reload the window**, then **trust the workspace** when Kiro prompts.
   `Cmd/Ctrl + Shift + P` → **Developer: Reload Window**. If you dismissed
   the trust prompt, reopen it with **Workspaces: Manage Workspace Trust**.
5. **Start chatting.** Type `/` and a skill name, or just describe what you
   want and let the agent route it. Pick `Assert-IQ` for execution,
   `Assert-IQ-PLAN` when you want to see the plan first.

> **If your workspace already had its own `.kiro/skills`**, the installer
> **merges** into it rather than claiming it: it reclaims a directory that
> is empty or byte-identical to the canonical tree, copies alongside
> anything else, and never deletes what it did not place. Uninstall removes
> only the pack's own files. Merged skills are copies, so re-run the
> installer after a pack upgrade.

---

## Three things Kiro does differently — each fails silently

These are the ones worth knowing up front, because none of them produces an
error message.

- **Hooks do not run in an untrusted workspace.** Dreaming will look dead —
  the counter never advances, the gate never fires — and nothing appears in
  any log you'd think to check. Trust the folder.
- **Agents do not inherit steering or skills.** A Kiro agent loads only what
  its own `resources` globs name, and an invalid entry is dropped without
  error. Every agent the pack ships declares both globs, and a test enforces
  it — but if you write your own agent and it seems to know nothing about
  QI, this is why.
- **File-triggered hooks fire only on agent-made edits**, never on a manual
  save. If you're testing a hook by editing a file yourself, it will never
  run.

One more, for anyone extending Dreaming: **Kiro writes no transcript.** Its
`Stop` payload carries no `transcript_path` — the string appears zero times
in the entire shipped bundle — so the recorder has nothing to mine. That is
why the pack ships a third, `agent`-type `Stop` hook on Kiro: the agent has
the finished turn in context, so on Kiro **the agent is the capture layer**.
Claude Code and Copilot are untouched; their `transcript_path` still works.

---

## "Will this also work in Copilot or Claude Code?"

Yes — both. The same content is mirrored to `.github/` for GitHub Copilot
and to `.claude/` for Claude Code, at the repo root. See
[`../.github/vscode-readme.md`](../.github/vscode-readme.md) and
[`../.claude/claude-readme.md`](../.claude/claude-readme.md).

You can use any of the three — they share the same skills, instructions, and
Dreaming memory. Because the Kiro steering and specialists are *generated*
from the same sources the other two read, the three cannot drift apart.
After editing `.github/instructions/*` or `.claude/agents/specialists/*`,
re-run **both** `scripts/sync-agents.sh` and `scripts/sync-kiro.sh` from the
pack checkout. Parity checks P7 and P8 fail while the Kiro side is stale,
exactly as P5 and P6 do for Copilot.

---

## Uninstalling the pack

Match the uninstall to the install path you used.

**Path A — pack-as-workspace** (`bash install.sh` / `pwsh ./install.ps1` at
the root of the cloned pack):

```bash
bash install.sh --uninstall          # macOS / Linux / WSL
pwsh ./install.ps1 -Uninstall        # Windows
```

That removes the skills symlinks and the rendered session-event wiring. Your
`.assert-iq/memory/` store is preserved. The committed pack files remain —
delete or `git rm` them when you're done with the clone.

**Path B — codebase install** (`/assert-iq-bootstrap` or
`bash scripts/bootstrap.sh --mode=trial` inside your target repo):

```bash
bash scripts/bootstrap.sh --uninstall            # macOS / Linux
bash scripts/bootstrap.sh --uninstall --dry-run  # preview without changes
pwsh -File scripts/bootstrap.ps1 -Uninstall      # Windows
```

The uninstall reads `.assert-iq/.install-manifest.json`, restores any
pre-existing files from their `<file>.assert-iq.pre-install` snapshots,
removes pack-owned files — including the generated steering and agents, the
rendered hooks, and the `.kiro/skills` link — and strips the trial-mode
block from `.git/info/exclude`. Skills you had before the install are left
alone. Files you edited post-install are preserved at
`<file>.assert-iq.uninstall-saved` so nothing is silently lost.

To disable just Dreaming without uninstalling: set `dreaming.enabled: false`
in `.assert-iq/config.yaml` (or export `AIQ_DREAMING_DISABLED=1`), or delete
`hooks/assert-iq-dreaming.json`.

---

## What the bootstrap does **not** auto-wire — and how to fix it

The bootstrap delivers **every file in the pack to disk** at the right
location, but Kiro only auto-loads some of them from a specific set of
paths. These have to live in the **workspace** to be picked up:

- `.kiro/steering/` — the always-on entrypoint plus the six scoped rule
  sheets. Kiro reads steering only from the workspace.
- `.kiro/agents/` — the lead, the planner, and the eight specialists.
- `.kiro/skills` — the link to `.github/skills/`. Without it, `/` shows
  nothing.
- `.kiro/hooks/` — Dreaming. Rendered at bootstrap time so the script paths
  resolve to the workspace copies, which is why this one cannot simply be
  copied from the pack.
- `.kiro/settings/mcp.json` — workspace MCP config. Merges over your
  user-global `~/.kiro/settings/mcp.json`, so personal credentials can stay
  in your home directory while the workspace file stays committed and
  secret-free.
- `AGENTS.md` — the generic agent pointer, which Kiro reads as always-on
  steering.
- `.assert-iq/` — per-client config. The agents read
  `.assert-iq/maturity-profile.md` and `.assert-iq/governance.md` on every
  quality or release question, and fall back to defaults if they're missing.

**Run the bootstrap script once per new workspace.** From a terminal inside
your target repo:

```bash
bash /path/to/assert-iq-agent-pack/scripts/bootstrap.sh --mode=trial
# Windows: pwsh -File <pack>\scripts\bootstrap.ps1 -Mode trial
```

The script walks you through where each surface should live, supports the
`solo`, `pod`, and `portable` presets, and copies the templates from the
cloned pack into the right places. Pre-existing files are preserved (SHA256
compare plus an interactive resolver) and snapshotted to
`<file>.assert-iq.pre-install` for a clean uninstall. Safe to re-run.

> **No user-global Kiro scope.** `--kiro` takes `workspace` or `skip`, not
> `user`. Kiro does resolve `~/.kiro/steering` and `~/.kiro/agents`, but
> global-versus-workspace precedence *per file name* is unverified against a
> real Kiro, and shipping an unverified scope is exactly the quiet
> half-support this pack avoids. See `kiro-harness.md` §8.

---

## Something feels off?

- **Dreaming not firing?** Trust the workspace first — that is the usual
  cause, and it fails without a message. Then check that
  `hooks/assert-iq-dreaming.json` exists and that `dreaming.enabled` is not
  `false` in `.assert-iq/config.yaml`.
- **Skills not showing up?** `skills` here should be a link (or a populated
  folder on Windows without Developer Mode), not empty. Re-run the
  installer.
- **An agent seems to know nothing about QI?** Check its `resources` globs —
  Kiro agents inherit nothing, and invalid entries are dropped silently.
- **A generated file keeps reverting?** That's working as intended. Edit the
  source under `.github/instructions/` or `.claude/agents/specialists/` and
  re-run `scripts/sync-kiro.sh`.
- Need the full file map? See [`../MANIFEST.md`](../MANIFEST.md).
- Need the day-one onboarding doc? See
  [`../README.assert-iq.md`](../README.assert-iq.md).
