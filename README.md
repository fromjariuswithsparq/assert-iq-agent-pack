# Assert.IQ Agent Pack

> Quality Intelligence for every IDE, every sprint, every team.

**v0.9.0** · [Full documentation →](README.assert-iq.md)

---

## Quality Intelligence — the shift from QA to QI

Traditional QA asks one question: *did this pass?*

**Quality Intelligence** asks four:

| Layer | Question |
|---|---|
| **Change risk** | What moved, and how broadly does it reach? |
| **Protection strength** | Do the right tests actually cover it? |
| **Signal trustworthiness** | Can we believe the results we're seeing? |
| **Outcome evidence** | What do escaped defects and telemetry say? |

These four layers combine into **Decision Confidence** — a synthesized, traceable answer to *"is this safe to ship?"* that no single coverage percentage or green CI badge can give you.

The immediate impact:

- Engineers stop asking "do we have tests?" and start asking "do our tests protect the *right* things?"
- Release conversations shift from gut-feel to evidence.
- Escaped defects get root-caused at the signal layer they slipped through, not just triaged.
- QA stops being a gate at the end of a sprint and becomes a continuous signal woven into every PR, every merge, every retrospective.

---

## Assert.IQ — QI inside your IDE

Assert.IQ is the accelerator. It drops a QI reasoning layer directly into **GitHub Copilot Chat** and **Claude Code** so teams don't have to learn a new tool or change their workflow. The IDE they already use becomes QI-aware.

- **23 skills** covering the full QE lifecycle — test generation, code review, risk assessment, hotspot mapping, traceability matrices, release confidence, escaped-defect analysis, exploratory charters, and more.
- **Two agents** (`Assert-IQ` for full execution, `Assert-IQ-PLAN` for plan-first workflows) with a built-in handoff button between them.
- **Maturity-aware behavior** — a one-file config scales the pack from "early / manual generation only" to "higher / autonomous healing," meeting teams where they are.
- **MCP wiring** to GitHub, ADO, Jira, Sentry, Grafana, Playwright, Slack, and 13 more tool surfaces — configured in one file, credentials kept in your OS keychain.
- **Hindsight Hooks** that learn from corrections across sessions and progressively tighten agent behavior for your specific codebase.

QI is the operating model. Assert.IQ is how teams act on it — from day one, in the tools they already use.

---

## Get started in three steps

### 1 · Install the plugin

**VS Code Copilot Chat**

1. `Cmd+Shift+P` → **`Chat: Install Plugin From Source`**
2. Paste the shorthand — no URL, no `@ref`:
   ```
   fromjariuswithsparq/assert-iq-agent-pack
   ```
3. Pick **`assert-iq`** from the list → confirm → **`Developer: Reload Window`**.

**Claude Code**

```bash
/plugin install fromjariuswithsparq/assert-iq-agent-pack@v0.9.0
```

This installs the 23 skills and both agents globally. Nothing is written to your codebase yet — that's the next step.

---

### 2 · Bootstrap the plugin to your workspace

Open the **target repo** (not this one), open the chat, and run:

```
/assert-iq-bootstrap
```

The skill asks two questions, then handles everything else:

- **Trial or committed?** Trial hides pack files from git via `.git/info/exclude` — only you see them; your codebase `.gitignore` is never touched. Committed checks files in so the whole team benefits. Graduate from trial to committed any time with `scripts/bootstrap.sh --graduate`.
- **Solo or pod?** Presets that tune defaults for individual contributors vs. cross-functional teams.

Bootstrap copies instruction files, `.assert-iq/` config, `.vscode/settings.json`, `.vscode/mcp.json`, and hooks into the right places. It SHA256-compares before writing — pre-existing files are preserved, never silently overwritten. Safe to re-run.

---

### 3 · Customize and wire everything in

1. **Set your maturity tier** in `.assert-iq/maturity-profile.md` — Early, Mid, or Higher. The agents read this on every quality and release question and scale their behavior accordingly.

2. **Set your governance posture** in `.assert-iq/governance.md` — compliance constraints the agents must respect (data handling, naming conventions, refusal rules).

