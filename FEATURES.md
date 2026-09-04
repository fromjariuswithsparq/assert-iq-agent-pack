# Assert.IQ — The Feature Guide

> Eight features. What each one is, how to use it, when to reach for it, and why it earns its place.

**v2.1.2** · [Full documentation →](README.assert-iq.md) · [← Back to the README](README.md)

---

## How to read this guide

Every feature below is written for two people at once: an engineer in their first year who needs the exact command, and a stakeholder who needs to know why any of it matters. Neither has to skip anything.

Each feature answers the same four questions, in the same order:

| | |
|---|---|
| **What it is** | Plain language. No prior Assert.IQ knowledge assumed. |
| **How to use it** | The actual commands, files, and steps. Copy-paste ready. |
| **When to use it** | The moments that should make you reach for it — and the moments that shouldn't. |
| **Why it matters** | What you get that you didn't have before. |

Every heading has its own link. Copy the URL from any feature or skill and it will drop the next person exactly where you were reading.

---

### Start here — which feature do I need?

| If you're trying to… | Go to |
|---|---|
| Write tests, review a PR, or produce any QE artifact | [The 31 Skills](#skills) |
| Get a deep, multi-angle read on a risky change | [Multi-Agent Orchestration](#multi-agent-orchestration) |
| Show leadership what quality work is worth in dollars | [Business Impact Dashboards](#business-impact-dashboards) |
| Define what "good" means before you generate anything | [Oracle Layer](#oracle-layer) |
| Stop the tool from doing more than your team is ready for | [Maturity-Aware Behavior](#maturity-aware) |
| Let the agent see your real PRs, tickets, and production errors | [20 MCP Servers](#mcp-servers) |
| Stop re-explaining your codebase every session | [Dreaming](#dreaming) |
| Prove your ship/hold calls were actually right | [Decision Confidence Calibration](#decision-confidence-calibration) |

---

## The eight words you'll see everywhere

Read these once and the rest of the guide reads easily.

| Word | What it means here |
|---|---|
| **Signal** | Evidence good enough to make a decision on. A number that just tells you what happened is a *metric*; a number you'd stake a release on is a *signal*. |
| **The four layers** | The four questions Assert.IQ asks about every change: what changed (**Change risk**), what tests protect it (**Protection strength**), whether those tests can be believed (**Signal trustworthiness**), and what real-world outcomes say (**Outcome evidence**). |
| **Decision Confidence** | The synthesis of those four layers into one answer: ship, mitigate, or hold. Never a single percentage. |
| **Verdict** | One recorded decision — a risk band (green / amber / red), a score, and the reasoning behind it. Saved, so it can be checked later. |
| **Escape** | A defect that reached production. The thing every other signal exists to prevent. |
| **Flake** | A test that passes and fails without the code changing. Flakes destroy trust in your test suite faster than missing tests do. |
| **Traceability** | A visible link from a requirement to the code that implements it to the test that proves it. |
| **Maturity tier** | Your team's honest self-assessment — `early`, `mid`, or `higher`. It controls how much autonomy Assert.IQ takes. |

---

<a id="skills"></a>

## The 31 Skills

> **In one sentence:** thirty-one slash commands that turn "I need a test plan / a risk read / a bug report" into a finished, standards-conforming artifact in under a minute.

### What it is

A skill is a pre-written expert procedure the agent follows on request. You type `/generate-automated-unit-test`; the agent reads your config, your framework, your acceptance criteria, and your existing test conventions, then produces a test that looks like your team wrote it.

The difference between a skill and just asking the chat window for a test is repeatability. The chat window gives you whatever it feels like today. A skill gives you the same structure, the same required headers, and the same traceability every single time, for every person on the team.

Skills live in `.github/skills/` and are mirrored to `.claude/skills/`, so the same 31 commands work in **GitHub Copilot Chat** and **Claude Code**. One pack, both tools.

### How to use it

In Copilot Chat, select the `Assert-IQ` agent. In Claude Code, just type. Then:

```
/risk-assess-pr
```

That's the whole interface. Some skills take an argument:

```
/generate-automated-unit-test src/checkout/totals.ts
/grade-with-rubric tests/unit/login.test.ts test-unit-v1.0
```

If you're not sure which one you want, describe the problem in plain language — "this test keeps failing randomly" — and the lead agent routes you to the right skill.

### When to use it

Any time you're about to produce a QE artifact by hand. If your next hour is going to be spent writing test cases, filing a bug, assembling a coverage story, or drafting a release readiness note, there is a skill for it.

**When not to:** skills draft, they don't decide. Everything a skill produces is reviewed by a human before it merges. That rule is not negotiable and it is enforced in the pack's own instructions.

### Why it matters

Consistency is the whole point. Thirty-one skills mean a junior engineer's test plan has the same structure as a principal's, a bug report from any team member has the same reproduction quality, and traceability headers appear on every generated artifact instead of the ones somebody remembered.

You also stop paying the "blank page" tax. The expensive part of quality work has never been the typing — it's deciding what to write. The skills carry that decision structure with them.

---

### The 31 skills, one by one

Each skill below has its own link. Grouped by where they land in the delivery lifecycle.

**Plan**

---

### `/review-acceptance-criteria`

- **What it is** — A testability review of your acceptance criteria before anyone writes a test against them.
- **How to use it** — `/review-acceptance-criteria` with a work item ID or pasted ACs. It returns each AC marked testable / ambiguous / untestable, with a rewrite suggestion for the weak ones.
- **When to use it** — Refinement and sprint planning, before the story is accepted into the sprint. The cheapest possible moment.
- **Why it matters** — An untestable AC produces an untestable feature, and you find out three weeks later during UAT. This catches it in ninety seconds while the AC is still cheap to change.

---

### `/generate-test-plan`

- **What it is** — A one-page operating test plan for a feature or release, scaled to the actual scope rather than a template you'll never read again.
- **How to use it** — `/generate-test-plan` with the epic, feature, or release scope. You get risk-weighted priorities and exit criteria written as signals, not vibes.
- **When to use it** — Kicking off any feature big enough that "we'll figure out testing as we go" would be a lie.
- **Why it matters** — Test plans usually fail because they're written to satisfy a process, not to be used. This one fits on a page and its exit criteria are checkable.

---

### `/generate-tests-from-ac`

- **What it is** — A router. It reads each acceptance criterion and decides whether it should become an automated test, a scripted manual case, or an exploratory charter — then dispatches to the right generator.
- **How to use it** — `/generate-tests-from-ac` with a work item ID or pasted ACs.
- **When to use it** — When a story is accepted and you need full coverage across every AC, not just the ones that are easy to automate.
- **Why it matters** — Teams over-automate the deterministic and under-test the subjective. This forces an explicit routing decision per AC, and records *why* anything went to manual.

---

**Develop**

---

### `/generate-automated-unit-test`

- **What it is** — Unit tests for one function, class, or module: happy path first, then negative paths, then edge cases.
- **How to use it** — `/generate-automated-unit-test <path>`. It reads your framework from `.assert-iq/config.yaml` and conforms to it rather than importing a new one.
- **When to use it** — Immediately after writing a unit of logic, and when you're hardening a module that a hotspot map flagged.
- **Why it matters** — It writes the tests you'd have written on a good day, including the traceability header and the review-required flag you'd have forgotten on a busy one.

---

### `/generate-automated-api-test`

- **What it is** — API tests built from a contract or work item — schema validation, error envelopes, and auth scenarios, not just a 200-OK check.
- **How to use it** — `/generate-automated-api-test` with the endpoint, spec, or work item.
- **When to use it** — New or changed endpoints, contract changes, and any integration another team depends on.
- **Why it matters** — Most API suites test the happy path and nothing else. The failures that reach production are almost always in the error envelope and the auth boundary.

---

### `/generate-automated-ui-test`

- **What it is** — UI tests using the Page Object Model, stable selectors, and explicit waits.
- **How to use it** — `/generate-automated-ui-test` with the workflow or work item. It reuses your existing page objects instead of inventing a parallel pattern.
- **When to use it** — Critical user journeys — the flows where a break is a revenue event, not a papercut.
- **Why it matters** — Hard waits and brittle selectors are the two things that turn a UI suite into an ignored, red-all-the-time wall. Neither one gets generated here.

---

### `/generate-manual-test-case`

- **What it is** — Scripted manual test cases formatted for the tool you already use — ADO Test Plans, Xray, TestRail, or markdown.
- **How to use it** — `/generate-manual-test-case` with the ACs. Every case carries a mandatory `routed-to-manual-because` field.
- **When to use it** — UAT scripts, accessibility checks, and anything genuinely subjective where a human judgment is the point.
- **Why it matters** — That mandatory field is the guardrail. Manual suites grow quietly until they're unmaintainable; forcing a stated reason keeps the growth honest.

---

### `/generate-exploratory-charter`

- **What it is** — A time-boxed exploratory testing mission: what to learn, which risks it targets, which oracles to judge against.
- **How to use it** — `/generate-exploratory-charter` with the area and risk. You get a charter — a mission, deliberately not a script.
- **When to use it** — Novel areas, third-party integrations, and anywhere your instinct says "something's off here" but you can't name it yet.
- **Why it matters** — Scripted tests only find the bugs you already thought of. Charters are how you find the ones you didn't — and this makes that session structured enough to report on.

---

### `/generate-test-data`

- **What it is** — Deterministic, PII-safe test data built through your project's existing factory pattern.
- **How to use it** — `/generate-test-data` with the scenario.
- **When to use it** — Any test needing more than trivial input, and whenever a suite is flaking because data drifted underneath it.
- **Why it matters** — Data drift is one of the top causes of flaky suites, and hand-rolled fixtures are one of the top causes of PII landing somewhere it shouldn't. This closes both.

---

**Code review and pull requests**

---

### `/code-review`

- **What it is** — A code review through the four-layer QI lens, plus a pre-flight pass for the anti-patterns human reviewers catch and AI reviews usually miss.
- **How to use it** — `/code-review` on the current diff or a PR. In PR mode it reads existing comment threads and commit history first, then checks claimed fixes against what was actually committed.
- **When to use it** — Before requesting review on your own work, and as a second pair of eyes on someone else's.
- **Why it matters** — It reviews the *change* in context of the tests protecting it, rather than reading a diff in isolation and commenting on style.

---

### `/check-test-coverage`

- **What it is** — Coverage analysis weighted by risk. Not "what percent," but "is the risky part covered."
- **How to use it** — `/check-test-coverage` on the changed surfaces.
- **When to use it** — Before merge, and whenever someone quotes a coverage percentage in a meeting as if it settles something.
- **Why it matters** — Eighty percent coverage means nothing if the uncovered twenty percent is your payment path. This tells you where the gap actually is.

---

### `/check-merge`

- **What it is** — The pre-merge gate. It aggregates every available signal into one verdict: merge, hold, or discuss.
- **How to use it** — `/check-merge` on the PR. Any layer it can't assess is reported **UNGRADED** with a stated reason — never guessed at.
- **When to use it** — The last checkpoint before the merge button.
- **Why it matters** — It replaces "CI is green, ship it" with a defensible answer that names what it doesn't know. That honesty is what makes the green ones trustworthy.

---

### `/new-pull-request`

- **What it is** — A PR opened with a QI-aware description: risk band, AC linkage, traceability, and specific reviewer guidance.
- **How to use it** — `/new-pull-request` when your branch is ready.
- **When to use it** — Every PR you open.
- **Why it matters** — Reviewers give better reviews when they're told where to look. This turns your PR description from a changelog into a set of directions.

---

### `/review-test-quality`

- **What it is** — A design review of tests that already exist — independence, determinism, brittle patterns, missing traceability.
- **How to use it** — `/review-test-quality` on a test file or directory.
- **When to use it** — Inheriting a suite, onboarding to a codebase, or after a sprint of fast test-writing that nobody reviewed closely.
- **Why it matters** — A bad test is worse than no test: it costs maintenance and buys false confidence. This finds the ones costing you both.

---

**Execute and debug**

---

### `/debug-ui-tests`

- **What it is** — A diagnosis of a failing UI test that answers the only question that matters: is this flaky, brittle, broken, or a real regression?
- **How to use it** — `/debug-ui-tests` with the failing test and its output.
- **When to use it** — The moment a UI test goes red and you're tempted to just re-run it.
- **Why it matters** — Those four causes need four different responses, and guessing wrong is how a real regression gets re-run until it passes and ships.

---

### `/analyze-flaky-test`

- **What it is** — Pattern analysis across historical run data to find the *systemic* cause of flake, rather than diagnosing one failure.
- **How to use it** — `/analyze-flaky-test` with the test or suite. It reads run history, not just the latest failure.
- **When to use it** — When the same test has failed intermittently more than twice, or when the team has started ignoring red.
- **Why it matters** — Flakes are usually one shared root cause wearing twelve different test names. Fixing the cause fixes all twelve.

---

### `/agentic-heal`

- **What it is** — Autonomous diagnosis, repair, and re-execution of failing tests within a bounded number of retries.
- **How to use it** — `/agentic-heal` on the failing test. **Requires `mid` maturity or higher.** At `mid` it suggests and never commits; at `higher` it can heal within your configured retry bound. Every heal records the failure signature and the fix rationale.
- **When to use it** — Breakage where the fix is mechanical — a moved selector, a renamed field — and the intent of the test is unchanged.
- **Why it matters** — It clears the mechanical failures so your attention goes to the real ones. The recorded rationale is what keeps this from becoming "the robot silently made the tests pass."

---

**Decision**

---

### `/risk-assess-pr`

- **What it is** — A score for a pull request across all four QI layers, posted back as a structured comment.
- **How to use it** — `/risk-assess-pr` on the PR. The verdict is recorded to `.assert-iq/verdicts/` with its band, score, per-layer states, assumptions, and a hash of the memory used to produce it.
- **When to use it** — Any PR touching a risky surface, and every PR once the team is used to the rhythm.
- **Why it matters** — It converts "this feels risky" into four named layers with evidence — and because it's recorded, you can check months later whether the call was right. See [Decision Confidence Calibration](#decision-confidence-calibration).

---

### `/release-confidence`

- **What it is** — Signals aggregated across an entire upcoming release into a go / no-go report.
- **How to use it** — `/release-confidence` with the release scope. **Mid maturity or higher.** Recorded like any other verdict.
- **When to use it** — Release readiness reviews, go/no-go calls, and any conversation where someone is about to ask "are we good to ship?"
- **Why it matters** — It gives that meeting a shared evidence base instead of a room full of competing intuitions and one loud opinion.

---

**Learn**

---

### `/dream`

- **What it is** — The memory consolidation pass. It reads recent session logs, resolves contradictions, prunes stale entries, and rewrites the memory store.
- **How to use it** — `/dream`. Full detail in [Dreaming](#dreaming).
- **When to use it** — Every week or two, and right after a refactor that invalidated things the agent believes.
- **Why it matters** — Memory that only ever grows becomes noise. This is the process that keeps it decision-grade.

---

### `/analyze-escaped-defect`

- **What it is** — Post-incident analysis that names *which signal layer should have caught this* — and links the escape back to the verdict that let it through.
- **How to use it** — `/analyze-escaped-defect` with the defect. It queries the verdict archive to find the original assessment.
- **When to use it** — Every production escape. Every single one.
- **Why it matters** — This is the feedback loop the whole system runs on. Without it you're triaging symptoms; with it, each escape permanently improves the layer that missed it.

---

### `/generate-bug-report`

- **What it is** — A failure converted into a tracker-ready defect: duplicate-checked, severity-justified, PII-stripped.
- **How to use it** — `/generate-bug-report` with the failure output.
- **When to use it** — Any time you're about to file a bug by hand.
- **Why it matters** — Bad bug reports cost the person who receives them an hour of clarification. Severity justification alone changes how triage meetings go.

---

**Cross-cutting**

---

### `/generate-traceability-matrix`

- **What it is** — A requirement ↔ code ↔ test matrix built from the `qi-trace` headers in your codebase, surfacing orphan tests, untraceable code, and uncovered ACs.
- **How to use it** — `/generate-traceability-matrix`.
- **When to use it** — Audit preparation, compliance reviews, and any time someone asks "how do we know this requirement is tested?"
- **Why it matters** — It answers an auditor's question with a document instead of a promise. The orphan-test column is usually the surprise: tests nobody can connect to a requirement.

---

### `/generate-hotspot-map`

- **What it is** — An audit of code volatility, structural complexity, and defect density, producing a ranked registry of your most fragile modules.
- **How to use it** — `/generate-hotspot-map`.
- **When to use it** — Sprint zero, quarterly planning, and whenever you have testing capacity and no agreement on where to spend it.
- **Why it matters** — Files that change constantly, are structurally complex, and have a defect history are where your next escape is coming from. This ranks them so investment goes to evidence, not to whoever argued hardest.

---

### `/eval-optimizer`

- **What it is** — An evaluate-and-improve loop for any AI instruction artifact — a skill, a system prompt, a set of custom instructions.
- **How to use it** — `/eval-optimizer` with the artifact. You get an optimized version plus a report on what changed and why.
- **When to use it** — When you've written or customized a skill and want to know whether it actually performs.
- **Why it matters** — Prompts and skills are code that nobody tests. This is the test.

---

**Setup and meta**

---

### `/assert-iq-bootstrap`

- **What it is** — The guided installer. It walks you through what goes into the workspace, what goes user-global, and what gets skipped, then runs the right script for your OS.
- **How to use it** — `/assert-iq-bootstrap`, or run `scripts/bootstrap.sh` / `scripts\bootstrap.ps1` directly. Use `--mode=trial` to keep everything local and invisible to your teammates.
- **When to use it** — Installing the pack into a repository.
- **Why it matters** — Trial mode is why you can evaluate this without a team decision, a PR, or a rollback plan. It never touches your `.gitignore`, and uninstall restores what it replaced.

---

### `/assert-iq-tailor`

- **What it is** — The customization pass. It discovers your stack once, then fills in `config.yaml`, `governance.md`, `maturity-profile.md`, the instruction files, and MCP wiring — in dependency order, with a human review gate at each step.
- **How to use it** — `/assert-iq-tailor` right after installing.
- **When to use it** — Immediately after install. This is the step that turns a generic pack into *your* pack.
- **Why it matters** — A pack full of `<PLACEHOLDER>` values produces generic output. Fifteen minutes here is the difference between advice about software and advice about your software.

---

**Oracle and verification**

---

### `/define-quality-rubric`

- **What it is** — A guided interview that turns your definition of "good" into a versioned, machine-readable acceptance contract.
- **How to use it** — `/define-quality-rubric`. Output lands in `.assert-iq/oracles/rubrics/<rubric_id>.json`, ready to commit. Available at **all maturity tiers**.
- **When to use it** — Before you start generating a new class of artifact at volume.
- **Why it matters** — See [Oracle Layer](#oracle-layer). Writing down what "good" means is the part everyone skips, and it's the part that makes every later judgment defensible.

---

### `/grade-with-rubric`

- **What it is** — Independent grading of an artifact against a rubric, performed by a grader with no visibility into how the artifact was produced.
- **How to use it** — `/grade-with-rubric <artifact_path> <rubric_id>`. Verdict lands in `.assert-iq/oracles/outcomes/`. Advisory at `early`, an optional gate at `mid`, able to block at `higher`.
- **When to use it** — On generated tests before merge, and on any artifact where "looks fine to me" isn't a good enough standard.
- **Why it matters** — The grader can't rationalize, because it never saw the reasoning. Every verdict cites line numbers and says what would change it.

---

**Business impact**

---

### `/measure-qi-impact`

- **What it is** — Your QI verdicts and baseline metrics converted into a quarterly HTML dashboard aimed at an executive audience.
- **How to use it** — `/measure-qi-impact`. Full detail in [Business Impact Dashboards](#business-impact-dashboards).
- **When to use it** — Quarterly business reviews, renewal conversations, and any budget discussion about quality investment.
- **Why it matters** — Engineering value that never gets translated into business language gets cut in the next budget cycle.

---

### `/calibration-report`

- **What it is** — Longitudinal accuracy measurement of your verdicts: Brier score, confusion matrix, per-layer fidelity, and drift — read against real escapes.
- **How to use it** — `/calibration-report`. Full detail in [Decision Confidence Calibration](#decision-confidence-calibration).
- **When to use it** — Quarterly, alongside `/measure-qi-impact`, and any time the team's trust in the verdicts starts to wobble.
- **Why it matters** — It answers the only question that ultimately matters about a prediction system: *are we actually right?*

---

<a id="multi-agent-orchestration"></a>

## Multi-Agent Orchestration

> **In one sentence:** instead of one agent forming one opinion, eight specialists analyze your change independently and a lead agent synthesizes their findings into a single decision.

### What it is

When you ask a single AI a complex question, everything it notices early colors everything it notices later. Decide in the first paragraph that a change looks safe, and the rest of the analysis quietly goes looking for agreement.

Multi-agent orchestration breaks that. Eight specialists each get their own isolated context — none of them sees the others' reasoning — and each returns structured JSON. A lead agent then synthesizes those independent findings into one narrative and one decision.

**Four run in parallel, at the same time:**

| Specialist | What it examines |
|---|---|
| **risk-scorer** | What changed and how far it reaches (Change + Protection layers) |
| **coverage-analyst** | Where the protection gaps actually are |
| **flake-adjudicator** | Whether a failure is flaky, brittle, or a genuine regression |
| **hotspot-analyzer** | Which modules are fragile — churn, complexity, and defect history |

**Four run after, in sequence:**

| Specialist | What it examines |
|---|---|
| **oracle-grader** | Artifact quality against your rubrics |
| **calibration-specialist** | Whether verdicts like this one have been accurate historically |
| **memory-curator** | Whether the memory informing this decision is healthy |
| **traceability-auditor** | Whether requirement, code, and test are actually linked |

Two lead agents drive them: `Assert-IQ` executes, and `Assert-IQ-PLAN` is a read-only sibling that plans first and waits for your approval before anything is done.

### How to use it

You don't invoke the specialists directly. You invoke a decision skill and the orchestration happens underneath:

```
/risk-assess-pr
/check-merge
/release-confidence
```

In Claude Code you can also address a lead agent by name and describe the problem. Use `Assert-IQ-PLAN` when the task is large, risky, or spans many files and you want to see the plan before anything moves.

Every run leaves an audit trail in `.assert-iq/agent-runs/` — each specialist's raw JSON, preserved. When you disagree with a verdict, that's where you go to find out which specialist you disagree with.

### When to use it

- Any pull request touching a critical path, a shared service, or a surface with an escape history
- Release go/no-go decisions
- Post-incident analysis, where you need to know which layer failed and not just what broke

**When not to:** a typo fix, a doc change, or a dependency bump doesn't need eight specialists. The lead agent routes simple questions to a single skill, and that's the correct outcome.

### Why it matters

**Isolation buys you real independence.** Four analysts who can't see each other's work produce four genuinely different reads. Agreement between them means something. Disagreement is a signal in itself — and it's exactly the disagreement a single-context analysis would have smoothed over.

**Parallelism buys you speed.** Four specialists running concurrently means depth doesn't cost you the afternoon.

**The audit trail buys you trust.** "The agent said it was risky" is not a reason. "The coverage analyst found no test on the changed branch, and the hotspot analyzer ranks this module third by defect density" is a reason — and it's still on disk next quarter.

---

<a id="business-impact-dashboards"></a>

## Business Impact Dashboards

> **In one sentence:** the `/measure-qi-impact` skill turns your quality data into a dashboard a VP will actually read — escape reduction, hours reclaimed, cycle time, and dollars.

### What it is

Quality teams have always had a translation problem. The work is real, the improvement is real, and none of it survives contact with a budget meeting — because "we reduced flake rate by 40%" doesn't map to anything a finance conversation can hold.

This skill does the translation. It reads your recorded verdicts, coverage data, and flake records, compares them against a baseline you captured before Assert.IQ, and produces four numbers in business language:

| Metric | The question it answers |
|---|---|
| **Escape Reduction** | How many production incidents didn't happen — and what they would have cost |
| **Triage Hours Reclaimed** | How many engineer-hours went back to building instead of investigating |
| **Release Cycle Acceleration** | How many days faster a change gets from PR to production |
| **Total Economic Value** | Those savings, added up, in dollars |

You get a print-friendly HTML dashboard and a JSON report for trending.

### How to use it

**One-time setup.** In `.assert-iq/config.yaml`, set your cost assumptions:

```yaml
business_metrics:
  enabled: true
  escape_incident_cost: 50000      # your average cost per production incident
  engineer_burden_rate: 85         # $/hour, all-in
  reporting_period: quarterly
```

Then capture where you're starting from in `.assert-iq/business-metrics/baseline.json` — escape rate, triage hours, cycle time. **Do this before you've improved anything.** A baseline captured after six months of gains understates every result you're about to report.

**Then, each quarter:**

```
/measure-qi-impact
```

Reports land in `.assert-iq/business-metrics/reports/`.

A quarter's output reads like this:

```
33% escape reduction (4 fewer incidents) → $200K cost avoidance
55 engineer-hours reclaimed             → $4,675 burden cost savings
4 days cycle acceleration               → velocity improvement
Total quarterly ROI: $204,675
```

### When to use it

- Quarterly business reviews and leadership updates
- Renewal, budget, and headcount conversations
- Any moment where someone asks what the quality investment is returning

**When not to:** don't run it in week two. There's no signal in a two-week window, and a dashboard built on eleven data points invites a challenge you'll lose. Give it a quarter.

### Why it matters

**Because the numbers are yours.** Every figure traces back to your recorded verdicts and your baseline, using cost assumptions you set. When someone challenges the ROI, you open the verdict archive.

**Because the alternative is being invisible.** Quality work that prevents incidents is, by definition, work whose output is an absence. Absences don't get noticed and don't get funded. This makes the absence countable.

**Because "we saved tokens" has never persuaded anyone.** "$200,000 in prevented incidents and 55 engineer-hours back" is a sentence a VP can repeat to their own leadership. That's the bar.

---

<a id="oracle-layer"></a>

## Oracle Layer

> **In one sentence:** write down what "good" means *first*, as a versioned contract, then have an independent grader judge artifacts against it — with evidence.

### What it is

Here's the gap at the center of AI-assisted testing: **generation without specification.** A tool generates a test. Is it a good test? The usual answer is that it looks fine. That isn't a standard; it's a mood.

The Oracle Layer inverts the order. Before you generate at volume, you author a **rubric** — a written acceptance contract naming three to five things that make an artifact good, with objective definitions of PASS, CONDITIONAL, and FAIL for each.

Then an **isolated grader** evaluates artifacts against that rubric. The grader has no access to how the artifact was made, no access to previous verdicts, and no ability to rationalize. It sees the artifact and the rubric. Nothing else.

Rubrics are **immutable**. You never edit `test-unit-v1.0`; you create `test-unit-v1.1`. Old versions stay in git, so every past verdict remains interpretable.

### How to use it

**Author a rubric:**

```
/define-quality-rubric
```

A guided interview walks you through dimensions, weights, and level definitions, then saves a versioned JSON spec to `.assert-iq/oracles/rubrics/`. Available at every maturity tier.

**Grade an artifact:**

```
/grade-with-rubric tests/unit/login.test.ts test-unit-v1.0
```

A verdict looks like this:

```
Verdict: CONDITIONAL (0.92 / 1.0)
  ✓ PASS: independence, determinism, focus
  ⚠ CONDITIONAL: assertion clarity — line 25 is a bare assert()
  → Add a message to line 25 and this becomes PASS
```

Every dimension cites specific lines, explains why that level was chosen, and says what would change it. Verdicts append to a history file, so you can watch an artifact improve across versions.

**Wire it into your gates.** Oracle verdicts feed the Outcome layer of `/check-merge` and `/release-confidence`, weighted by maturity: **early 0%** (advisory only), **mid 20%** (an optional gate), **higher 50%** (co-decisive).

Start with `ORACLE_QUICK_START.md`.

### When to use it

- Before generating a new class of artifact at volume — that's the moment the contract is worth the most
- Grading generated tests before merge
- Onboarding, where "what does good look like here?" currently has no written answer
- Regulated work, where a subjective judgment is not an acceptable artifact

**When not to:** don't author a rubric for a one-off. Rubrics pay back through repetition.

### Why it matters

**Rubric authorship is the defensible skill.** Anyone can generate a test. Knowing what makes a test good in *your* domain is expertise, and this is where that expertise gets written down instead of walking out with whoever had it.

**Independent grading can't flatter itself.** A grader that saw the generator's reasoning would inherit its blind spots. This one can't.

**Evidence over opinion.** "Line 25 is a bare assert, and here's what would fix it" is actionable. "Looks good" is not.

**Immutability preserves history.** A verdict from six months ago still means what it meant, because the rubric it was graded against hasn't moved.

---

<a id="maturity-aware"></a>

## Maturity-Aware Behavior

> **In one sentence:** one config field scales the entire pack from cautious to autonomous, so it never does more than your team is ready to trust.

### What it is

Most tools ship one behavior and expect you to adapt. A team six months into their first regression suite gets the same autonomy as a team with ten years of signal infrastructure — and it goes badly for one of them.

Assert.IQ reads your maturity tier before it acts, and scales itself:

| Tier | What's active | What's off |
|---|---|---|
| **`early`** | Traceability, manual test generation, rubric authoring, foundation reasoning | Agentic Healing is **disabled**. Oracle verdicts carry **0%** decision weight |
| **`mid`** | Adds automated test generation and risk assessment | Healing is **suggest-only** — it proposes, never commits. Oracle carries **20%** weight |
| **`higher`** | Full pack: autonomous healing within your retry bounds, predictive risk, the full signal pipeline | Nothing gated. Oracle carries **50%** weight |

The tier isn't a settings toggle. It's a statement about what your team can currently verify.

### How to use it

Set it in two places, and keep them in sync:

**`.assert-iq/maturity-profile.md`** — the honest version. It ships with a checklist of indicators across foundation, test signal, and governance. Check the ones that genuinely describe your team today, and count:

- **0–4 checked** → `early`
- **5–8 checked** → `mid`
- **9+ checked** → `higher`

**`.assert-iq/config.yaml`** — the machine-readable version:

```yaml
maturity:
  tier: "early"
  rationale: "New team, building baseline coverage first."
```

Write the rationale in plain language. The agent reads it.

Re-evaluate quarterly, and **promote one tier at a time.** When in doubt, choose the tier below where you think you are.

### When to use it

Set it during setup, before you run anything else — it changes how every other feature behaves. Then revisit it every ninety days, or whenever something material shifts: a new regression suite, a governance change, a team that turned over.

### Why it matters

**It prevents the failure that kills adoption.** A team at `early` given autonomous healing gets tests silently rewritten by a tool nobody yet trusts. One surprise like that and the pack is uninstalled — correctly.

**It makes trust incremental.** Each tier turns on capabilities you've earned the ability to verify. That's a much better story to your leadership than "we turned everything on and hoped."

**It makes the tool honest about itself.** The pack refuses to do things your tier hasn't enabled, even if you ask. Constraints you can rely on are worth more than capabilities you can't.

---

<a id="mcp-servers"></a>

## 20 MCP Servers

> **In one sentence:** twenty pre-configured connections that let the agent read your real pull requests, tickets, production errors, and dashboards instead of guessing.

### What it is

MCP — Model Context Protocol — is the standard way an AI tool connects to another system. Without it, the agent only knows what's in your open files. With it, the agent can read the actual PR, the actual Jira ticket, the actual Sentry error from last Tuesday.

That distinction is the difference between advice and evidence. The fourth QI layer — Outcome evidence — is *unanswerable* without a connection to where outcomes live.

Twenty servers ship pre-configured across eight categories:

| Category | Servers |
|---|---|
| **Code hosts & trackers** | GitHub, Azure DevOps, Atlassian (Jira/Confluence), GitLab, Bitbucket, git |
| **Local & filesystem** | filesystem |
| **Databases** | PostgreSQL, SQLite |
| **Cloud** | AWS |
| **Observability** | Sentry, Grafana, Datadog, Honeycomb |
| **Browser automation** | Playwright, Puppeteer |
| **Knowledge bases** | Notion, Confluence |
| **Communication** | Slack, Microsoft Teams |

### How to use it

Everything is defined in `.vscode/mcp.json`. You enable what you use and delete the rest.

**Credentials are never written to that file.** Each server declares an input placeholder; your editor prompts you the first time and stores the value in your **OS keychain**. The config file stays safe to commit.

Start with three and grow from there:

1. **Your code host** — GitHub, ADO, GitLab, or Bitbucket. This unlocks the Change layer.
2. **Your tracker** — Jira or ADO. This unlocks acceptance criteria and traceability.
3. **Your error monitor** — Sentry, Datadog, Grafana, or Honeycomb. This unlocks Outcome evidence.

Per-server setup, credential scopes, and troubleshooting are in [`.vscode/MCP.md`](.vscode/MCP.md).

### When to use it

Wire this during setup, right after tailoring your config. Add servers as you notice gaps — when a skill reports a layer as **UNGRADED** with a reason like "no telemetry source," it's telling you exactly which server to connect next.

**When not to:** don't connect all twenty. Every connection is a credential to manage and an access surface to justify. Three well-chosen servers beat twenty half-configured ones.

### Why it matters

**It's the difference between a chatbot and an analyst.** An agent that can't see your PRs is pattern-matching on your open buffer. An agent that can read the PR, the linked ticket, and last month's Sentry events on that module is reasoning about your system.

**It's what makes UNGRADED honest.** Assert.IQ never fabricates a missing signal — it names the gap. Connecting a server is how you close one.

**It respects your security posture.** Credentials in the OS keychain, config in git, nothing crossing the IDE or CI boundary. That's a design decision the governance rules enforce, not a convention.

---

<a id="dreaming"></a>

## Dreaming

> **In one sentence:** a markdown memory store the agent consolidates between sessions, so it gets sharper on your codebase over time instead of starting from zero every morning.

### What it is

Every AI session starts amnesiac. You re-explain the same architecture, the same conventions, the same "we don't do it that way here" — every time.

Dreaming fixes that with two loops, borrowed from how memory actually works.

**The waking loop** records a one-line note per session and increments a counter. Cheap, quiet, always running.

**The dream loop** is the `/dream` skill — an offline consolidation pass that reads recent session logs and existing memory, then resolves contradictions, prunes stale entries, removes duplicates, and rewrites the store. Memory improving memory.

The store lives in `.assert-iq/memory/`, as plain markdown you can read and edit. `MEMORY.md` is the index — capped at 200 lines and the only part loaded at session start. Detail lives in `topics/`, pulled in only when relevant.

**Dreaming can only write inside the memory store.** Source, config, and the instruction rule files are read-only to it. Memory never overrides a written rule.

### How to use it

It's on by default. Configure it in `.assert-iq/config.yaml`:

```yaml
dreaming:
  enabled: true
  memory_dir: ".assert-iq/memory"
  index_max_lines: 200
  gate:
    min_hours_between_dreams: 24
    min_sessions_between_dreams: 5
```

Both gates must be met before a dream is suggested — 24 hours *and* 5 sessions.

**To run one:**

```
/dream
```

**Before it changes a single file, run the safety check:**

```bash
python3 .assert-iq/analysis/dream-safety.py pre
```

That one command runs sanity checks (cycles, staleness past 180 days, contradictions, copy-paste vs. synthesis), snapshots the memory to `.assert-iq/dreaming/.snapshots/`, and opens an append-only audit record. Honor its exit code: **0** proceed, **1** stop, **2** stop — never dream blind. On Windows use `python` or `py -3`.

**After consolidating, close the record:**

```bash
python3 .assert-iq/analysis/dream-safety.py post --cycle-id dream-<stamp>
```

Maturity gates it as you'd expect: `early` runs only when you ask, `mid` nudges you at session start, `higher` may fire on its own — and still produces a reviewable diff.

### When to use it

- Every week or two during active development
- Right after a refactor that invalidated things the agent believes
- When the agent starts citing something that used to be true

**When not to:** don't dream after every session. The gates exist because over-consolidation destroys detail. And don't skip the safety check to save thirty seconds — the snapshot it takes is the only thing that makes a bad dream reversible.

### Why it matters

**It compounds.** Month three is materially better than week one, because the agent has accumulated the things you'd otherwise re-explain.

**It's cheap.** Consolidating between sessions rather than hooking every tool call means the token cost stays flat while the knowledge grows.

**It's inspectable.** The memory is markdown in your repo. You can read it, edit it, and diff it. On a committed install, every dream cycle is a reviewable pull-request-shaped change.

**It's safe by construction.** Snapshots, an append-only audit trail, sanity checks before every pass, and a hard rule that memory never outranks an instruction file.

Full detail: `dreaming-readme.html`.

---

<a id="decision-confidence-calibration"></a>

## Decision Confidence Calibration

> **In one sentence:** every ship/hold call is recorded, later checked against what actually escaped to production, and scored — so you know whether your verdicts deserve to be trusted.

### What it is

Every prediction system has one honest question to answer: **are we right?** Most never ask, because nobody wrote down what they predicted.

Assert.IQ writes it down. Every `/risk-assess-pr` and `/release-confidence` verdict is recorded immutably to `.assert-iq/verdicts/archive/YYYY/MM/`:

- A unique verdict ID and band (green / amber / red / ungraded)
- The numeric confidence score
- Per-layer scores for Change, Protection, Trust, and Outcome
- The maturity tier at the time
- **A SHA256 hash of the memory used to produce it**
- The explicit assumptions — and a link to the escape, if one is later found

That memory hash is what makes a verdict **reproducible**. Restore the snapshot, re-run the assessment, get the same verdict. For a SOX or ISO 27001 audit asking "why did you ship PR #4521?", that's a complete answer instead of an anecdote.

When an escape is found, `/analyze-escaped-defect` links it back to the verdict that let it through. Over time that produces real accuracy measurement:

- **Brier score** per band — green verdicts followed by escapes cost you, as they should
- **Confusion matrix** — predicted band against actual outcome, and precision per band
- **Per-layer signal fidelity** — of the verdicts marked WEAK on Protection, how many actually escaped? That tells you which layer is earning its weight
- **Drift detection** — rolling 30-day windows, alarming if the Brier score degrades past your threshold

### How to use it

Enable it in `.assert-iq/config.yaml`:

```yaml
verdicts:
  enabled: true
  track_in_git: false      # set true for regulated clients (SOX, ISO 27001)
  retention_days: 730

calibration:
  enabled: true
  window_days: 90
  drift_alarm_threshold: 0.15
  min_verdicts_for_stats: 10
```

**Read the report:**

```
/calibration-report
```

Or run the analysis directly:

```bash
python3 .assert-iq/analysis/calibration.py --window-days 90 --output report.json
```

**Investigate one verdict:**

```bash
bash .assert-iq/analysis/audit-verdict.sh <verdict_id>
```

That prints the full record plus instructions for reproducing it.

One-line summaries also append to `.assert-iq/verdicts/VERDICTS.md` for human scanning.

### When to use it

- Quarterly, next to `/measure-qi-impact` — impact says what it was worth, calibration says whether to believe it
- After any escape, to close the loop on the verdict that missed it
- After a `/dream`, to confirm memory consolidation didn't degrade accuracy
- Whenever the team starts second-guessing the verdicts. Either the data reassures them or it doesn't, and both answers are useful

**When not to:** below `min_verdicts_for_stats` — ten by default — the statistics are noise. The tool suppresses them for you.

### Why it matters

**For engineers:** it tells you which of the four layers is actually predictive in *your* codebase. If Protection-layer warnings have been right seven times out of eight and Trust-layer warnings have been right twice out of nine, you now know where to spend the next quarter.

**For regulated teams:** verdicts are auditable end to end. Memory snapshot → reproducible assessment → linked escape. That's the difference between "our process is sound" and demonstrating it.

**For anyone selling or defending this work:** after sixty days you have escape-correlation data specific to your environment that nobody can replicate from the outside. "Our green-band verdicts had 94% precision in your codebase" is a claim with a receipt attached.

**For the system itself:** this is the feedback loop. Calibration feeds back into confidence scoring, so being wrong makes the next verdict better.

---

## Your first two weeks

The features reinforce each other, so order matters more than speed.

### Install and tailor — day 1

Run `/assert-iq-bootstrap` with `--mode=trial` so nothing touches your team's git history. Then `/assert-iq-tailor` to replace the placeholders with your actual stack. Fifteen minutes here changes the quality of everything downstream.

### Set your tier honestly — day 1

Work through the checklist in `.assert-iq/maturity-profile.md` and set [the tier](#maturity-aware) in both files. Choose the tier below where you think you are.

### Connect three servers — day 2

Your [code host, your tracker, and your error monitor](#mcp-servers). That's enough to answer all four layers.

### Capture your baseline — day 2

Fill in `.assert-iq/business-metrics/baseline.json` *before* anything improves. You cannot go back for this number later.

### Use the skills on real work — week 1

Run [`/risk-assess-pr`](#risk-assess-pr) on a live PR. Run [`/generate-hotspot-map`](#generate-hotspot-map) to see where your fragility actually is. Run [`/check-test-coverage`](#check-test-coverage) on something you thought was well covered.

### Write one rubric — week 2

Pick the artifact you generate most and give it an [acceptance contract](#oracle-layer). Then grade three existing examples against it and see what you learn.

### Dream once — week 2

After five or so sessions, run the safety check and then [`/dream`](#dreaming). Read the diff. That's the moment the compounding starts.

### Report — end of quarter

Run [`/measure-qi-impact`](#business-impact-dashboards) and [`/calibration-report`](#decision-confidence-calibration) together. One says what the work was worth; the other says whether to believe it.

---

## Where to go next

| | |
|---|---|
| [README.md](README.md) | The overview and install path |
| [README.assert-iq.md](README.assert-iq.md) | Full documentation — every install option, full skill reference, release history |
| [ORACLE_QUICK_START.md](ORACLE_QUICK_START.md) | Oracle Layer in five steps |
| [`.vscode/MCP.md`](.vscode/MCP.md) | Per-server MCP setup and credentials |
| [`.claude/claude-readme.md`](.claude/claude-readme.md) | Claude Code specifics |
| [`.github/vscode-readme.md`](.github/vscode-readme.md) | VS Code and Copilot specifics |

---

*Assert.IQ Agent Pack · v2.1.2 · Owned by [Jarius Hayes](https://github.com/fromjariuswithsparq) · Sparq Intelligence Studio*
