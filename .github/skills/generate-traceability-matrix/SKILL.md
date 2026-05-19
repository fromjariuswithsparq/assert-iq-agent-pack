---
name: generate-traceability-matrix
description: "Build a req↔code↔test matrix from ///<qi-trace: WORK-ITEM /> headers — surface orphan tests, untraceable code, uncovered ACs."
---

# Generate traceability matrix

Build a requirement ↔ code ↔ test matrix by scanning `///<qi-trace: WORK-ITEM />` headers
across the repository. Surfaces three kinds of gap that compliance teams,
release leaders, and QI maturity assessments care about.

## Inputs

- Scope: full repo, a module/path, or a release scope (set of work items).
  Default: full repo.
- Output format: markdown table, CSV, or both. Default: markdown.

## Procedure

1. Scan the codebase in scope for `///<qi-trace: WORK-ITEM />` annotations in:
   - Source files (`**/*.{cs,xaml}`)
   - Test files (`tests/**`, including `~/Library/Application Support/Code/User/prompts/assert-iq/tests/_qi/automated/`, `~/Library/Application Support/Code/User/prompts/assert-iq/tests/_qi/manual/`,
     `~/Library/Application Support/Code/User/prompts/assert-iq/tests/_qi/exploratory/`)

2. For each trace, extract:
   - Work item ID
   - Acceptance criterion reference
   - Risk tier
   - File path and (for code) function/class

3. Pull the work items via MCP to validate that:
   - The work item exists
   - The AC referenced is present in the work item
   - The work item is in scope (if a release scope was specified)

4. Cross-reference. Build the matrix:

   | Work Item | AC | Code references | Test references | Status |
   |---|---|---|---|---|
   | PROJ-123 | AC-1 | src/payments/charge.ts:42 | tests/_qi/automated/charge.spec.ts | Covered |
   | PROJ-123 | AC-2 | src/payments/refund.ts:18 | (none) | Uncovered |
   | PROJ-124 | AC-1 | (none) | tests/_qi/manual/refund.md | Orphan test |

5. Surface three gap categories:
   - **Uncovered ACs** — AC has code but no test trace (or no `manual` /
     `exploratory` artifact tracing back)
   - **Orphan tests** — test traces a work item / AC that no longer exists
     or is out of scope
   - **Untraceable code** — code in scope without any `///<qi-trace: WORK-ITEM />` header
     (use the `~/Library/Application Support/Code/User/prompts/qi-traceability.instructions.md` rules to determine which
     code should have one)

6. Compute coverage metrics:
   - AC coverage: % of in-scope ACs with at least one test trace
   - Traceability density: % of in-scope code with `///<qi-trace: WORK-ITEM />` headers
   - Orphan rate: % of test traces pointing to invalid work items

7. Output the matrix and a gap summary report.

## Governance

- Do not fabricate traces. If code lacks a trace, surface it as a gap.
- Do not remove orphan tests. Surface them and recommend either
  re-association or controlled removal.
- Do not silently downgrade an AC to "covered" because a near-match test
  exists — the trace must be explicit.
- For compliance-relevant traceability (regulated industries), surface a
  recommendation to lock the matrix at release time as an audit artifact.