3. **Wire your tools** in `.vscode/mcp.json`. The pack ships 20 pre-configured MCP servers. Add credentials when VS Code prompts — they go to your OS keychain, not the file. See [`.vscode/MCP.md`](.vscode/MCP.md) for a per-server setup guide.

4. **Tailor `config.yaml` to your codebase.** Open `.assert-iq/config.yaml` — it controls your maturity tier, tracker, test framework, signal sink, and the free-text context the agent uses when generating artifacts. Every field has inline comments, so you can edit it manually. Or let the agent do it:

   - Add `.assert-iq/config.yaml` to the chat context (drag the file in, or use the **Attach** button in Copilot Chat).
   - Then say:
     ```
     Customize this config.yaml file to my codebase and workspace.
     ```
   The agent will ask a few targeted questions about your stack, tracker, and team, then fill in the placeholders for you. (Tip: You can also do this for other files like instructions and skills!)

5. **Pick your workspace topology.** Open `.assert-iq/config.yaml` and set `workspace.role`:

   | Topology | `workspace.role` | Setup |
   |---|---|---|
   | Tests and prod code in the same repo | `monorepo` (default) | Nothing else to configure — every skill behaves exactly as it did pre-v0.8 |
   | This repo holds prod code; tests live in a separate repo | `prod` | Set `workspace.companion_repo` to the tests repo (path or remote) |
   | This repo holds tests; prod code lives in a separate repo | `tests` | Set `workspace.companion_repo` to the prod repo (path or remote) |

   When the companion is set, cross-repo skills (`risk-assess-pr`, `check-merge`, `release-confidence`, `code-review`, `check-test-coverage`, `generate-traceability-matrix`, `analyze-escaped-defect`) fetch the other half via your VCS MCP, a local checkout, or manual paste. When it isn't set, the affected layer is reported as **UNGRADED** with reason `companion_repo_unset` — never fabricated. Full contract in [.github/instructions/qi-foundation.instructions.md](.github/instructions/qi-foundation.instructions.md). For tight test↔prod feedback loops in a split-repo team, also consider opening both folders as a multi-root VS Code workspace.

6. **Run a skill.** In Copilot Chat, select the `Assert-IQ` agent and try:
   ```
   /risk-assess-pr
   ```
   The agent pulls context from your connected tools and reasons through all four signal layers.

---

## What's inside

```
.github/
  copilot-instructions.md     ← always-on QI reasoning rules for Copilot
  instructions/               ← scoped rule sheets (tests, C#/XAML, CI, etc.)
  skills/                     ← 23 QI skills, one subfolder each
  agents/                     ← Assert-IQ and Assert-IQ-PLAN agent definitions
.claude/
  agents/                     ← Claude Code subagent counterparts
  skills → ../.github/skills  ← symlink (copy on Windows without Dev Mode)
.vscode/
  mcp.json                    ← 20 MCP server definitions
  MCP.md                      ← per-server credential and setup guide
hooks/
  hooks.json                  ← Hindsight Hooks wiring
  scripts/                    ← session-start, apply, reflect, session-end
.assert-iq/                   ← per-repo config (created by bootstrap)
scripts/
  bootstrap.sh / .ps1         ← workspace installer, cross-platform
```

---

## Upgrade

Upgrades are explicit and intentional:

1. Read the [Releases page](https://github.com/fromjariuswithsparq/assert-iq-agent-pack/releases) for what changed and any migration notes.
2. Uninstall the current version — VS Code: Extensions view → `@agentPlugins` → uninstall `assert-iq`. Claude Code: `claude mcp remove assert-iq`.
3. Reinstall using the same Step 1 commands with the new tag.
4. Re-run `/assert-iq-bootstrap` to refresh workspace surfaces.

---

## Go deeper

The three steps above are the fast path. When you're ready for the full picture:

**[README.assert-iq.md →](README.assert-iq.md)** — detailed install options (drop-in / air-gapped / trial vs. committed), full skill reference, maturity tier matrix, MCP server inventory, hooks architecture, and full release history.

Tool-specific references:
- VS Code / Copilot — [`.github/vscode-readme.md`](.github/vscode-readme.md)
- Claude Code — [`.claude/claude-readme.md`](.claude/claude-readme.md)
- MCP servers — [`.vscode/MCP.md`](.vscode/MCP.md)
