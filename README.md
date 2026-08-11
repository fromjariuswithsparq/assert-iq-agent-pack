# Assert.IQ Agent Pack

> Quality Intelligence for every IDE, every sprint, every team.

**v2.0.0** · [Full documentation →](README.assert-iq.md)

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

- **29 skills** covering the full QE lifecycle — test generation, code review, risk assessment, hotspot mapping, traceability matrices, release confidence, escaped-defect analysis, exploratory charters, oracle-based grading, and more.
- **Two agents** (`Assert-IQ` for full execution, `Assert-IQ-PLAN` for plan-first workflows) with a built-in handoff button between them.
- **Maturity-aware behavior** — a one-file config scales the pack from "early / manual generation only" to "higher / autonomous healing," meeting teams where they are.
- **MCP wiring** to GitHub, ADO, Jira, Sentry, Grafana, Playwright, Slack, and 13 more tool surfaces — configured in one file, credentials kept in your OS keychain.
- **Dreaming** — a markdown memory store that consolidates learnings across sessions (via the `/dream` skill) so the agent gets sharper on your codebase over time, without the token cost of per-tool-call hooks.

QI is the operating model. Assert.IQ is how teams act on it — from day one, in the tools they already use.

---

## Decision Confidence Calibration — Proving Your QI Verdicts (v1.7.0+)

Assert.IQ v1.7.0 introduces **Decision Confidence Calibration**: a longitudinal accuracy measurement system that proves how good your PR and release verdicts are against real production escapes.

**What's recorded:**
- Every PR risk assessment and release confidence judgment → immutable verdict record (band, score, layer states, assumptions, memory hash)
- When an escape is discovered → linked back to original verdict
- Over time → Brier score, confusion matrix, per-layer fidelity, drift alerts

**Why it matters:**
- **For vendors:** After 60 days, you have escape correlation data competitors can't replicate. Show regulated clients: "Our verdicts had 94% precision on green-band PRs in your environment."
- **For regulated clients:** Verdicts are auditable end-to-end. SOX audits can ask "Why did we ship PR #4521?" and get: memory snapshot → reproducible assessment → linked escape (if any).
- **For teams:** Brier score trending reveals memory drift. Regression tests prevent dreams from degrading accuracy.

**Quick example:**
```bash
python3 .assert-iq/analysis/calibration.py --window-days 90 --output report.json
# Outputs: Brier Score, Confusion Matrix, Per-Layer Fidelity, Drift Alerts
```

Enable in `.assert-iq/config.yaml` — all facilities ship in the pack. For regulated clients, set `verdicts.track_in_git: true` to commit audit trail to git.

---

## Oracle Layer — Defensible Quality Verification (v1.6.0+)

The single largest gap in AI-driven testing is this: **generation without specification.**

Assert.IQ ships with the **Oracle Layer** — a rubric-based grading system that inverts the problem. Instead of generating artifacts (tests, reports, plans) and hoping they're good, you define what "good" looks like *first*, then grade independently.

**How it works:**

1. **Author rubrics** (`/define-quality-rubric`) — Guided interview → define dimensions (e.g., "assertion clarity", "test independence") → versioned JSON spec
2. **Grade artifacts** (`/grade-with-rubric`) — Isolated grader agent evaluates test/report/plan against rubric → PASS / CONDITIONAL / FAIL verdict + evidence
3. **Integrate with decisions** — Oracle verdicts feed into the **Outcome layer** of your merge/release gates (maturity-gated: early 0%, mid 20%, higher 50%)

**Why this matters:**

- **Rubric authorship** (defining quality) is the defensible differentiator, not test generation
- **Independent grading** — grader has zero access to how the artifact was produced, ensuring objectivity
- **Immutable specs** — rubrics are versioned (v1.0, v1.1) and tracked in git; full lineage preserved
- **Evidence-driven** — every verdict cites specific evidence; never subjective

**Quick example:**

```
You: "/define-quality-rubric"
  → Author rubric: Unit Test Acceptance Contract (v1.0)
    - Dimensions: assertion clarity, independence, determinism, focus
    - Weights: 1.0, 0.8, 0.9, 0.7
    - Saved to: .assert-iq/oracles/rubrics/test-unit-v1.0.json

You: "/grade-with-rubric tests/unit/login.test.ts test-unit-v1.0"
  → Grader evaluates independently
  → Verdict: CONDITIONAL (0.92 / 1.0)
    - ✓ PASS: independence, determinism, focus
    - ⚠ CONDITIONAL: assertion clarity (line 25 bare assert)
  → Fix line 25 → Re-grade → PASS

You: "/check-merge"
  → Outcome layer includes oracle verdict
  → No FAIL verdicts on touched tests → green Outcome
  → Verdict: MERGE
```

