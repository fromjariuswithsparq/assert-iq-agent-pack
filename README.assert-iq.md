# Assert.IQ Agent Pack

> The capability layer of Assert.IQ. Quality Intelligence-grounded skills,
> instructions, modes, and tools that turn GitHub Copilot Chat **and**
> Claude Code into a QI-aware delivery partner inside the IDE.

**Version**: v1.1.7
**Status**: Internal Sparq asset — Intelligence Studio
**Owner**: Jarius Hayes
**Repo**: <https://github.com/fromjariuswithsparq/assert-iq-agent-pack>

---

## What this is

This pack drops into a client codebase and gives the development team an
opinionated, QI-grounded layer over **GitHub Copilot Chat and Claude Code**
in VS Code (and any other `AGENTS.md`-aware tooling: Codex CLI, Cursor,
Aider). It is *not* a SaaS product. It is *not* a runtime. It is a
versioned set of files — markdown, YAML, JSON — that lives in the repo
and is owned by the team.

The pack operationalizes Sparq's Quality Intelligence framework:

- The four-layer signal model (Change → Protection → Trust → Outcome →
  Decision Confidence) is loaded as Copilot's reasoning lens on every interaction.
- 24 skills cover the QE lifecycle: planning, development, review, execution,
  decision, and post-incident learning.
- A QI Advisor chat mode provides maturity-aware coaching.
- MCP wiring connects to ADO or Jira and to GitHub for first-class
  bidirectional context.

QI is the operating model. Assert.IQ is the commercialized acceleration.
This pack is one concrete way teams *act* on QI — without ever becoming a
tooling pitch.

---

## Dual-target: Copilot and Claude Code

The pack ships one canonical copy of every asset and exposes it through both
tools' native config surfaces. There is no duplicated content — only thin
entry-point files (`CLAUDE.md`, `AGENTS.md`, `.claude/agents/*`) plus a
short installer that wires `.claude/settings.json` and the skills symlink.

| Asset | Canonical location | Copilot reads | Claude reads |
|---|---|---|---|
| Always-on guidance | `.github/copilot-instructions.md` (Copilot-native) + mirrored body in `CLAUDE.md` | `.github/copilot-instructions.md` | `CLAUDE.md` |
| Scoped instructions | `.github/instructions/*.instructions.md` | same (auto via `applyTo`) | same (via `@`-imports in `CLAUDE.md`; "When this applies" prose) |
| Skills (22) | `.github/skills/*/SKILL.md` | `.github/skills/` directly | `.claude/skills/` (symlink → `.github/skills/`) |
| Chat mode / subagent | `.github/agents/Assert-IQ.agent.md` + `.github/agents/Assert-IQ-PLAN.agent.md` (Copilot) + `.claude/agents/assert-iq.md` + `.claude/agents/assert-iq-plan.md` (Claude) | agent files | subagent files |
| Hooks | `hooks.json` (pack root) + `hooks/scripts/`, `hooks/config/` | yes (via `chat.hookFilesLocations`) | `.claude/settings.json` (hooks block, synced by installer) |
| MCP wiring | `.vscode/mcp.json` | yes | yes (VS Code MCP is tool-agnostic) |
| Per-client config | `.assert-iq/*` | yes | yes |
| Generic agent pointer | `AGENTS.md` | n/a | n/a (read by Codex CLI / Cursor / Aider) |

**After dropping the pack into a repo, run the installer once:**

```bash
bash install.sh        # macOS / Linux
.\install.ps1          # Windows PowerShell
```

The installer is idempotent. It (1) syncs `hooks.json` into
`.claude/settings.json` (merging — it preserves any other settings keys you
have), and (2) creates `.claude/skills` as a symlink to `../.github/skills`
(falling back to a copy on Windows without Developer Mode — in that case
re-run the installer after editing skills).

Copilot requires no extra wiring — it reads `.github/*` natively.

> **Note on the `.html` siblings.** The `*.html` files at the repo root
> (`README.html`, `README.assert-iq.html`, `claude-readme.html`,
> `vscode-readme.html`, `hooks-readme.html`, `MCP.html`) are rendered
> snapshots of the corresponding `.md` files, intended for offline /
> static-host distribution. They are **not** the source of truth — edit
> the `.md` files only and regenerate the HTMLs from those. If you change
> a doc and don't refresh the HTML, the two will drift.

---

## Installation

The pack supports exactly two install paths. They serve different needs
— pick based on whether you're evaluating Assert.IQ or actually
deploying it into a team's repo.

### Path A — try it on the pack repo itself

Best when you want to play with Assert.IQ without touching your team's
repository. You clone the pack, run the installer, and open the **pack
folder** as your VS Code / Claude Code workspace. Everything runs
against the pack's own files.

