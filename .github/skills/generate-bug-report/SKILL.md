
# Generate bug report

Convert a failure into a tracker-ready defect that requires zero rework. A good defect saves multiple cycle hours; a bad defect spawns clarification threads.

---

## Scope check

Before generating, verify this IS a defect:

| Signal | Route | Action |
|--------|-------|--------|
| Something worked before and now doesn't | **Defect** | Proceed |
| Expected behavior never existed | **Feature request** | Decline: "This is missing functionality, not a defect. Want me to draft a feature request/user story instead?" |
| Behavior matches spec but user dislikes it | **Enhancement** | Decline: "This works as designed. Want me to draft an enhancement request?" |
| Works as designed but UX is poor/confusing | **UX issue** | Decline: "This is a UX improvement, not a functional defect. Want me to draft a UX work item?" |
| Already reported — open | **Duplicate** | Link: "Found existing [ID] — adding your context as a comment." |
| Already reported — closed/resolved | **Regression** | Proceed as defect, tag regression, link to closed item: "This was fixed in [ID] but has regressed." |
| Test failed but has known flake history | **Flaky test** | "This test has flake history — filing as test-reliability issue, not product defect." |
| Active incident in progress | **Incident** | Attach to incident: "Linked to active incident [ID]." |
| Multiple symptoms, one root cause | **Compound** | File ONE bug for root cause, list all symptoms. |
| Unclear whether defect or gap | **Clarify** | "Is this something that previously worked and broke, or functionality that was never built?" |

**Compound failure rule:** One root cause = one bug listing all symptoms. Independent root causes = separate bugs. When unsure: file one, note "May split if investigation reveals independent causes."

---

## Inputs

- **Failure source:** test failure, manual finding, telemetry alert, or production incident
- **Target tracker:** Read from project config if available; otherwise ask. Support ADO and Jira.

---

## Procedure

### 1. Capture failure context

Gather what's available. Mark unknowns — never fabricate.

| Field | Source | If unknown |
|-------|--------|-----------|
| Action / scenario | Test name, alert, tester report | `[TBD — needs reproduction]` |
| Expected behavior | Assertion, spec, previous behavior | `[TBD — needs spec review]` |
| Observed behavior | Error output, screenshots, metrics | **Required** — cannot file without |
| Environment | CI config, tester setup, deploy info | `[Environment not captured]` |
| Build / commit | CI metadata, release notes | `[Build unknown]` |
| Stack trace | Logs, test output, telemetry | Sanitize if present; omit if unavailable |

**Minimum viable report:** Observed behavior + suspected component.

### 2. Write the title

Let a developer decide whether to click without reading the body.

**Format:** `[Component] Verb describing what's broken — context`

| Quality | Example | Why |
|---------|---------|-----|
| Good | `[PricingService] Discount calculates 10% instead of 15% for orders over $500` | Component, symptom, condition |
| Good | `[OrderAPI] NullReferenceException in ValidateShippingAddress after v2.4.1 deploy` | Component, error type, trigger |
| Bad | `Bug in pricing` | No component, no specifics |
| Bad | `Test failed` | No information content |
| Bad | `System.NullReferenceException was thrown` | Error type without context |

### 3. Reproduction

| Source | Format |
|--------|--------|
| **Test failure** | Test command, seed/config, assertion line |
| **Manual finding** | Numbered steps from clean state |
| **Telemetry alert** | Alert query + time window + deployment correlation |
| **Production incident** | Link to incident + time window + impact count |

**Quality bar:**
- Starts from known state (logged in as X, on page Y, with data Z)
- One action per step (not "configure and submit")
- Specific trigger data (not "enter some data")
- Explicit observation point ("Click Submit → observe error toast, not redirect")

**When unknown:** "Intermittent — reproduction not confirmed. Context: [what was happening]. Investigation area: [where to look]."

**Environment-specific failures** (fails in CI but not locally, or vice versa):
- Note both environments and the difference: "Fails on Ubuntu 22.04 CI runner. Passes locally on macOS 14."
- Include environment-specific factors: locale, timezone, available services, network, permissions
- Tag with `env-specific` if confirmed environment-dependent

### 4. Classify severity and priority

**Severity** = impact if unresolved. **Priority** = urgency of fix (may differ).

