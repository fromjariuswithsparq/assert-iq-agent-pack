---
name: analyze-escaped-defect
mode: agent
description: "Post-incident analysis — which signal layer should have caught it, and how do we prevent next time."
---

<!-- markdownlint-disable MD033 -->
<!--
HOW TO CUSTOMIZE THIS SKILL
===========================

This skill is a universal template. It works out of the box for **any
language, framework, platform, tracker, or team** — the four-layer signal
model and post-incident discipline are universal; only the integration
points change. You'll get sharper, faster reports if you fill in the
per-repo specifics below.

**How placeholders work**: `{{NAME}}` strings are **documentation
placeholders, not runtime variables** — nothing substitutes them
automatically. The agent reads this file, then reads
`.assert-iq/config.yaml` to find the corresponding key (cited next to
each placeholder). If the key is absent, the agent infers from repo
signals or asks you. Wire the values once in `.assert-iq/config.yaml`
and they flow into every skill that references them — no per-skill
editing required.

1. **Tracker** — `{{TRACKER_NAME}}` is your work-item system. Examples:
   - Azure DevOps (work item IDs like `AB#1234` or `#1234`)
   - Jira (keys like `PROJ-1234`)
   - GitHub Issues (`#1234`, `owner/repo#1234`)
   - GitLab Issues (`#1234`, `group/project#1234`)
   - Linear (`ENG-1234`)
   - Asana, Shortcut, ClickUp, Trello, monday.com — use whatever ID format
     your team links from commits and PRs
   Set this in `.assert-iq/config.yaml > tracker.system`.

2. **Tracker fetch path** — `{{TRACKER_MCP}}` is the mechanism the agent
   uses to pull the defect record. Options in priority order:
   - MCP server wired in `.assert-iq/config.yaml > mcp.<system>` (preferred
     when available — ADO, Jira, GitHub, GitLab, Linear all have MCPs).
   - CLI fallback (`gh issue view`, `glab issue view`, `az boards work-item
     show`, `jira issue view`).
   - Manual paste — the user provides the defect description and timeline
     inline. The skill still works; it just can't auto-fetch history.

3. **Incident / telemetry source** — `{{INCIDENT_SOURCE}}` is where the
   bug was first observed in production. Examples:
   - APM / observability: Datadog, New Relic, Dynatrace, Application
     Insights, Honeycomb, Sentry, Rollbar, Splunk
   - Customer-support tooling: Zendesk, Intercom, Salesforce Service Cloud
   - On-call paging: PagerDuty, Opsgenie, VictorOps
   - Internal dogfood / bug reports
   Specify the URL or query the analyst should consult.

4. **Test backlog destination** — `{{TEST_BACKLOG_LOCATION}}` is where new
   regression-test work items land. Defaults to the same tracker as the
   defect, under whatever epic / label your team uses for QE work (e.g.
   `qe/regression`, `area-path/Quality`, `team:platform-qe`). Wired via
   `.assert-iq/config.yaml > bug_reporter.auto_create_threshold` and
   `tracker.regression_area_path`.

5. **Test artifact targets** — when a regression test is recommended, the
   skill calls into the appropriate generator (`generate-automated-unit-
   test`, `generate-automated-api-test`, `generate-automated-ui-test`, or
   the manual-test / exploratory-charter skills). Those skills are
   independently customizable to your framework / language — see their
   own HOW TO CUSTOMIZE blocks.

6. **Component / pattern lookup** — to detect whether an escape is part of
   a pattern, the skill queries recent escapes on the same component or
   root cause. Configure the lookup in
   `.assert-iq/config.yaml > escape_pattern_lookup`:
   - `tracker_query` — saved query / JQL / WIQL / GitHub search string
   - `lookback_days` (default `90`)
   - `pattern_threshold` (default `3` escapes on the same component
     within the lookback window triggers a "pattern" classification).

7. **Report sink** — by default the report is written to
   `escaped-defect-report.md` at the repo root. Override the path in
   `.assert-iq/config.yaml > escape_analysis.report_path`. (Structured
   QI signal emission is separate — see the `signals` section in
   `.assert-iq/config.yaml`.)

8. **Privacy / blameless framing** — this skill is *systemic learning*,
   not performance review. The governance section below is non-negotiable
   regardless of tier. Do not weaken it.