```bash
git clone https://github.com/fromjariuswithsparq/assert-iq-agent-pack
cd assert-iq-agent-pack
bash install.sh        # macOS / Linux / WSL
# or
pwsh ./install.ps1     # Windows PowerShell 7+
```

What it does (all inside the pack folder):

1. Renders `hooks/hooks.json` from `hooks/hooks.template.json` with the
   pack root absolute path baked in (VS Code Copilot has no env var
   equivalent of `CLAUDE_PLUGIN_ROOT`, so the path is resolved at
   install time).
2. Merges the rendered `hooks` block into `.claude/settings.json`,
   preserving any other keys you already have.
3. Creates `.claude/skills` as a symlink to `../.github/skills` so
   Claude Code discovers the same skills Copilot does (falls back to a
   copy on Windows without Developer Mode — re-run after edits in that
   case).

Idempotent on every platform — safe to re-run any time. Reverse it
cleanly with `bash install.sh --uninstall` (or `pwsh ./install.ps1
-Uninstall`).

### Path B — install it into your codebase

This is the real deployment path. Bootstrap copies the full set of
workspace-loaded surfaces into a target repo so Copilot Chat and Claude
Code can discover the skills, agents, instructions, hooks, and config
from that codebase.

**Run the bootstrap script from a terminal in your target repo.** No
editor required, nothing to install in chat first:

```bash
# 1. Clone the pack somewhere on your machine (one time, anywhere)
git clone https://github.com/fromjariuswithsparq/assert-iq-agent-pack ~/assert-iq-agent-pack

# 2. cd into YOUR repo
cd ~/code/my-app

# 3. Run the bootstrap script from the clone
bash ~/assert-iq-agent-pack/scripts/bootstrap.sh --mode=trial
# Windows PowerShell:
pwsh -File ~\assert-iq-agent-pack\scripts\bootstrap.ps1 -Mode trial
```

The script is fully standalone — it accepts `--preset=solo|pod`,
prompts interactively when run in a TTY, and writes everything Copilot
and Claude need into your workspace. **There is no chicken-and-egg.**
You do not need to open VS Code or Claude Code first, and the
`/assert-iq-bootstrap` skill does not need to be loaded — the script
is what the skill calls under the hood.

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

> **Already have the pack loaded** (the cloned pack opened in your
> editor, or the skills installed user-globally to
> `~/.agents/skills/`)? You can also run `/assert-iq-bootstrap` from
> chat — same outcome, chat-driven prompts.

`--mode=trial` is the safe default: every pack file lands in your
workspace, and each path is added to `.git/info/exclude` so your team
sees nothing. **Your codebase's `.gitignore` is never touched.** When
you're ready for the team to see it, run
`bash scripts/bootstrap.sh --graduate` (or use `--mode=committed` from
the start).

#### Portable mode — skills user-globally, minimal workspace footprint

If you'd rather not put the full pack into your workspace (not even in
trial mode), use `--preset=portable`. Skills install to
`~/.agents/skills/` (VS Code Copilot Chat) and `~/.claude/skills/`
(Claude Code) so every workspace you open has the 24 QI skills
available. Workspace footprint shrinks to just the Assert-IQ chat
agent files (`.github/agents/`, `.claude/agents/`) and the install
manifest — no instructions, hooks, settings, MCP config, or `CLAUDE.md`
are written into the repo.

```bash
bash ~/assert-iq-agent-pack/scripts/bootstrap.sh --preset=portable
# Reverse with: --uninstall --user
```

You can also opt in à la carte with `--skills-scope=user` (default is
`workspace`; `both` puts skills in both places).

### Pinning to a tag

