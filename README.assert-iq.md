# Assert.IQ Agent Pack

> The capability layer of Assert.IQ. Quality Intelligence-grounded skills,
> instructions, modes, and tools that turn GitHub Copilot Chat **and**
> Claude Code into a QI-aware delivery partner inside the IDE.

**Version**: v0.5.0
**Status**: Internal Sparq asset — Intelligence Studio
**Owner**: QE Competency Council

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
- 22 skills cover the QE lifecycle: planning, development, review, execution,
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

---

## The four layers of the pack

```
LAYER          PRIMITIVE                              ROLE
─────────      ───────────────────────────            ──────────────────────────
Foundation     copilot-instructions.md                Always-on QI guidance
               instructions/*.instructions.md         (loaded automatically)

Skills         prompts/*.prompt.md                    Invokable workflows
                                                      (called via /skill-name)

Modes          agents/Assert-IQ.agent.md             Default front-door agent
               agents/Assert-IQ-PLAN.agent.md        Read-only planning sibling

Tools          .vscode/mcp.json                       External integrations
                                                      (ADO, Jira, GitHub)
```

---

## Quick start

### 1. Drop the pack into the client repo

Copy these directories into the repo root:
- `MANIFEST.md` (root-level inventory of all files in the pack)
- `README.assert-iq.md`
- `.github/copilot-instructions.md`
- `.github/instructions/`
- `.github/skills/`               ← each skill is a folder with a `SKILL.md`
- `.github/agents/`              ← `Assert-IQ.agent.md` + `Assert-IQ-PLAN.agent.md`
- `.vscode/mcp.json`
- `.vscode/settings.json`        ← wires `.github/skills/` into Copilot prompt-file loading
- `.assert-iq/`
- `tests/_qi/` (if not already present)

> **Note on hidden directories.** `.github/`, `.vscode/`, and `.assert-iq/` are dot-prefixed
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
| Add a domain skill (e.g., performance, accessibility) | New file in `.github/prompts/` |
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
4. Update this README's skill registry and the root `MANIFEST.md`.

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
`.github/prompts/risk-assess-pr.prompt.md`. Each layer is independently
tunable.

**The router sends too many ACs to manual.**
Tighten `routing.automation_threshold` in `config.yaml`, or adjust the
classification heuristics in `generate-tests-from-ac.prompt.md`.

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
| **0.5.0** | **Dual-target support: works with both GitHub Copilot Chat and Claude Code from the same pack folder. Added `CLAUDE.md`, `AGENTS.md`, `.claude/agents/qi-advisor.md`, `.claude/settings.json`, `.claude/skills/` symlink, `install.sh` / `install.ps1`. Added "When this applies" prose to all five instruction files. Hooks integrated (`.github/hooks/`).** |

Tag releases. Keep a CHANGELOG in `.assert-iq/CHANGELOG.md`.

---

## Ownership

| Role | Responsibility |
|---|---|
| Pack technical owner | Jarius Hayes |
| Assert.IQ commercial owner | Intelligence Studio leadership |
| Pilot account leads | Embedded QE pod leads |
| Governance review | QI sponsor + Sparq InfoSec |
| Versioning and release | QE Competency Council |

---

## Where to learn more

- Quality Intelligence Kit (Sparq internal) — the operating model behind every skill in this pack
- QI Diagnostic Guide — how to set the right maturity tier
- QI Facilitator Guide and Playbook — how to talk about this pack with clients without making it the headline
- Assert.IQ and the Quality Intelligence Vision — positioning between the operating model and the commercial offering