Get started with `ORACLE_QUICK_START.md` or the full guide at `oracles-readme.html`.

---

## Multi-Agent Orchestration & Commercial Instrumentation (v2.0+)

Assert.IQ v2.0 introduces a **multi-agent orchestration architecture** that isolates specialist analysis in parallel, then synthesizes findings into executive-ready business metrics.

### Eight Specialist Agents

When you invoke a quality or release decision skill, the lead agent now delegates to 8 isolated specialists running **in parallel**, then **serially**:

**Parallel Batch (concurrent execution):**
1. **risk-scorer** — PR risk assessment (change + protection layers)
2. **coverage-analyst** — Test protection gap analysis
3. **flake-adjudicator** — Test failure root-cause classification
4. **hotspot-analyzer** — Fragile module identification (churn + complexity + escapes)

**Serial Specialists (after parallel completes):**
5. **oracle-grader** — Rubric-based quality scoring
6. **calibration-specialist** — Verdict accuracy measurement (Brier score, layer fidelity, drift)
7. **memory-curator** — Memory store health checks (cycles, staleness, contradictions)
8. **traceability-auditor** — AC↔code↔test linkage validation

Each specialist returns **structured JSON** with findings, recommendations, and evidence. The lead agent aggregates all outputs into a synthesized narrative + decision, preserving the audit trail in `.assert-iq/agent-runs/`.

### Business Impact Dashboards

The new **`/measure-qi-impact`** skill converts QI verdicts + baseline metrics into **VP-ready HTML dashboards** showing quarterly economic ROI:

- **Escape Reduction** — Production incident count delta vs. baseline (% improvement + cost impact)
- **Triage Hours Reclaimed** — Post-incident investigation time saved (hours + engineer cost)
- **Release Cycle Acceleration** — Days saved PR→release (velocity improvement)
- **Total Economic Value** — Combined ROI in dollars (sum of prevented incidents + triage savings)

**Output format:**
- **HTML Dashboard** — Professional, responsive, print-friendly (hero section + 4 metric cards + recommendation)
- **JSON Report** — Structured data for trending and reporting
- **Baseline Template** — Pre-QI metrics capture (escape rate, triage hours, cycle time)

**Example Impact (Q3 2026):**
```
33% escape reduction (4 fewer incidents) → $200K cost avoidance
55 engineer-hours reclaimed → $4,675 burden cost savings
4 days cycle acceleration → velocity metrics improvement
Total quarterly ROI: $204,675
```

Enable in `.assert-iq/config.yaml` — set `business_metrics.enabled: true` and provide baseline metrics in `.assert-iq/business-metrics/baseline.json`. Regenerate quarterly or on-demand with `/measure-qi-impact`.

### Why This Matters

- **Context Isolation** — Specialists don't see each other's prompts; each reasons independently.
- **Parallel Speed** — 4 agents run simultaneously; orchestration reduces analysis latency.
- **VP Conversations** — Business metrics are the missing lever for renewal and investment conversations. "Token savings" doesn't sell; **"$200K in prevented incidents + $4.7K in triage reclamation" does.**
- **Predictive Accuracy** — Calibration layer measures verdict fidelity over time, feeding back into confidence scoring.

---

## Get started in three steps

### 1 · Install the pack

There are exactly two install paths. Pick the one that matches how comfortable you are dropping the pack into your team's codebase.

**Path A — Try it on the pack repo itself.** Best if you want to play with Assert.IQ before touching your team's repository. Clone the pack, run the installer, and open the **pack folder** as your VS Code / Claude Code workspace. Everything runs against the pack's own files — your team's codebase is never modified.

```bash
git clone https://github.com/fromjariuswithsparq/assert-iq-agent-pack
cd assert-iq-agent-pack
bash install.sh           # macOS / Linux / WSL
# or
pwsh ./install.ps1        # Windows PowerShell 7+
```

The installer renders the session-events wiring for the pack's own root, scaffolds the `.assert-iq/memory/` store, wires `.claude/settings.json`, and creates the `.claude/skills` symlink — all inside the pack folder. Re-runnable. Reverse it with `bash install.sh --uninstall` (or `pwsh ./install.ps1 -Uninstall`).

**Path B — Install it into your codebase.** This is the real deployment path. **Run the bootstrap script from a terminal in your target repo** — no editor required:

```bash
# 1. Clone the pack somewhere on your machine (one time, anywhere)
git clone https://github.com/fromjariuswithsparq/assert-iq-agent-pack ~/assert-iq-agent-pack

# 2. cd into YOUR repo (the one you want Copilot/Claude to load the pack in)
cd ~/code/my-app

# 3. Run the bootstrap script from the clone
bash ~/assert-iq-agent-pack/scripts/bootstrap.sh --mode=trial
# Windows (PowerShell 5.1 or PowerShell Core):
powershell -File ~\assert-iq-agent-pack\scripts\bootstrap.ps1 -Mode trial
# or if you have PowerShell Core 7+ installed:
pwsh -File ~\assert-iq-agent-pack\scripts\bootstrap.ps1 -Mode trial
```

The script is fully standalone — it accepts `--preset=solo|pod`, prompts interactively when run in a TTY, and writes everything Copilot and Claude need into your workspace. **There is no chicken-and-egg.** You do not need to open VS Code or Claude Code first, and you do not need the `/assert-iq-bootstrap` skill loaded — the script is what the skill calls under the hood.
> **Where does `--preset=solo` put the QI instructions?** Solo is
> designed for a single developer who wants the QI rules to apply to
> *every* repo they open, not just this one. The instruction files
> (`qi-foundation`, `qi-test-design`, etc.) and `CLAUDE.md` install to
> your VS Code user prompts folder
> (`~/Library/Application Support/Code/User/prompts/` on macOS,
> `~/.config/Code/User/prompts/` on Linux,
> `%APPDATA%\Code\User\prompts\` on Windows) and `~/.claude/CLAUDE.md`
> respectively — **not** to `.github/instructions/` in the workspace.
> Use `--preset=pod` if you want the instructions checked into this
> repo for the whole team.


> **Already have the pack loaded** (e.g. you opened the cloned pack itself in your editor, or you've installed the skills user-globally to `~/.agents/skills/`)? You can also run `/assert-iq-bootstrap` from chat — same outcome, chat-driven prompts.

`--mode=trial` is the safe default for the first install: every pack file lands in your workspace, but the path is added to `.git/info/exclude`. Your team sees nothing — your codebase's `.gitignore` is **never** touched. Once you're ready for the team to see it, run `bash scripts/bootstrap.sh --graduate` (or use `--mode=committed` from the start).

Bootstrap writes twelve surfaces into the workspace: `.assert-iq/`, `.github/instructions/`, `.github/copilot-instructions.md`, `.github/skills/`, `.github/agents/`, `.claude/agents/`, `.claude/skills` (symlink to `../.github/skills` on macOS/Linux; copy fallback on Windows without Developer Mode), `.claude/settings.json`, `CLAUDE.md`, `AGENTS.md`, `.vscode/settings.json` + `.vscode/mcp.json`, and the `.assert-iq/dreaming/` machinery + `.assert-iq/memory/` store. Pre-existing user files are snapshotted to `<file>.assert-iq.pre-install` before any modification, so a later `bash scripts/bootstrap.sh --uninstall` can restore them byte-for-byte. Safe to re-run.

> **Already have a `copilot-instructions.md`, `CLAUDE.md`, or `AGENTS.md` in your repo?** The interactive resolver offers `[m]erge (recommended)` for those three files. Merge wraps the pack content in idempotent HTML-comment markers (`<!-- assert-iq:begin v=... -->` … `<!-- assert-iq:end -->`) at the top of the file and leaves your existing content below the markers untouched. Re-installing replaces only the marker block, so the merge stays clean across upgrades and your team-authored content is never rewritten. Other files keep the existing `[k]eep / [o]verwrite / [s]idecar` choices.

> **Don't want trial mode? Want skills available in every workspace?**
> Use `--preset=portable` instead. Skills install user-globally to
> `~/.agents/skills/` (VS Code Copilot Chat) and `~/.claude/skills/`
> (Claude Code), so every repo you open has the 26 QI skills available.
> Workspace footprint is minimal: just the Assert-IQ chat agent files
> (`.github/agents/`, `.claude/agents/`) and the manifest — no
> instructions, dreaming, settings, or MCP config touch your repo.
> ```bash
> bash ~/assert-iq-agent-pack/scripts/bootstrap.sh --preset=portable
> ```
> Reverse with `bash ~/assert-iq-agent-pack/scripts/bootstrap.sh --uninstall --user`.

| | Path A — pack-as-workspace | Path B — install into codebase |
|---|---|---|
| **Command** | `bash install.sh` | `bash <pack>/scripts/bootstrap.sh --mode=trial` (or `/assert-iq-bootstrap` if the pack is already loaded) |
| **Workspace** | The pack folder itself | Your team's repo |
| **Touches your codebase?** | No — the pack is the workspace | Yes — files go into your repo (hidden from git in trial mode) |
| **Hides from team git?** | N/A | Yes via `.git/info/exclude` (trial mode) |
| **Reverse with** | `bash install.sh --uninstall` | `bash scripts/bootstrap.sh --uninstall` |
| **Best for** | Evaluating the pack, demos, the curious | Real adoption — solo, then team |

#### Compare the Presets

To avoid confusion regarding what files land globally versus locally, here is a breakdown of the three installation presets:

| Preset | Instructions & Rules | Skills / Commands | Workspace Footprint | Best used for... |
|---|---|---|---|---|
| `--preset=pod` (default) | **Workspace** (`.github/instructions/`) | **Workspace** (`.github/skills/`) | Full (12 configuration surfaces) | The entire team adopting Assert.IQ simultaneously in a shared repository. |
| `--preset=solo` | **User-global** (`~/Library/..`) | **Workspace** (`.github/skills/`) | High (Skills & config, no instructions) | A single developer who wants the core QI reasoning rules active *everywhere*, but skills isolated strictly to this project. |
| `--preset=portable` | *(Not installed)* | **User-global** (`~/.agents/skills/`) | Minimal (Chat agents & manifest only) | A developer who wants the 26 QI skills available in *any* repository without writing configs into the codebase. |

> **Presets vs. Modes: What's the difference?**
> - **Presets (`--preset`) control _Placement_:** Where do the files physically go on your hard drive? (Global OS directories vs. local workspace folders).
> - **Modes (`--mode`) control _Git Visibility_:** For the files that *do* land in your workspace, how does git treat them?
> 
> You mix and match them. For example, `--preset=pod --mode=trial` means *"Put everything in my workspace (`pod`), but hide them in `.git/info/exclude` so I can evaluate them locally without bothering my team (`trial`)."* 
> Once you're ready to share with the team, you use `--mode=committed` (or run `--graduate`), meaning *"Keep the files in the workspace, but now let git track them so my team sees them."*


---

### 2 · Customize and wire everything in

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

   When the companion is set, cross-repo skills (`risk-assess-pr`, `check-merge`, `release-confidence`, `code-review`, `check-test-coverage`, `generate-traceability-matrix`, `analyze-escaped-defect`) fetch the other half via your VCS MCP, a local checkout, or manual paste. When it isn't set, the affected layer is reported as **UNGRADED** with reason `companion_repo_unset` — never fabricated. Full contract in [.assert-iq/workspace-topology.md](.assert-iq/workspace-topology.md). For tight test↔prod feedback loops in a split-repo team, also consider opening both folders as a multi-root VS Code workspace.

---

### 3 · Run a skill

In Copilot Chat, select the `Assert-IQ` agent and try:

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
  skills/                     ← 26 QI skills, one subfolder each
  agents/                     ← Assert-IQ and Assert-IQ-PLAN agent definitions
.claude/
  agents/                     ← Claude Code subagent counterparts
  skills → ../.github/skills  ← symlink (copy on Windows without Dev Mode)
.vscode/
  mcp.json                    ← 20 MCP server definitions
  MCP.md                      ← per-server credential and setup guide
.assert-iq/                   ← per-repo config (created by bootstrap)
  memory/                     ← Dreaming memory store (MEMORY.md, topics/, logs/)
  dreaming/                   ← waking-loop recorder, dream gate, optional cron dreamer
scripts/
  bootstrap.sh / .ps1         ← workspace installer, cross-platform
```

---

## Upgrade

Upgrades are explicit and intentional:

1. Read the [Releases page](https://github.com/fromjariuswithsparq/assert-iq-agent-pack/releases) for what changed and any migration notes.
2. Uninstall the current version where you installed it:
   - **Path A** (pack-as-workspace): `bash install.sh --uninstall` (or `pwsh ./install.ps1 -Uninstall`).
   - **Path B** (codebase install): `bash scripts/bootstrap.sh --uninstall` (or `pwsh scripts/bootstrap.ps1 -Uninstall`) in each target repo.
3. `git pull` (or re-clone) to the new tag, then re-run the same path to refresh.

---

## Go deeper

The three steps above are the fast path. When you're ready for the full picture:

**[README.assert-iq.md →](README.assert-iq.md)** — detailed install options (drop-in / air-gapped / trial vs. committed), full skill reference, maturity tier matrix, MCP server inventory, Dreaming architecture, and full release history.

Tool-specific references:
- VS Code / Copilot — [`.github/vscode-readme.md`](.github/vscode-readme.md)
- Claude Code — [`.claude/claude-readme.md`](.claude/claude-readme.md)
- MCP servers — [`.vscode/MCP.md`](.vscode/MCP.md)