| Severity | Criteria | Examples |
|----------|----------|----------|
| **Critical** | Breaks critical workflow, no workaround, data loss/security risk | Payment down; data corruption; auth bypass |
| **High** | Degrades critical workflow OR breaks non-critical, no workaround | Checkout 10x slower; export broken |
| **Medium** | Non-critical degradation, workaround available | Report formatting wrong; search duplicates |
| **Low** | Cosmetic, edge-case, minimal impact | Typo in error; 1px alignment |

**Priority guidance:**
| Severity | Typical Priority | Differs when |
|----------|-----------------|-------------|
| Critical | P1 (immediate) | Almost never |
| High | P2 (next sprint) | P1 if affects release/SLA |
| Medium | P3 (backlog) | P2 if easy fix during related work |
| Low | P4 (if time) | P3 if high-visibility area |

**When ambiguous:** State both:
> "Severity: High (could argue Critical — 847 users, but performance degradation not total failure)"

**Impact multipliers:**
- \> 100 users in < 1 hour → consider escalating
- Data corruption/loss → minimum High
- Auth/authz bypass → Critical
- Blocks revenue → Critical

### 5. Identify component

Stop at first match:
1. **Stack trace** → file/class/method
2. **Error message** → service, endpoint, module
3. **Area of failure** → UI area, API route, job name
4. **Deployment correlation** → what was just deployed?
5. **Recent commits** → only if above yields nothing

### 6. Duplicate check

Search tracker for:
- Same component + similar error message
- Same stack trace signature
- Similar title keywords in last 30 days

| Found | State | Action |
|-------|-------|--------|
| Match | Open | Link as duplicate, add context as comment |
| Match | Closed/Resolved | File new as **regression**, link to closed, tag `regression` |
| No match | — | Proceed to create |

### 7. Format for tracker

#### ADO format

```
Title: [Component] Verb describing what's broken — context

## Repro Steps
1. [Precondition / starting state]
2. [Action]
3. [Action]
4. Observe: [What goes wrong]

## Expected Result
[What should happen at observation step]

## Actual Result
[What actually happens, including exact error]

## System Info
- Environment: [OS, browser/runtime version]
- Build: [Build number or commit SHA]
- Date observed: [ISO timestamp]
- Frequency: [Always (deterministic) / Intermittent (N of M) / Once observed]

## Additional Context
- Severity: [Critical/High/Medium/Low] — [justification]
- Priority: [P1/P2/P3/P4]
- Suspected component: [Name + file/method if known]
- Impact: [User count, revenue impact, scope]
- Related items: [Incidents, related bugs, work items]
- Deployment correlation: [Release/commit if timing suggests cause]
- Area Path: [Current MDA Area]
- Iteration Path: [Current iteration]
- Tags: [regression, security, data-loss, env-specific — as applicable]
```

#### ADO format — telemetry-sourced

```
Title: [Component] Error description — deployment/time correlation

## Alert Details
- Alert: [Alert name/rule]
- Query: [KQL or monitoring query]
- Time window: [Start → End ISO]
- Error rate: [X% over Y minutes]

## Deployment Context
- Last deployment: [Release, commit, deploy time]
- Time between deploy and alert: [duration]
- Hypothesis: [Deploy caused / Unrelated because...]

## Impact
- Users affected: [count]
- Error count: [total in window]
- Affected endpoint/service: [specific]

## Stack Trace (sanitized)
[Exception type and call stack, PII removed]

## Severity & Priority
[Level] — [justification] | Priority: [P1-P4]

## Assignment
- Area Path: [Current MDA Area]
- Iteration Path: [Current iteration]

## Suggested Action
[Rollback? Hotfix? Investigation? Feature flag disable?]
```

#### Jira format

```
Summary: [Component] Verb describing what's broken — context

Description:
h3. Steps to Reproduce
# [Precondition / starting state]
# [Action]
# [Action]
# Observe: [What goes wrong]

h3. Expected
[What should happen]

h3. Actual
[What actually happens]

h3. Environment
- OS/Browser: [details]
- Version: [build/commit]
- Frequency: [Always (deterministic) / Intermittent / Once]

h3. Impact
- Users affected: [count or scope]
- Workaround: [Available — describe / None]

Priority: [Highest/High/Medium/Low]
Component/s: [Component name]
Labels: [bug, regression, severity-X, env-specific, area-tag]
```

