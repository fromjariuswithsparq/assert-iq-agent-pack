---
name: analyze-escaped-defect
mode: agent
description: "Post-incident analysis — which signal layer should have caught it, and how do we prevent next time."
---

# Analyze escaped defect

A defect escaped to production. This skill drives QI maturity by asking
the only question that matters: which signal layer should have caught it,
and what changes so the next one doesn't?

This is a learning skill, not a blame skill.

## Inputs

- Escaped defect ID (ADO or Jira). Fetch via MCP.
- Optional: the production incident or customer report that surfaced it.

## Procedure

1. Pull the defect. Establish the timeline:
   - When was the bug introduced (commit, PR, work item)
   - When was it released
   - When was it observed
   - When was it fixed

2. Identify which signal layer should have caught it:

   - **Change layer** — was the introducing change small, low-risk on paper,
     and snuck through? Or was it high-risk and inadequately scrutinized?
   - **Protection layer** — was there a coverage gap on the affected
     surface? A missing test? A test that exists but didn't catch this
     class of failure?
   - **Trust layer** — was there a covering test that was flaky, blocked,
     or skipped at the time of release?
   - **Outcome layer** — were there earlier signals (telemetry, support
     tickets, dogfood reports) that were missed or under-weighted?

3. For each layer, identify the *specific* gap. Avoid generic statements
   like "more testing." Be precise.

4. Recommend changes — at most one per layer, ranked by leverage:
   - **Regression test** — the specific test (automated, manual, or
     exploratory) that would have caught it. Generate the test artifact.
   - **Signal addition** — a metric or signal that would have surfaced
     earlier. Specify where it lives and who owns it.
   - **Process change** — only when a process gap is the real cause
     (e.g., AC review missing). Be sparing here.
   - **Infrastructure / environment** — only when the gap is environmental.

5. Identify whether this is a one-off or part of a pattern. Pull recent
   escapes on the same component / by the same root cause. If a pattern,
   recommend a focused remediation across all related work.

6. Output an escaped-defect analysis report:
   - Timeline
   - Layer-by-layer gap analysis
   - Recommended changes (ranked)
   - Pattern assessment
   - Owners and timeline for each recommendation

## Governance

- This skill is post-incident learning. It is not a performance review of
  the engineer who introduced the change. Frame findings as systemic.
- Do not recommend "more testing" generically. Every recommendation must
  name the specific signal, test, or process change.
- Surface findings that implicate process or culture (not just code) when
  the evidence warrants — this is where QI maturity advances.
- Add the recommended regression test to the team's test backlog via the
  tracker MCP if `bug_reporter.auto_create_threshold` permits.