Use `git checkout v1.1.7` (or `git clone --branch v1.1.7`) on the cloned
copy. Use the latest tag from the
[Releases page](https://github.com/fromjariuswithsparq/assert-iq-agent-pack/releases).
The pack is on the stable `1.x` line — bootstrap CLI flags, manifest
schema, skill names, and workspace surface layout will not change in
incompatible ways without a major-version bump.

### What bootstrap delivers (Path B)

The bootstrap copies the **complete workspace surface** into the target
repo. Copilot and Claude Code can't auto-discover skills or agents that
aren't physically present in the workspace, so all of them ship in.

| Surface | Why it's per-repo |
|---|---|
| `.assert-iq/config.yaml` | Maturity tier, tracker, framework, signal sink — varies by repo. |
| `.assert-iq/governance.md` | Compliance posture — varies by client / regulatory regime. |
| `.assert-iq/maturity-profile.md` | Tier rationale — team-specific. |
| `.github/copilot-instructions.md` + `.github/instructions/qi-*.instructions.md` | Copilot reads these only from the workspace; their `applyTo` globs scope to repo files. |
| `.github/skills/` | All 24 QI skills — Copilot Chat reads them from this workspace path. |
| `.github/agents/` | `Assert-IQ.agent.md` and `Assert-IQ-PLAN.agent.md` custom chat modes. |
| `.claude/agents/` | Claude Code subagent counterparts (`assert-iq.md`, `assert-iq-plan.md`). |
| `.claude/skills` | Symlink to `../.github/skills` (copy fallback on Windows without Developer Mode) so Claude Code discovers the same skills. |
| `CLAUDE.md` / `AGENTS.md` | Claude and other agent runners read these from the repo root. |
| `.vscode/settings.json` + `.vscode/mcp.json` | Wires VS Code Copilot to read instructions, prompts, and **hooks** from the workspace; declares optional GitHub / ADO / Jira MCP servers. JSON deep-merged into any pre-existing settings (additive; your values win on conflicts). |
| `hooks/` (`scripts/`, `lib/`, `config/`, `hooks.json`) | The hook scripts that fire on `SessionStart` / `PostToolUse` / `Stop`. `hooks.json` is rendered at bootstrap time so the script paths resolve to the workspace copies. |
| `.claude/settings.json` | Claude Code reads the `hooks` block from here. Bootstrap merges only the `hooks` key, preserving any other settings you have. |

### Trial vs Committed (Path B)

Three install modes, all driven by the bootstrap script
(`scripts/bootstrap.sh` / `scripts/bootstrap.ps1`):

| Mode | What happens | Reverse with |
|---|---|---|
| `--mode=trial` | Files land in workspace; their paths added to `.git/info/exclude` (local-only). `.gitignore` untouched. | `--graduate` (promote) or `--uninstall` (remove) |
| `--mode=committed` | Files land in workspace and are visible to git. | `--uninstall` |
| `--mode=ask` (default in TTY) | Prompts interactively. Non-TTY falls back to `committed`. | — |

**Pre-existing files are preserved.** The script SHA256-compares each
file. If the destination matches the pack version, it's silently
recorded as `unchanged_owned`. If the user has a different file at that
path, the script falls back to an interactive resolver:
`[k]eep` / `[o]verwrite` / `[s]idecar (writes .assert-iq-new)` /
`[d]iff` / `[K/O/S]all` / `[a]bort`. Non-TTY runs auto-keep.

**Pre-install backups for safe uninstall.** Whenever the bootstrap
overwrites or merges into a file you already had, it first snapshots the
original to `<file>.assert-iq.pre-install`. A later
`scripts/bootstrap.sh --uninstall` restores from that snapshot
byte-for-byte; if the file changed since install, the post-install copy
is preserved at `<file>.assert-iq.uninstall-saved` so nothing is silently
lost.

Every install writes `.assert-iq/.install-manifest.json` recording
`{version, installed_at, mode, paths[]}`. Trial mode uses this manifest
to know which paths to add to `.git/info/exclude` (and which to remove
on `--graduate`). Uninstall reads the same manifest.

**Graduating from trial → committed:**

```bash
# macOS / Linux
scripts/bootstrap.sh --graduate

# Windows
pwsh -File scripts/bootstrap.ps1 -Graduate

# Then commit the pack files when ready:
git add .assert-iq .claude .github CLAUDE.md AGENTS.md
git commit -m "chore: adopt Assert.IQ agent pack"
```

**Removing the pack from a workspace:**

```bash
# macOS / Linux
scripts/bootstrap.sh --uninstall          # add --user to also remove user-global copies
scripts/bootstrap.sh --uninstall --dry-run  # preview without changing anything

# Windows
pwsh -File scripts/bootstrap.ps1 -Uninstall
pwsh -File scripts/bootstrap.ps1 -Uninstall -DryRun
```

### Upgrading to a new release

Upgrades are an explicit, intentional act. To move to a later tag:

1. Read the release notes on the
   [Releases page](https://github.com/fromjariuswithsparq/assert-iq-agent-pack/releases).
2. Uninstall the path you used:
   - **Path A:** `bash install.sh --uninstall` in the cloned pack.
   - **Path B:** `bash scripts/bootstrap.sh --uninstall` in each
     target repo.
3. `git pull` (or re-clone) to the new tag, then re-run the same path
   to refresh.

### Platform notes (`.claude/skills` symlink)

The installer creates `.claude/skills` as a **directory symlink** pointing
at `../.github/skills/`, so Copilot and Claude share one canonical copy of
the 24 skills. Behavior varies by platform:

| Platform | What happens | What you need to do |
|---|---|---|
| **macOS / Linux** | Symlink created normally. | Nothing — edits to either path reflect instantly. |
| **Windows + Developer Mode (or admin shell)** | Symlink created normally. | Enable Developer Mode once: `Settings → Privacy & security → For developers → Developer Mode On`. Then run `install.ps1`. |
| **Windows without Developer Mode / admin** | Installer **falls back to copying** `.github/skills/` → `.claude/skills/` and logs the fallback. | **Re-run `install.ps1` after editing any skill** so Claude sees the change. There is real drift risk here — prefer Developer Mode. |
| **CI runners, Docker `COPY`, manual zip downloads** | Symlinks may not be preserved — you may get a broken link or a copy. | Prefer the GitHub-generated source tarball (preserves symlinks), or run `install.sh` / `install.ps1` after checkout to repair the link. |

The installer is idempotent on every platform — re-running it is always
safe.

---

## The four layers of the pack

```
LAYER          PRIMITIVE                                  ROLE
─────────      ─────────────────────────────────          ──────────────────────────
Foundation     .github/copilot-instructions.md            Always-on QI guidance
               .github/instructions/*.instructions.md     (loaded automatically;
               CLAUDE.md                                   Claude reads CLAUDE.md)

Skills         .github/skills/<name>/SKILL.md             Invokable workflows
               (mirrored read-only at .claude/skills/)    (called via /skill-name)

Modes          .github/agents/Assert-IQ.agent.md          Default front-door agent
               .github/agents/Assert-IQ-PLAN.agent.md     Read-only planning sibling
               .claude/agents/assert-iq{,-plan}.md         Claude Code subagents

Tools          .vscode/mcp.json                           External integrations
                                                          (ADO, Jira, GitHub)

Hooks          hooks/hooks.json + hooks/scripts/          Retrospective skill
               (wired via .vscode/settings.json and        refinement on session
               .claude/settings.json)                      end
```

---

## Quick start

### 1. Drop the pack into the client repo

Copy these directories into the repo root:
- `MANIFEST.md` (root-level inventory of all files in the pack)
- `README.assert-iq.md`
- `CLAUDE.md` + `AGENTS.md`       ← always-on guidance for Claude Code and other `AGENTS.md`-aware tooling
- `.github/copilot-instructions.md`
- `.github/instructions/`
- `.github/skills/`               ← each skill is a folder with a `SKILL.md`
- `.github/agents/`               ← `Assert-IQ.agent.md` + `Assert-IQ-PLAN.agent.md`
- `.claude/`                      ← `agents/`, `settings.json`; `.claude/skills/` is created as a symlink by the installer
- `.vscode/mcp.json`
- `.vscode/settings.json`         ← wires `.github/skills/` into Copilot prompt-file loading and points `chat.hookFilesLocations` at `./hooks/hooks.json`
- `hooks/`                        ← `scripts/`, `lib/`, `config/`, and the rendered `hooks.json`
- `.assert-iq/`
- `tests/_qi/` (if not already present)

> **Note on hidden directories.** `.github/`, `.vscode/`, `.claude/`, and `.assert-iq/` are dot-prefixed
> and hidden by default in macOS Finder and Windows Explorer. Show hidden files
> (`Cmd+Shift+.` on macOS; View → Hidden items on Windows) to see them, or open
> the folder in VS Code which shows all files. The `MANIFEST.md` at the root
> lists every file in the pack so you can verify the extraction is complete.

### 2. Configure for the client context

Open `.assert-iq/config.yaml` and set:
- `client.name`
- `maturity.tier` — `early`, `mid`, or `higher` based on the QI Diagnostic
- `tracker.type` — `ado` or `jira`, plus the connection details
- `vcs.type` — `github`, `ado-repos`, `gitlab`, or `bitbucket`
- `test_framework` — primary framework, language, test command
- `manual_test_management.tool` — `ado_test_plans`, `xray`, `testrail`,
  `zephyr`, or `markdown`

Open `.assert-iq/maturity-profile.md` and document the rationale for the
chosen tier.

### 3. Wire MCP

Open `.vscode/mcp.json` and confirm the servers for the configured tracker
and VCS are enabled. Provide the required PATs / API tokens at the input
prompts.

### 4. Validate

In Copilot Chat, type:

```
/risk-assess-pr
```

The agent should respond with a four-layer scaffolded assessment of the
current branch. If MCP is wired correctly, it will pull live work item
data; if not, it will ask for it.

### 5. Pick a starter skill for the team

Recommended first invocations:
- Plan phase: `/review-acceptance-criteria` on a recent work item
- Develop phase: `/generate-tests-from-ac` on the same work item
- PR phase: `/code-review` on the current branch

---

## The skill registry

Skills are organized by QE lifecycle phase. All skills are invoked in
Copilot Chat with `/skill-name`. Maturity gating is enforced by each skill
that requires it.

### Plan

| Skill | Purpose |
|---|---|
| `/review-acceptance-criteria` | Review ACs for testability before generation. |
| `/generate-test-plan` | Generate a one-page operating test plan. |
| `/generate-tests-from-ac` | Router — classify each AC and dispatch to automation, manual, or exploratory. |

### Develop

| Skill | Purpose |
|---|---|
| `/generate-automated-unit-test` | Generate unit tests for a function, class, or module. |
| `/generate-automated-api-test` | Generate API tests with schema validation and error envelopes. |
| `/generate-automated-ui-test` | Generate UI tests using Page Object Model and stable selectors. |
| `/generate-manual-test-case` | Generate scripted manual test cases for ADO Test Plans / Xray / TestRail / markdown. |
| `/generate-exploratory-charter` | Generate a session-based exploratory test charter. |
| `/generate-test-data` | Generate deterministic, PII-safe test data using the project's factory pattern. |

### Code Review / PR

| Skill | Purpose |
|---|---|
| `/code-review` | Review changes through the QI four-layer lens. |
| `/check-test-coverage` | Risk-weighted coverage analysis on changed surfaces. |
| `/check-merge` | Pre-merge quality gate aggregating all signals into a verdict. |
| `/new-pull-request` | Open a PR with a QI-aware body — risk band, AC linkage, traceability. |
| `/review-test-quality` | Review existing tests for design quality (independence, determinism, brittle patterns). |

### Execute / Debug

| Skill | Purpose |
|---|---|
| `/debug-ui-tests` | Diagnose a failing UI test — flaky vs brittle vs broken vs regression. |
| `/analyze-flaky-test` | Pattern analysis over historical run data to identify flake root causes. |
| `/agentic-heal` | Autonomously diagnose, repair, and re-execute failing tests within bounded retries. (Mid+ maturity) |

### Decision

| Skill | Purpose |
|---|---|
| `/risk-assess-pr` | Score a PR across all four QI layers and post a structured comment. |
| `/release-confidence` | Aggregate signals across an upcoming release into a go/no-go report. (Mid+ maturity) |

### Learn

| Skill | Purpose |
|---|---|
| `/analyze-escaped-defect` | Post-incident analysis — which signal layer should have caught it. |
| `/generate-bug-report` | Convert a failure into a tracker-ready defect. |

### Cross-cutting

| Skill | Purpose |
|---|---|
| `/generate-traceability-matrix` | Build a req↔code↔test matrix from `@qi-trace` headers. |
| `/generate-hotspot-map` | Audit code volatility, structural complexity, and defect density for risk prioritization. |

---

## How to use

### Invoking a skill

Open Copilot Chat in VS Code. Type `/` to see available skills. Type the
skill name to invoke. Provide inputs when prompted, or skip if the skill
can resolve them from context (work item from branch name, scope from current
diff, etc.).

### Using the Assert-IQ agents

Pick **`Assert-IQ`** from the agent dropdown for default behavior — it
routes to the right skill and has full tools to act. Pick
**`Assert-IQ-PLAN`** when you want plan-first behavior on a larger or
riskier task; it produces a plan and surfaces a **Start Implementation**
handoff button that switches back to `Assert-IQ` for execution. Both
agents are maturity-aware: they adjust recommendations based on
`maturity.tier` and proactively raise traceability gaps, coverage gaps
on changed surfaces, flaky tests near touched code, and governance
concerns when AI is being applied to high-risk areas.

### Combining skills

Skills compose. A typical PR-time workflow:

```
/review-acceptance-criteria PROJ-123
/generate-tests-from-ac PROJ-123
   → routes to /generate-automated-unit-test, /generate-manual-test-case, etc.
/code-review
/check-test-coverage
/check-merge
/new-pull-request
```

A typical post-incident workflow:

```
/analyze-escaped-defect PROJ-456
   → produces gap analysis + recommended regression test
/generate-tests-from-ac     (for the recommended regression)
/generate-bug-report          (if the analysis surfaces additional issues)
```

---

## Maturity awareness

The pack reads `.assert-iq/maturity-profile.md` and adjusts behavior:

| Tier | Behavior |
|---|---|
| **Early** | Foundation + traceability + manual generation only. Agentic Healing disabled. Risk assessment and release confidence operate in advisory mode without strong opinions. Manual fallback produced even when ACs route to automation. |
| **Mid** | Add risk assessment, automated test generation, healing in suggest-only mode. Routing classifier operates as designed. |
| **Higher** | Full pack including autonomous healing within configured retry bounds. Predictive release confidence enabled. Routing classifier flags manual ACs that could be automated. |

Maturity is set during the QI Diagnostic and re-evaluated quarterly.

---

## Governance & guardrails

The pack enforces governance at multiple layers:

| Concern | Control |
|---|---|
| AI-generated tests merged without review | `@qi-review-required true` header + branch protection |
| Healing patches production code | `allowed_scope: test-only` default, regression escalation |
| Secrets in prompts or signals | Mask rule in foundation instructions, secret scanning in CI |
| Premature acceleration on low-maturity | Maturity tier gate in every applicable skill |
| Vendor lock-in | Markdown / YAML / JSON only — portable to other LLM IDE tools |
| Signal payload drift | JSON schema in `.assert-iq/signal-schema.json` |
| IP leakage via MCP tool calls | Scoped PATs, audit logging |
| Hallucinated traceability | Trace must reference a real work item resolvable via MCP |
| Compliance violations | `governance.md` defines client compliance posture |
| Auto-creating defects without review | `bug_reporter.auto_create_threshold` |

Every skill includes an explicit Governance section. Read it before
delegating the skill to a less-experienced engineer.

---

## Customization

### Common customizations

| Need | Where |
|---|---|
| Switch test framework | `.assert-iq/config.yaml` → `test_framework.primary` |
| Switch tracker (ADO ↔ Jira) | `.assert-iq/config.yaml` → `tracker.type` and `.vscode/mcp.json` |
| Adjust maturity tier | `.assert-iq/config.yaml` → `maturity.tier` and `.assert-iq/maturity-profile.md` |
| Change healing retry bound | `.assert-iq/config.yaml` → `agentic_healing.retry_bound` |
| Add a domain skill (e.g., performance, accessibility) | New folder under `.github/skills/<name>/` with a `SKILL.md` |
| Adjust client-specific code patterns | `.github/instructions/qi-test-design.instructions.md` |
| Change telemetry sink | `.assert-iq/config.yaml` → `signals.sink` |

### Adding a new skill

1. Create a folder at `.github/skills/your-skill/` containing `SKILL.md` with:
   - YAML frontmatter with `name`, `description`, and `mode: agent`
   - `# Title`
   - `## Inputs`
   - `## Procedure`
   - `## Governance`
2. If the skill needs supporting templates (XML, CSV, schemas, examples), drop
   them in the same folder. Reference them from `SKILL.md` by relative path.
3. If the skill needs new instructions, add a corresponding
   `.instructions.md` file in `.github/instructions/` with an `applyTo` glob.
4. Update this README's skill registry and the root `MANIFEST.md`. Because
   `.claude/skills/` is a symlink to `.github/skills/`, Claude Code picks
   the new skill up automatically — no second copy needed.

---

## Troubleshooting

**The skill says it can't find the work item.**
Confirm MCP is wired (`.vscode/mcp.json`) and the PAT has read access.
Test by running a minimal MCP query directly.

**Generated tests don't match our framework conventions.**
Update `.github/instructions/qi-test-design.instructions.md` with explicit
examples of your project's pattern. The agent reads instructions before
generating.

**Healing keeps escalating regressions but the test is wrong.**
This is by design — healing never patches production code. If the test
expectation is genuinely outdated, fix the test directly or use
`/debug-ui-tests` with the `broken` classification path.

**Risk assessment scores feel off.**
Adjust the weighting heuristics in
`.github/skills/risk-assess-pr/SKILL.md`. Each layer is independently
tunable.

**The router sends too many ACs to manual.**
Tighten `routing.automation_threshold` in `config.yaml`, or adjust the
classification heuristics in
`.github/skills/generate-tests-from-ac/SKILL.md`.

**Skill outputs feel generic.**
The pack relies on instructions files for project-specific shape. Update
`qi-test-design.instructions.md`, `qi-manual-test-design.instructions.md`,
or `qi-traceability.instructions.md` with examples drawn from your codebase.

---

## What this pack is not

- It is not a runtime. There is no service to deploy.
- It is not a SaaS. The client owns the files; if Sparq rotates off the
  account, the pack stays.
- It is not a replacement for QE judgment. Every output is a draft;
  human review is required.
- It is not a tooling pitch for Assert.IQ. Use it where the maturity
  supports it. Lead with QI thinking, not with this pack.

---

## Versioning

| Version | Notes |
|---|---|
| 0.1.0 | Foundation, instructions, MCP, 9 starter skills (as `.prompt.md` files). |
| 0.1.5 | Manual & Exploratory addendum — router, manual test design, charter generator. |
| 0.2.0 | Renamed to Agent Pack. Added 9 lifecycle skills. |
| 0.3.0 | Added 8 high-leverage skills. README, governance template, maturity-profile template. 22 skills total. |
| 0.4.0 | Skills refactored to `.github/skills/<name>/SKILL.md` directory structure. Added `MANIFEST.md`, `.vscode/settings.json`. README updated. |
| 0.5.0 | Dual-target support: works with both GitHub Copilot Chat and Claude Code from the same pack folder. Added `CLAUDE.md`, `AGENTS.md`, `.claude/agents/`, `.claude/settings.json`, `.claude/skills/` symlink, `install.sh` / `install.ps1`. Added "When this applies" prose to all five instruction files. Hooks integrated under `hooks/`. |
| 0.6.x | Bootstrap rewrite: `scripts/bootstrap.sh` / `.ps1` with `trial` / `committed` / `ask` modes, `solo` / `pod` presets, interactive conflict resolver, `.git/info/exclude` for trial mode (codebase `.gitignore` untouched), and `--graduate` to flip trial → committed. `.assert-iq/.install-manifest.json` written on every install. |
| 0.7.0-rc.1 | Claude plugin format: `.claude-plugin/plugin.json`, `hooks/hooks.json` with portable `${CLAUDE_PLUGIN_ROOT}` paths. Single install path for both VS Code Copilot and Claude Code. |
| 0.7.0-rc.2 | Added `.claude-plugin/marketplace.json` so VS Code Copilot's `Chat: Install Plugin From Source` accepts the repo. README install instructions clarified (no `@ref` pinning on the Copilot side). |
| 0.7.0-rc.3 | Bootstrap surfaces three more workspace artifacts: `.vscode/` (settings + mcp), `hooks/` (scripts + rendered `hooks.json`), and `.claude/settings.json`. Additive JSON deep-merge for settings files — user's scalar values win on conflicts, object keys union from both sides — so pre-existing user config is never clobbered. Hook scripts now actually fire after a plugin install. |
| 0.7.0-rc.4 | Bootstrap now also surfaces the Hindsight Hooks runtime directories — `hooks/state/` (seed JSON for `dismissed-lessons` and `edit-frequency`), `hooks/logs/` (writable log sink), and an empty `hooks/sessions/` directory for per-session scratch. Without these, hooks fired but had no state to read or anywhere to write. Trial-mode `.git/info/exclude` now records 38 paths (was 35). |
| 0.7.0-rc.5 | Hardened bootstrap manifest and hook path rendering (PR #3). Validated apply-selection tokens in `skill-improve-apply` so invalid selections no longer silently dismiss candidates (PR #4). |
| **0.7.0** | **First official release. Windows verified end-to-end. Fixes since rc.5: escaped `$manifestPath` interpolation in the bootstrap graduate log (PR #5); trial-mode unignore guidance added to README (PR #6); Windows hook commands switched to `pwsh -File` so PS1 hooks fire correctly on Windows (PR #7).** |
| **0.8.0** | **Expanded MCP server catalog.** `.vscode/mcp.json` now wires 20 MCP servers (was 3): adds `git`, `gitlab`, `bitbucket`, `filesystem`, `postgres`, `sqlite`, `aws`, `sentry`, `grafana`, `datadog`, `honeycomb`, `playwright`, `puppeteer`, `notion`, `confluence`, `slack`, `teams`. All secrets routed through `${input:…}` prompts so the file stays safe to commit. New `.vscode/MCP.md` is a per-server setup guide covering prereqs (`uv`, `node`), VS Code quick start, Claude Code / Claude Desktop equivalents, credential sourcing, and troubleshooting. |
| **0.9.0** | **Workspace topology + Five Whys discipline + install-model rework.** New `workspace.role` config (`monorepo` default, `prod`, `tests`) plus optional `companion_repo` (`path` / `remote` / `fetch: mcp \| local_path \| manual_paste`) wires split-repo teams whose tests live separate from prod code. Topology contract centralized in `qi-foundation.instructions.md` § Workspace topology with fetch fallback (MCP → local path → manual paste) and UNGRADED degradation (`reason: companion_repo_unset \| companion_repo_unreachable`) per the v0.2 signal-schema `partial_signal_mode` contract — never fabricated. Seven cross-repo skills (`risk-assess-pr`, `check-merge`, `release-confidence`, `code-review`, `check-test-coverage`, `generate-traceability-matrix`, `analyze-escaped-defect`) carry short pointers to the rule. Five Whys discipline added to `debug-ui-tests`, `analyze-flaky-test`, and `analyze-escaped-defect`: mandatory evidence-per-link chains, `max_depth` runaway guard, user-gated Anti-Patterns appendix. Install model reworked into **two paths**: Path A pack-as-workspace (`install.sh` / `install.ps1` at the cloned pack root) and Path B codebase install (`/assert-iq-bootstrap` or `bash scripts/bootstrap.sh --mode=trial`); the `.claude-plugin/` directory is removed. Both installers gain `--uninstall` with `--user` / `--yes` / `--dry-run`; bootstrap snapshots pre-existing user files to `<file>.assert-iq.pre-install` for byte-for-byte restore. Four new workspace surfaces (`.github/skills/`, `.github/agents/`, `.claude/agents/`, `.claude/skills` symlink with copy fallback on Windows without Developer Mode) bring the total to twelve. Skill count 23 → 24. Version centralized in a new `VERSION` file. Backward-compatible: single-repo users see zero behavioral change. |
| **1.0.0** | **First stable release.** API-stable surface: bootstrap CLI flags, manifest schema, skill names, and workspace surface layout will not change incompatibly without a major-version bump. Adds the `assert-iq-bootstrap` skill (the `/assert-iq-bootstrap` slash command itself), the `generate-hotspot-map` skill (churn × complexity × defect-density audit producing a Hotspot Risk Index registry), HTML snapshots of the README family for offline / static-host distribution, and the `e2e-bootstrap.sh` regression suite (23 cases covering pod / solo / portable presets, committed / trial / ask modes, skills-scope variants, idempotent reinstall, conflict + backup + restore, dry-run, invalid-arg rejection — all isolated under mktemp `$HOME` so it's safe to run on a developer machine). |
| **1.1.0** | **Hindsight Hooks: scope-aware install + double-fire dedup.** New `--hooks=user` / `-Hooks user` install mode in `scripts/bootstrap.{sh,ps1}` lets power users install hooks once at `~/.agents/hooks/` and have them fire across every VS Code workspace; the per-workspace install path is unchanged and remains the default. New `si_dedup_or_exit` / `Invoke-SiDedupOrExit` helpers suppress duplicate fires of the same `(session_id, event)` pair within `SKILL_IMPROVE_DEDUP_WINDOW_SECONDS` (default 5; set to 0 to disable) via atomic `set -o noclobber` (bash) / `FileMode.CreateNew` (PowerShell) marker claims under `hooks/state/.dedup-<sha256>`; wired into SessionStart and Stop only — PostToolUse legitimately fires once per tool call. Hook scripts now resolve `SKILL_IMPROVE_ROOT` from the environment (set by the wrapper template) so workspace and user installs route to their own roots deterministically. Janitor sweep prunes stale `.dedup-*` markers older than 1 hour. New `e2e-hooks.sh` suite (15 cases) verifies workspace + user layouts, SessionStart routing, PostToolUse telemetry + detect, Stop log entry, `config.enabled=false` and `SKILL_IMPROVE_DISABLED=1` no-ops, dedup behavior, and user uninstall. |
| **1.1.1** | **Patch.** Hides Hindsight Hooks runtime artifacts from git so workspaces don't see hook state files appear as untracked changes. Per-directory `.gitignore` files now ship inside `hooks/state/`, `hooks/logs/`, and `hooks/sessions/` at the pack source; `copy_tree()` already copies dotfiles, so the rules propagate verbatim into every workspace install — no mutation of the workspace `.gitignore` required (consistent with the design rule that bootstrap never touches the user's `.gitignore`). Untracks the previously-committed runtime seeds `hooks/logs/skill-improve.log` and `hooks/state/.last-janitor`; structural seeds `dismissed-lessons.json` and `edit-frequency.json` remain tracked. Also enables GitHub Pages at `https://fromjariuswithsparq.github.io/assert-iq-agent-pack/` with `README.assert-iq.html` as the landing page, and refreshes stale current-version banners across the README family. |

Tag releases. Keep a CHANGELOG in `.assert-iq/CHANGELOG.md`.

---

## Ownership

| Role | Responsibility |
|---|---|
| Pack technical owner/QI Sponsor | Jarius Hayes |
| Assert.IQ commercial owner | Intelligence Studio leadership |
| Pilot account leads | Embedded QE pod leads |
| Governance review | QI sponsor + Sparq InfoSec |
| Versioning and release | Jarius Hayes |

---

## Where to learn more

- Quality Intelligence Kit (Sparq internal) — the operating model behind every skill in this pack
- QI Diagnostic Guide — how to set the right maturity tier (See Jarius)
- QI Facilitator Guide and Playbook — how to talk about this pack with clients without making it the headline (Sparq internal)
- Assert.IQ and the Quality Intelligence Vision — positioning between the operating model and the commercial offering (See Jarius)