### 8. Delivery

| Condition | Action |
|-----------|--------|
| Severity Critical or High | **Never auto-create.** Present draft, require confirmation. |
| Active incident exists | Link to incident, add as comment. |
| Likely duplicate (open) | Link, add context as comment. |
| Likely duplicate (closed) | File as regression, link to closed item. |
| Config allows auto-create AND severity ≤ Medium | Create via API/MCP, return ID. |
| No tracker access | Return formatted draft. |

---

## Handling incomplete information

When input is vague or missing critical fields:

1. **Produce what you can** — fill known fields, mark unknowns with `[TBD]`
2. **Append clarification section** with specific questions and who to ask
3. **Classify severity provisionally** with confidence qualifier
4. **Suggest investigation direction** — even without repro steps, point developers at where to look:
   - Which logs to check (application logs, browser console, network tab)
   - Which component likely owns the behavior
   - What data conditions might trigger the issue
5. **File if minimum viable** (observed behavior + component); otherwise present draft with questions

**Applies to all source types:** Telemetry alerts with partial context (alert fired but no stack trace, or stack trace but no user impact count) follow the same pattern — fill what's known, [TBD] the rest, provide investigation direction.

### Worked example — incomplete input

**Input:** "The export button doesn't work sometimes. I think it was on the reports page. Maybe Chrome?"

**Output:**
```
Title: [Reports] Export button intermittently non-functional — reproduction TBD

## Repro Steps
1. Navigate to Reports page
2. Click Export button
3. Observe: [TBD — unresponsive? Error shown? Wrong file downloaded?]

## Expected Result
[TBD — expected: file downloads / dialog appears / new tab opens]

## Actual Result
Export button "doesn't work" — specific failure mode not yet captured

## System Info
- Environment: Chrome [version TBD], OS [TBD]
- Build: [TBD]
- Date observed: ~[yesterday/day before] per reporter
- Frequency: Intermittent ("sometimes")

## Additional Context
- Severity: Medium (provisional — non-critical feature, intermittent, workaround unknown)
- Priority: P3
- Suspected component: Reports / Export functionality
- Impact: [Single reporter — unknown if widespread]

## Investigation Suggestions
- Check browser console for JS errors when Export is clicked
- Check network tab for failed API calls to export endpoint
- Check if export works in incognito (extension interference?)
- Check server logs for the export endpoint around reported times

## Needs Clarification
- [ ] What exactly happens? (No response? Error? Wrong file?)
- [ ] Chrome version and OS
- [ ] Can you reproduce now? Steps that trigger it?
- [ ] Works in another browser?
- [ ] Frequency estimate (1 in 3? Once a day?)
```

---

## Data protection

Strip before including in any report:

| PII type | Replace with |
|----------|-------------|
| Email addresses | `[REDACTED-EMAIL]` |
| Phone numbers | `[REDACTED-PHONE]` |
| SSN / national IDs | `[REDACTED-ID]` |
| Payment card numbers | `[REDACTED-CARD]` |
| Physical addresses | `[REDACTED-ADDRESS]` |
| Customer names | `[CUSTOMER]` or anonymized ref |
| Auth tokens / secrets | `[REDACTED-TOKEN]` |
| Internal URLs | `[INTERNAL-URL]` |
| IP addresses (user) | `[REDACTED-IP]` |

**Rule:** When in doubt, redact. Too much redaction is fixable; leaked PII is a compliance incident.

After redaction: `⚠️ PII redacted. Contact [source] for unredacted details if needed for debugging.`

---

## Self-check before delivery

- [ ] Title: `[Component] Verb — context` format, scannable
- [ ] No PII/secrets in any field
- [ ] Severity justified (not just a label)
- [ ] Priority set (or noted as TBD if org norms unknown)
- [ ] Reproduction specific enough to attempt (or TBD with investigation suggestions)
- [ ] Duplicate check done (or noted as pending)
- [ ] Correctly routed — not a feature request, enhancement, flaky test, or UX issue
- [ ] Regression tagged if previously-fixed issue
- [ ] Environment-specific factors noted if applicable