9. **Five Whys discipline** — `.assert-iq/config.yaml >
   escape_analysis.five_whys`:
   - `max_depth` (default `7`) — runaway guard only. A short chain
     that reaches an evidence-exhausted root is correct.
   - `require_evidence_per_link` (default `true`, recommended locked)
     — every "why" must cite a concrete fact: timeline entry, commit
     SHA, PR review comment, test file, coverage report, dashboard
     query, alert rule, incident note, support ticket, or process
     artifact. Unevidenced links are marked `[ASSUMPTION]` and pause
     the chain.
   - `anti_pattern_capture` (default `ask`) — `ask` prompts before
     appending to the Anti-Patterns appendix below; `off` disables
     capture. `auto` is deliberately not offered — silent self-edits
     to the skill are forbidden.
-->

# Analyze escaped defect

A defect escaped to production. This skill drives QI maturity by asking
the only question that matters: which signal layer should have caught it,
and what changes so the next one doesn't?

This is a **learning skill, not a blame skill**.

The skill is **tracker-, framework-, language-, and platform-agnostic** —
it works with whatever work-item system, test stack, and observability
pipeline your team already uses (see `{{TRACKER_NAME}}`,
`{{INCIDENT_SOURCE}}`, and `{{TEST_BACKLOG_LOCATION}}` in the
customization block above).

## Inputs

- **Escaped defect ID** in your tracker's native format
  (`{{TRACKER_NAME}}`) — required. Fetch via `{{TRACKER_MCP}}` if wired,
  otherwise via CLI or manual paste.
- **Incident / observation reference** (optional) — link or query into
  `{{INCIDENT_SOURCE}}` (APM, support ticket, on-call page, dogfood
  report) that surfaced the bug.
- **Affected component or surface area** (optional but recommended) —
  enables the pattern lookup in step 5.

## Procedure

1. **Pull the defect** and establish the timeline:
   - When was the bug introduced (commit, PR, work item)
   - When was it released
   - When was it observed
   - When was it fixed

2. **Run the Five Whys causal chain — MANDATORY on every escape,
   including obvious ones.** Non-skippable. Discipline over depth.
   A short chain that terminates early at a genuine root is correct;
   skipping is not. The chain prevents pattern-match-to-known-fix
   drift and is the core of systemic learning.

   Before starting, check the **Anti-Patterns** appendix at the
   bottom of this skill for a matching escape signature. If a match
   is found, note the signature ID, then still run a (short) chain
   to *ratify* the match against the current defect — never shortcut
   purely on pattern recognition.

   Chain rules:

   - **Start from the customer-visible symptom** (the defect as
     observed in production, not as filed in the tracker), then ask:
     why did this reach production?
   - **Each "why" must cite concrete evidence**: a timeline entry,
     commit SHA, PR review comment, test file path, coverage report
     gap, dashboard query, alert rule, incident note, support ticket,
     or process artifact (e.g. AC document, risk register entry).
     Cite inline (`PR #1234 review thread`, `coverage.xml: 0% on
     PaymentService.RefundAsync`, `dashboard "checkout-errors" has
     no alert <500/min`).
   - **Tag each link's confidence**: `evidenced` (artifact cited),
     `inferred` (reasoned from cited evidence), `assumed` (no
     evidence — pauses the chain).
   - **Render the chain inline in the working response**, not only
     in the final report, so the user can intervene precisely at the
     drifting link.
   - **Stop rule = evidence exhaustion**, not layer boundary. Keep
     asking "why" until the next answer cannot be backed by evidence
     in the tracker, repo, telemetry, or wired MCP sources. Code,
     tests, process, culture, and tooling are all in-scope for the
     chain. The action scope (regression test, signal addition,
     process change, infra change) is bounded separately in step 5.
   - **Runaway guard**: depth cap `escape_analysis.five_whys.max_depth`
     (default 7). If reached without exhausting evidence, declare
     insufficient evidence per the Stop conditions.
   - **Contradictory evidence mid-chain**: single chain only — pick
     the higher-confidence branch, continue, log the discarded branch
     in the report. No parallel chains.
   - **When the user pushes back**: revise the specific challenged
     link with new evidence. Do **not** restart the chain or swap the
     responsible layer to please the user. Hold position when every
     link is `evidenced`; defer or re-investigate only when any link
     is `inferred` or `assumed`.
   - **When the user states the root cause**: still produce the
     chain from the symptom to validate or contradict.
   - **Blameless rule applies mid-chain**: name systems, processes,
     and signals — never individuals. "Author skipped tests" is a
     blame framing; "PR template did not require risk-band
