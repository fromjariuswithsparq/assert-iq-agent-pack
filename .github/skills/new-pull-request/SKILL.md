---
name: new-pull-request
description: "Open a PR with a QI-aware body — risk band, AC linkage, traceability, reviewer guidance."
---

# New pull request

Create a PR for the current branch using the Assert.IQ template. Reviewers
should see the risk picture before they read a line of code.

## Inputs

- Target branch (default: `default_branch` from config).
- Work item ID. Auto-detect from branch name (e.g., `feature/PROJ-123-...`); otherwise ask. If no work item exists (housekeeping, hotfix, spike), skip AC sections — that's fine.

## Pre-flight checks

Run before anything else. **Blockers stop PR creation; fix them first, then re-run.**

| Check | Blocker? | Action |
|---|---|---|
| Hardcoded credentials in diff | **Yes — block** | "Found credential at [file:line]. Remove it, then re-run this skill." |
| Incomplete ACs, no draft signal | Warn | Ask: "Some ACs aren't done — open as draft for early feedback?" |
| Work item not found via MCP | No | Proceed; note in body |
| ADO/Github MCP unavailable | No | Generate body as text; provide paste instructions |
| Work item found but ADO/Github MCP fails | No | Same as above — produce the body, note MCP failure |

**Credential patterns to scan:** string literals containing `key=`, `token=`, `password=`, `secret=`, `api_key=`, `apikey=`; random-looking strings ≥ 20 chars; cloud key prefixes: `AKIA` (AWS), `AccountKey=` (Azure), `ya29.` (GCP).

## PR type

| Situation | PR type |
|---|---|
| All in-scope ACs complete | Ready for review |
| Any AC deferred (not yet implemented) or user wants early feedback | **Draft PR** |
| Explicit `--draft` | Draft PR |

## Procedure

### Step 1: Fetch context

1. Fetch work item via MCP (if available): title, description, ACs.
2. Identify ACs **covered** by this branch vs. **deferred** (out of scope or not yet done).
3. If no work item: mark AC fields as `N/A — no linked work item`, proceed.

### Step 2: Self-assess risk

Use `/risk-assess-pr` output if available. Otherwise:

| Signal | Contribution |
|---|---|
| Changed lines > 200 | +amber |
| New external API / auth / payment / data-export logic | +amber → red |
| Credential in diff | **Red — blocker (should have been caught in pre-flight)** |
| Changes beyond linked ACs (scope creep) | +amber |
| Pure deletion / dead-code removal | −green |
| Good automated test coverage | −green |

Final band: **🟢 Green** / **🟡 Amber** / **🔴 Red** — plus a one-line rationale.

### Step 3: Generate PR title and body

**Title format:**
- With work item: `[WORK-ITEM] Imperative description` → `[PROJ-456] Add payment retry with exponential backoff`
- No work item: plain imperative → `Remove dead code from DataExportService`

**Standard body template:**

```markdown
## Summary
[One paragraph: what changed and why, in plain language.]

## Work item
- **Linked:** [PROJ-456 — Payment retry](link)  |  or  `N/A — no linked work item`
- **ACs covered:** AC1 ✅, AC2 ✅
- **ACs deferred:** AC3 — not yet implemented (scoped to PROJ-460)  |  or  `N/A`

## Risk band
**🟡 Amber** — Retry logic touches payment flow; 240 lines changed across 4 files.

## Tests
| AC | Test | Type |
|---|---|---|
| AC1 | `PaymentServiceTests.cs > RetryLogicTests` | Automated |
| AC2 | Manual: cart payment failure flow (see test plan) | Manual |
| N/A | No tests needed — pure deletion | N/A |

## Traceability
- `///<qi-trace: PROJ-456 />` on: `PaymentService.ProcessPayment`, `PaymentService.RetryWithBackoff`
- Intentional exceptions: none  |  or: `N/A — no linked work item`

## Reviewer guidance
- **Start here:** `PaymentService.RetryWithBackoff` — retry count and backoff multiplier
- **Watch for:** off-by-one on max retries; concurrent retry race condition
- **Out of scope:** refund flow, payment method switching
- **Scope notes:** none  |  or: `Includes JSON export (not in ACs) — added because [reason]`
```

**No-work-item example (abbreviated):**
```markdown
## Summary
Deleted ~300 lines of commented-out code and unused helpers across 8 files. No behavior change.

## Work item
N/A — no linked work item

## Risk band
**🟢 Green** — pure deletion; no logic changed; automated tests pass.

## Tests
No tests needed — no behavior changed.

## Traceability
N/A — no linked work item

## Reviewer guidance
- **Start here:** any file with ≥ 50 lines deleted
- **Watch for:** any deletion that turns out to be used via reflection or dynamic dispatch
- **Out of scope:** refactoring, renaming — only deletions
```

### Step 4: Handle repo PR template

If `.github/pull_request_template.md` (or similar) exists:

1. Populate the template's existing fields — don't leave placeholder text.
2. **Overlapping sections:** embed QI content *inside* the template's section rather than duplicating.
3. **QI sections with no template equivalent:** add them after the last template section under `<!-- QI additions -->`.
4. Never remove template checkboxes or required fields.
5. **If template has a `## Risk` section:** enrich it with the risk band assessment (same rule as any overlapping section).
6. **If template has no sections at all:** add QI structure as labeled sections after the template's free-form content.

**Merge example** (template: `## What changed` / `## Testing` / `## Checklist`):
```markdown
## What changed
Added retry logic to PaymentService with exponential backoff (AC1) and UI error message (AC2).
Risk: 🟡 Amber — payment flow touched, 240 lines changed.

## Testing
| AC | Test | Type |
|---|---|---|
| AC1 | `PaymentServiceTests.cs > RetryLogicTests` | Automated |
| AC2 | Manual: cart payment failure flow | Manual |

## Checklist
- [x] Tests added
- [x] No hardcoded credentials
- [x] Work item linked

<!-- QI additions -->
## Traceability
- `///<qi-trace: PROJ-456 />` on: `PaymentService.ProcessPayment`, `PaymentService.RetryWithBackoff`

## Reviewer guidance
- **Start here:** `RetryWithBackoff` — retry count and backoff multiplier
- **Watch for:** off-by-one on max retries; concurrent retry race condition
```

### Step 5: Open PR

Open via ADO/Github MCP:
- `title`: Step 3
- `body`: Steps 3–4
- `draft`: true if draft PR
- `base`: target branch

**If MCP unavailable or fails at any point:** Produce the complete PR body as formatted markdown and say: "MCP unavailable — copy the body below and paste it into a new PR on ADO/Github."

## Governance

- Do not auto-merge. Do not bypass required reviewers.
- Block PR creation if a credential or secret is in the diff. Fix it, then re-run.
- Do not include PII from work item descriptions (names, emails, internal data).
- Scope creep must appear in "Scope notes" — never silently include out-of-AC changes.
