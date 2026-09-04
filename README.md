# Assert.IQ Agent Pack

> Quality Intelligence for every IDE, every sprint, every team.

**v2.1.2** · [Full documentation →](README.assert-iq.md)

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

Eight features do the work. Each one links to its full write-up in the **[Feature Guide](FEATURES.md)** — what it is, how to use it, when to reach for it, and why it earns its place, written to be readable whether or not you write code.

- **[31 skills](FEATURES.md#skills)** covering the full QE lifecycle — test generation, code review, risk assessment, hotspot mapping, traceability matrices, release confidence, escaped-defect analysis, exploratory charters, oracle-based grading, business metrics dashboards, and more. Every skill is broken down individually [in the guide](FEATURES.md#the-31-skills-one-by-one).
- **[Multi-agent orchestration](FEATURES.md#multi-agent-orchestration) (v2.0)** — available on **both** harnesses: two lead agents (`Assert-IQ` for full execution, `Assert-IQ-PLAN` for plan-first workflows) orchestrate **8 isolated specialist agents** (risk-scorer, coverage-analyst, flake-adjudicator, hotspot-analyzer, oracle-grader, calibration-specialist, memory-curator, traceability-auditor) that run in parallel then serially, each returning structured JSON the lead synthesizes into one decision.
- **[Business impact dashboards](FEATURES.md#business-impact-dashboards) (v2.0)** — the `/measure-qi-impact` skill converts QI verdicts into VP-ready HTML dashboards: escape reduction %, triage hours reclaimed, cycle-time acceleration, and total economic ROI in dollars.
- **[Oracle Layer](FEATURES.md#oracle-layer)** — rubric-based grading (`/define-quality-rubric`, `/grade-with-rubric`): define what "good" looks like first, then grade artifacts independently. Immutable, versioned specs feed the Outcome layer.
- **[Maturity-aware behavior](FEATURES.md#maturity-aware)** — a one-file config scales the pack from "early / manual generation only" to "higher / autonomous healing," meeting teams where they are.
- **[20 MCP servers](FEATURES.md#mcp-servers)** wiring GitHub, ADO, Jira, Sentry, Grafana, Playwright, Slack, and 13 more tool surfaces — configured in one file, credentials kept in your OS keychain.
- **[Dreaming](FEATURES.md#dreaming)** — a markdown memory store that consolidates learnings across sessions (via the `/dream` skill) so the agent gets sharper on your codebase over time, without the token cost of per-tool-call hooks.
- **[Decision Confidence Calibration](FEATURES.md#decision-confidence-calibration)** — every verdict is recorded with a memory hash for reproducibility. Brier score, confusion matrix, and per-layer fidelity prove verdict accuracy against real production escapes over time.

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
# Windows: python.org ships python.exe but no python3.exe — use `python` or `py -3`
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

## Environment requirements

Here's what the pack needs on your machine. You don't have to check these by hand — **[step 3 of the install](#get-started) runs an environment check for you** and prints the exact fix for anything missing, so a bad environment surfaces before install rather than as a confusing failure midway through.

| | macOS / Linux / WSL | Windows |
|---|---|---|
| **Installer to run** | `bash scripts/bootstrap.sh` | `scripts\bootstrap.ps1` |
| **Host** | bash 3.2+ (macOS's `/bin/bash` qualifies) | **PowerShell 7+ (`pwsh`) recommended.** Windows PowerShell 5.1 is supported and tested — see below |
| **git** | Required | Required |
| **Python 3** | Required for calibration, memory sanity, verdict recording | Same — the pack resolves `python3` → `python` → `py -3` itself |
| **jq** | Not needed for the install below. Only required by advanced flows in the [full docs](README.assert-iq.md#installation) | Not used — the PowerShell path parses JSON natively |
| **Symlinks** | Native | Developer Mode for a live `.claude/skills`; otherwise it is copied |

**Why PowerShell 7 is the recommendation.** Both hosts pass the full suite, so 5.1 is a real fallback, not a warning label — install nothing if you'd rather not. PowerShell 7 is simply the better default: it creates a live `.claude/skills` symlink where 5.1 usually falls back to a copy, and it avoids a family of .NET Framework quirks (native stderr promoted to terminating errors, `-Encoding UTF8` writing a byte-order mark) that the pack now works around explicitly rather than relies on.

```powershell
winget install Microsoft.PowerShell     # optional; 5.1 works if you skip it
```

Note that **your Dreaming hooks may still run under 5.1 regardless** of what you install: the session-event handlers invoke `powershell`, and on a typical Windows box that name resolves to 5.1 even when `pwsh` is present. That is why 5.1 stays supported and tested rather than merely tolerated.

### Windows specifics

These four are the only Windows behaviors that differ enough to matter:

- **Use the PowerShell installers, not Git Bash.** `bootstrap.sh` refuses to run under Git Bash/MSYS and points you at `bootstrap.ps1`. Windows process creation costs ~50–100 ms, and a full install copies and hashes ~1000 files one child process at a time: **9+ minutes** per install under Git Bash versus about a minute under PowerShell, with no output for most of it — indistinguishable from a hang. Override with `--allow-msys` if you truly want it. **WSL is unaffected** — inside WSL this is Linux, and bash is the right path.
- **`python3` may be a decoy.** The Microsoft Store ships a `python3` stub that resolves on `PATH`, prints an install hint, and exits non-zero; the python.org installer provides `python.exe` with **no** `python3.exe`. Every pack script probes `python3` → `python` → `py -3` by executing it, so a correct install works either way. If you see a Microsoft Store hint where you expected Python, that is the stub.
- **Developer Mode controls `.claude/skills`.** With it on, `.claude/skills` is a live symlink to `.github/skills` and skill edits appear immediately. Without it the installer copies the directory, so re-run the installer after editing a skill. Windows PowerShell 5.1 often cannot create symlinks even with Developer Mode on, while PowerShell 7 usually can — the main practical reason to prefer `pwsh`. `check-environment.ps1` tells you which you will get.
- **Line endings.** The pack pins shell scripts to LF via `.gitattributes`. If your checkout predates that file and you also use it from WSL, run `git add --renormalize . && git checkout -- .` — bash on Linux/macOS rejects a CRLF script with `$'\r': command not found`.

> **Contributors — run the PowerShell suites under _both_ hosts.** Windows PowerShell 5.1 and PowerShell 7 are different runtimes with different failure modes, and a green run on one proves nothing about the other. 5.1 is .NET Framework (no `ProcessStartInfo.ArgumentList`), it promotes native-command stderr to a *terminating* error under `$ErrorActionPreference='Stop'`, and its `-Encoding UTF8` writes a BOM that Python's `json.load` rejects. Every one of those produced a real, silent Windows defect that a fully green PowerShell 7 run reported as fine.
>
> ```powershell
> powershell -File tests\_qi\automated\e2e-bootstrap.ps1   # Windows PowerShell 5.1
> pwsh       -File tests\_qi\automated\e2e-bootstrap.ps1   # PowerShell 7+
> powershell -File tests\_qi\automated\e2e-dreaming.ps1
> pwsh       -File tests\_qi\automated\e2e-dreaming.ps1
> bash .assert-iq/tests/_qi/automated/run-all.sh           # includes e2e-hook-execution.py
> ```
>
> The suites print which host they ran under for exactly this reason.

## Get started

### 1 · Install the pack

**What this does.** It copies Assert.IQ into a project you already have, then tells git to ignore those files. Nothing gets committed. Your teammates see nothing. Your project's `.gitignore` is never touched. This is called **trial mode**, and it's the safe way to start — you can undo it completely at any time.

It's four commands, run once. **Step 3 checks that your machine is set up correctly before anything gets installed — please don't skip it.**

#### On a Mac

Open **Terminal** and run these one at a time:

```bash
# 1. Download the pack. Do this once — it can live anywhere on your machine.
git clone https://github.com/fromjariuswithsparq/assert-iq-agent-pack ~/assert-iq-agent-pack

# 2. Go to the project you want to use Assert.IQ in.
cd ~/code/my-app

# 3. Check your machine is ready. Run this from inside your project.
bash ~/assert-iq-agent-pack/scripts/check-environment.sh

# 4. Install it into that project.
bash ~/assert-iq-agent-pack/scripts/bootstrap.sh --mode=trial
```

#### On Windows

Open **PowerShell**. Not Command Prompt, and not Git Bash — those will fail. Then run these one at a time:

```powershell
# 1. Download the pack. Do this once — it can live anywhere on your machine.
git clone https://github.com/fromjariuswithsparq/assert-iq-agent-pack $HOME\assert-iq-agent-pack

# 2. Go to the project you want to use Assert.IQ in.
cd $HOME\code\my-app

# 3. Check your machine is ready. Run this from inside your project.
pwsh -File $HOME\assert-iq-agent-pack\scripts\check-environment.ps1

# 4. Install it into that project.
pwsh -File $HOME\assert-iq-agent-pack\scripts\bootstrap.ps1 -Mode trial
```

If Windows says `pwsh` isn't recognized, use `powershell` instead — the older version works too.

#### Reading the environment check

Step 3 prints one line per requirement, then a verdict at the bottom:

- **`Ready to install.`** — everything passed. Go to step 4.
- **`Ready to install, with N warning(s)`** — safe to continue. A `[WARN]` means reduced functionality, not a broken install (for example, no Developer Mode on Windows, so `.claude/skills` gets copied instead of symlinked).
- **`Not ready: N blocking issue(s)`** — stop. Each `[FAIL]` line prints the exact command to fix it. Fix them, run step 3 again, and continue once it says ready.

Run it from **inside your project**, as shown above. It checks the folder you're standing in — that it's a git repo, and that the pack isn't already installed there — so running it from somewhere else reports on the wrong folder.

**Then, on either platform,** reload your editor so it picks up the new files:

- **VS Code** — press `Cmd/Ctrl + Shift + P`, then pick **Developer: Reload Window**
- **Claude Code** — restart the session

That's it. Skip to step 2.

> **Just want to poke at Assert.IQ without involving a project of your own?** You can open the pack folder itself as your workspace instead. That, plus every other way to install — sharing with your team, installing skills globally, air-gapped setups — is covered in [detailed install options →](README.assert-iq.md#installation).

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

### Update to a newer version

Two steps: refresh your copy of the pack, then run the same install command again. Re-installing is safe — it replaces the pack's own files and leaves your edits to `config.yaml`, `governance.md`, and `maturity-profile.md` alone.

Worth a look first: the [Releases page](https://github.com/fromjariuswithsparq/assert-iq-agent-pack/releases) says what changed.

#### On a Mac

```bash
# 1. Get the newest version of the pack.
cd ~/assert-iq-agent-pack
git pull

# 2. Go back to your project and re-run the install.
cd ~/code/my-app
bash ~/assert-iq-agent-pack/scripts/bootstrap.sh --mode=trial
```

#### On Windows

```powershell
# 1. Get the newest version of the pack.
cd $HOME\assert-iq-agent-pack
git pull

# 2. Go back to your project and re-run the install.
cd $HOME\code\my-app
pwsh -File $HOME\assert-iq-agent-pack\scripts\bootstrap.ps1 -Mode trial
```

Reload your editor afterwards, the same way you did after installing.

---

### Uninstall

One command, run inside your project. It removes every file the pack added and puts back anything of yours it had replaced. If you had your own `CLAUDE.md` or `AGENTS.md` before installing, you get your original file back.

#### On a Mac

```bash
cd ~/code/my-app
bash ~/assert-iq-agent-pack/scripts/bootstrap.sh --uninstall
```

#### On Windows

```powershell
cd $HOME\code\my-app
pwsh -File $HOME\assert-iq-agent-pack\scripts\bootstrap.ps1 -Uninstall
```

You can delete the `~/assert-iq-agent-pack` folder too if you're done with it entirely.

---

## What's inside

```
.github/
  copilot-instructions.md     ← always-on QI reasoning rules for Copilot
  instructions/               ← 6 scoped rule sheets (tests, C#/XAML, CI, oracle, etc.)
  skills/                     ← 31 QI skills, one subfolder each
  agents/                     ← Assert-IQ and Assert-IQ-PLAN lead agent definitions
    specialists/              ← 8 specialists, GENERATED by scripts/sync-agents.sh
.claude/
  agents/                     ← Claude Code lead + grader subagents
    specialists/              ← 8 v2.0 orchestration specialists (JSON-only output)
  skills → ../.github/skills  ← symlink (copy on Windows without Dev Mode)
.vscode/
  mcp.json                    ← 20 MCP server definitions
  MCP.md                      ← per-server credential and setup guide
.assert-iq/                   ← per-repo config (created by bootstrap)
  memory/                     ← Dreaming memory store (MEMORY.md, topics/, logs/)
  dreaming/                   ← waking-loop recorder, dream gate, optional cron dreamer
  agent-runs/                 ← v2.0 orchestration audit trail
  business-metrics/           ← v2.0 baseline metrics + quarterly ROI dashboards
scripts/
  bootstrap.sh / .ps1         ← workspace installer, cross-platform
  sync-agents.sh / .ps1       ← renders the Copilot specialists from .claude sources
```

---

## Go deeper

The steps above are the fast path. When you're ready for the full picture — including every other way to install, how to share the pack with your team, and the full skill reference:

**[FEATURES.md →](FEATURES.md)** — the Feature Guide: all eight features and all 31 skills, each with what it is, how to use it, when to use it, and why it matters.

**[README.assert-iq.md →](README.assert-iq.md)** — detailed install options (drop-in / air-gapped / trial vs. committed), full skill reference, maturity tier matrix, MCP server inventory, Dreaming architecture, and full release history.

Tool-specific references:
- Feature guide — [`FEATURES.md`](FEATURES.md)
- VS Code / Copilot — [`.github/vscode-readme.md`](.github/vscode-readme.md)
- Claude Code — [`.claude/claude-readme.md`](.claude/claude-readme.md)
- MCP servers — [`.vscode/MCP.md`](.vscode/MCP.md)