selection on payment-service changes" is a systemic framing.
     Reframe whenever a link drifts toward blame.

   Record the terminal link as the **systemic root cause**. The next
   step's layer identification falls out of where evidence ran out.

3. **Identify which signal layer should have caught it.** The
   responsible layer must follow from the terminal link of the chain
   — do **not** select a layer before the chain terminates.

   - **Change layer** — was the introducing change small, low-risk on paper,
     and snuck through? Or was it high-risk and inadequately scrutinized?
   - **Protection layer** — was there a coverage gap on the affected
     surface? A missing test? A test that exists but didn't catch this
     class of failure?
   - **Trust layer** — was there a covering test that was flaky, blocked,
     or skipped at the time of release?
   - **Outcome layer** — were there earlier signals (telemetry, support
     tickets, dogfood reports) in `{{INCIDENT_SOURCE}}` that were missed
     or under-weighted?

4. **For each layer, identify the *specific* gap.** Avoid generic
   statements like "more testing." Be precise — name the file, the test,
   the metric, the dashboard, the review step.

5. **Recommend changes** — at most one per layer, ranked by leverage:
   - **Regression test** — the specific test (automated, manual, or
     exploratory) that would have caught it. Generate the test artifact
     by invoking the appropriate generator skill for your framework.
   - **Signal addition** — a metric or signal that would have surfaced
     earlier. Specify where it lives (`{{INCIDENT_SOURCE}}` dashboard,
     log query, alert rule) and who owns it.
   - **Process change** — only when a process gap is the real cause
     (e.g., AC review missing, risk band not set). Be sparing here.
   - **Infrastructure / environment** — only when the gap is environmental
     (CI runner config, test data, secrets management, etc.).

6. **Identify whether this is a one-off or part of a pattern.** Run the
   pattern-lookup query configured in
   `.assert-iq/config.yaml > escape_pattern_lookup` (lookback default
   `90` days, threshold default `3` on the same component). If a pattern
   is detected, recommend focused remediation across all related work,
   not just this defect. **Reconcile with the Anti-Patterns appendix**
   below — the tracker query is external evidence; the appendix is the
   skill's internal memory. Both must be consulted.

7. **Output an escaped-defect analysis report** containing:
   - Timeline (introduced \u2192 released \u2192 observed \u2192 fixed)
   - **The full Five Whys chain** with per-link evidence citations,
     confidence tags (`evidenced` / `inferred` / `assumed`), and the
     stop reason
   - Discarded-branch log (if contradictory evidence was encountered)
   - Layer-by-layer gap analysis (Change / Protection / Trust /
     Outcome), tied to the terminal link of the chain
   - Recommended changes (ranked by leverage, one per layer max)
   - Pattern assessment (one-off vs. systemic, with linked prior
     escapes from both the tracker query and the Anti-Patterns
     appendix)
   - Owners and timeline for each recommendation
   - Traceability reference back to the defect ID in `{{TRACKER_NAME}}`
   - Anti-Patterns lookup result: matched signature ID, or the
     proposed-new-signature row awaiting confirmation (see step 8)

8. **Capture learning — update the Anti-Patterns appendix.** After
   the report is produced:
   - If the chain matched an existing signature, increment its
     `Recurrences` count and update `Last seen`. This may be done in
     the same turn; surface the change in the response.
   - If the chain produced a **new** signature, draft the proposed
     row (signature, root cause, diagnostic shortcut, first seen,
     recurrences = 1) and **ask the user before appending**. Asking
     is mandatory — `auto` capture is not offered. If the response
     would end before the append can be performed, include the
     proposed row and the explicit ask as the final block of the
     response so the user can approve next turn.
   - Entries must be paraphrased / pattern-level and **blameless**.
     **Never** paste defect descriptions verbatim, customer PII,
     internal URLs, secrets, support-ticket bodies, or individual
     names into the appendix.
   - The goal is to make the skill sharper over time — a matched
     signature in step 2 lets future invocations reach the systemic
     root faster without sacrificing the discipline of the chain.

## Stop conditions

- The Five Whys chain hits an `[ASSUMPTION]` link that cannot be
  resolved with available evidence — pause the chain, surface the
  unevidenced link, and recommend the specific evidence needed
  (timeline detail, PR review thread, coverage report, dashboard
  query, on-call note) before continuing. Do **not** advance the
  chain by guessing.
- The chain reaches `max_depth` without exhausting evidence — declare
  insufficient evidence; recommend further investigation rather than
  acting on a half-formed root.

## Governance

- This skill is **post-incident learning**. It is **not** a performance
  review of the engineer who introduced the change. Frame findings as
  systemic. This rule is non-negotiable regardless of maturity tier.
- Do **not** recommend "more testing" generically. Every recommendation
  must name the specific signal, test, dashboard, or process change.
- Surface findings that implicate process or culture (not just code) when
  the evidence warrants \u2014 this is where QI maturity advances.
- Add the recommended regression test to the team's test backlog via
  `{{TRACKER_NAME}}` (into `{{TEST_BACKLOG_LOCATION}}`) if
  `bug_reporter.auto_create_threshold` permits. Otherwise present the
  draft work item for human review.
- Preserve any existing traceability comments on tests or code touched
  by the recommendations (`AB#`, Jira key, etc.).
### Five Whys discipline (anti-drift)

- The chain is **mandatory** on every escape, including obvious
  ones. Skipping is forbidden; short chains are fine when the root
  is reached early.
- Every link must be evidenced or explicitly tagged `[ASSUMPTION]`.
  Unevidenced advancement is forbidden.
- The responsible layer (step 3) must follow from the terminal link
  of the chain. **Never** pick a layer before the chain terminates.
- When challenged by the user, revise the specific link with new
  evidence — do **not** restart the chain or swap the layer to
  satisfy the user. Hold position when every link is `evidenced`;
  defer or re-investigate only when any link is `inferred` or
  `assumed`.
- When the user states the root cause directly, still produce the
  chain from the symptom to validate or contradict.
- Contradictory evidence mid-chain: single chain only — pick the
  higher-confidence branch and log the discarded branch in the
  report. No parallel chains.
- **Blameless framing applies to every link**. Reframe any link that
  drifts toward individual blame into a systemic statement (process,
  tooling, signal, convention).

### Self-update discipline (Anti-Patterns appendix)

- Anti-Patterns table edits are **user-gated**. The agent may
  **never** append, edit, or reorder rows without explicit
  confirmation in the same turn. `auto` capture mode is not offered.
- Recurrence increments on a clear signature match may be applied in
  the same turn, but must be surfaced in the response.
- Entries are paraphrased, pattern-level, and **blameless**. **No**
  defect descriptions verbatim, customer PII, internal URLs, secrets,
  support-ticket bodies, or individual names.
- If the response would end before the proposed row can be appended,
  include the proposed row and the explicit ask as the final block of
  the response so the user can approve next turn.
- The appendix is the skill's long-term memory. Prefer updating an
  existing signature over creating a near-duplicate, and propose
  retiring rows that have not recurred in 12 months.
## Output

An `escaped-defect-report.md` artifact (or the path configured in
`.assert-iq/config.yaml > escape_analysis.report_path`) with the
sections listed in step 6 — including the full Five Whys chain and
the Anti-Patterns lookup result — plus any generated regression-test
files produced by the downstream test-generator skill.

## Signals emitted

When the QI signal sink is wired, this skill emits an `escape.analysis`
signal per run conforming to `.assert-iq/signal-schema.json`, carrying:
`defect_id`, `tracker_system`, `introduced_commit`, `released_at`,
`observed_at`, `fixed_at`, `responsible_layer`, `gap_summary`,
`recommendations[]`, `pattern_detected`, `related_defect_ids[]`,
`causal_chain_depth`, `causal_chain_stop_reason`
(`evidence_exhausted` | `actionable_root` | `depth_cap`
| `insufficient_evidence`), `unevidenced_links_count`,
`anti_pattern_match` (signature ID or `null`), and
`anti_pattern_proposed` (boolean — true when a new signature was
proposed for user confirmation).

## Anti-Patterns appendix

The skill's long-term memory. Each row is a reusable escape signature
with its evidence-backed systemic root cause and a diagnostic shortcut
for future invocations. Rows are added **only with user confirmation**
(see step 7 and the Self-update discipline section). Recurrence
increments may be applied automatically on a clear match but must be
surfaced in the response. Entries are blameless and pattern-level.

| Signature | Root cause | Diagnostic shortcut | First seen | Last seen | Recurrences |
| --- | --- | --- | --- | --- | --- |
| _(empty — seeded by user-confirmed captures from step 7)_ | | | | | |
