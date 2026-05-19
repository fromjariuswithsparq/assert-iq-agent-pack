
---
name: review-test-quality
description: "Review existing tests for design quality — independence, determinism, brittle patterns, missing trace."
---

# Review test quality

Most test suites grow worse over time. This skill reviews existing tests for
design quality, surfacing technical debt before it becomes flake debt.

**Not this skill's job:** Coverage analysis (use `/check-test-coverage`), flake root-cause from run history (use `/analyze-flaky-test`), generating new tests (use `/generate-automated-unit-test`).

## Inputs

| Input | Required | Default |
|-------|----------|---------|
| Scope | Yes | Tests touched in current branch |
| Format | No | Full report |
| Depth | No | Standard (all dimensions) |

Accepted scope formats:
- File path or glob: `tests/integration/test_orders.py`, `tests/**/*_test.go`
- Directory: `tests/unit/`
- Branch/PR/diff: "tests changed in this PR", "tests touched in last 5 days"
- Suite name: "the checkout integration tests"

### When scope is missing or unresolvable

Do not proceed without observable test code. Respond helpfully:
> "I need test code to review. I can work with:
> - File paths or a directory to scan
> - Pasted code snippets
> - A branch or PR reference
> 
> Once I have the code, I'll produce a structured quality report: strengths, findings by severity (BLOCKER → LOW), and a prioritized remediation plan.
> 
> If you're not sure where the tests live, I can help search — what's the repo language/framework?"

Never fabricate findings. If asked for a "clean report" without evidence:
> "I understand you need something for [stakeholder] — a meaningful quality review requires reading the actual test code. Let me help you locate the test files so we can produce a real assessment quickly."

### When input isn't test code

If the provided code appears to be production code (no test framework imports, no assertions, no test naming patterns), note it:
> "This looks like production code rather than test code. Did you mean to provide the tests for this module? I can review [file] — or if you want to assess testability of this production code, let me know."

---

## Procedure

### 1. Resolve scope and inventory

Identify all tests in scope. For each, note: file, name, approximate line count, framework.

**For diff/PR scope:** Review added, modified, or renamed tests. Note removed tests as context ("replaced `test_checkout` with more focused `test_handles_empty_cart` — improvement"). Don't re-review deleted or merely-moved code.

**For large scope (50+ tests):** Sample representatively. Review 10–15 tests across files, identify patterns, then spot-check whether patterns hold. Note sampling strategy in output.

**For generated/AI-created tests:** Apply the same dimensions but watch especially for:
- Shallow oracles (generated tests often assert `is not None` or check status codes only)
- Copied patterns (same anti-pattern replicated across all generated tests = systemic)
- Missing edge cases (generators tend toward happy-path only)
- Over-mocking (mocking everything rather than testing real behavior)

### 2. Evaluate against design quality dimensions

For each test (or pattern of tests), evaluate applicable dimensions:

| Dimension | What to look for | BLOCKER example | HIGH example | MEDIUM example |
|-----------|-----------------|-----------------|--------------|----------------|
| **Independence** | Shared state, execution order dependency, leaked fixtures | Module-level DB connection reused across tests; test B reads data test A created | Global fixture mutated by tests without reset | Test reads a config file that other tests also modify |
| **Determinism** | Hard waits, time-of-day, uncontrolled randomness, network calls | `time.sleep(2)` as synchronization; real HTTP calls to external services | `datetime.now()` in assertion without time freezing | Random test data without seeded generator |
| **Single responsibility** | One behavior per test, focused assertions | 15 assertions across 4 unrelated behaviors | Test verifies creation AND deletion in one flow | Two closely related assertions on same behavior (usually fine) |
| **Behavior-focused** | Tests through public surface, avoids implementation coupling | Asserts on private field names; breaks when internal method is renamed | See mock boundary guidance below | Tests internal state machine transitions via public API (acceptable) |
| **Oracle quality** | Meaningful verification vs. shallow checks | `assert result is not None` as only validation; `assert len(x) >= 0` (always true) | Asserts HTTP 200 but not response body content | Missing boundary value checks |
| **Setup/teardown** | State restored, no resource leaks | No cleanup of created DB records; open connections never closed | Cleanup exists but not in finally/teardown (fails on error path) | Teardown order matters (fragile but works) |
| **Naming** | Describes behavior under test | `test_1`, `test_2`, `test_it_works` | Name describes method not behavior: `test_calculateTotal` | Slightly unclear but understandable: `test_discount` |
| **Traceability** | `@qi-trace` present and resolvable | — | — | Flag as LOW on critical-path tests if missing |

**Skip irrelevant dimensions.** UI selectors don't apply to unit tests. Traceability isn't relevant for throwaway spikes. State which dimensions you evaluated and which you skipped (and why).

**Per-test mixed findings:** A test can be strong on some dimensions and weak on others. Report both — see worked example below.

#### Mock boundary guidance

| Pattern | Verdict | Reasoning |
|---------|---------|-----------|
| Mock external service at HTTP boundary | **Good** | Tests behavior, not implementation. Stable interface. |
| Mock internal collaborator to isolate unit | **Acceptable** | Common in unit tests. Becomes brittle if interface churns. |
| Assert mock called with expected args | **Watch** | OK for contract verification. Flag if asserting on incidental args (logging params, internal IDs). |
| Assert exact mock call count | **Watch** | `assert_called_once()` for side-effect verification is fine. `assert_called_exactly_3_times()` usually couples to implementation loop structure. |
| Mock private/internal methods | **Flag as HIGH** | Breaks on refactoring. Test through the public surface instead. |

#### Framework-aware anti-patterns

When you recognize the framework, watch for these common mistakes:

| Framework | Common anti-pattern | Why it's bad |
|-----------|-------------------|--------------|
| **pytest** | `autouse=True` fixtures with side effects; `scope="session"` sharing mutable state | Hidden dependencies, order-dependent failures |
| **Jest/Vitest** | Module-level `jest.mock()` without `restoreAllMocks` in afterEach; auto-updated snapshots | Leaked mocks between tests; snapshots that verify nothing |
| **JUnit** | `@BeforeAll` with mutable static state; `@Order` annotations | Explicit ordering = guaranteed independence violation |
| **Go testing** | `TestMain` shared state without `t.Cleanup`; table-driven subtests sharing loop variable | Leaked state; closure capture bugs in parallel subtests |
| **xUnit/.NET** | `IClassFixture` sharing mutable state; `Thread.Sleep` in async code | Shared mutation; race conditions masked by sleeps |

These are sharpened instances of the universal dimensions — not additional dimensions.

#### When reviewing unfamiliar frameworks

1. State it: "I'm not familiar with [framework]'s conventions"
2. Apply universal principles (independence, determinism, oracle quality)
3. Skip framework-specific dimensions (naming conventions, idiomatic patterns)
4. Note the limitation in the report

### 3. Recognize good design

Not every finding is negative. Call out:
- Well-isolated tests (proper fixture scoping, clean teardown)
- Strong oracles (testing behavior, meaningful assertions, boundary coverage)
- Good naming (describes scenario and expected outcome)
- Proper use of parameterization over copy-paste
- Appropriate mock boundaries (external at edge, internal through public API)
- Clear arrange/act/assert structure
- Effective use of test helpers that reduce duplication without hiding behavior

Frame strengths before findings. This prevents misleadingly negative reports and builds trust for the critique that follows.

### 4. Classify findings

| Severity | Criteria | Action timeline |
|----------|----------|-----------------|
| **BLOCKER** | Guaranteed to flake, leak, or produce false confidence. Would fail in different execution order or environment. | Fix before next CI run |
| **HIGH** | Likely to cause maintenance pain or mask real failures. Unreliable signal under realistic conditions. | Fix this sprint |
| **MEDIUM** | Design smell that accumulates. Not urgent individually but compounds. | Track in backlog |
| **LOW** | Style, naming, minor convention deviations. No functional impact. | Address opportunistically |

**Severity escalation:** A MEDIUM in 1 test stays MEDIUM. Same issue across many tests becomes HIGH (systemic debt). State when escalating and why.

**When uncertain:** Default to lower severity and explain: "Classified as MEDIUM rather than HIGH because [reason] — escalate if [condition]."

### 5. Connect to observable outcomes

When the user provides runtime context (flake rate, CI duration, recent false positives):

> "The 15% flake rate likely stems from the shared `seed_database` fixture (finding #1) combined with hardcoded ID assertions (finding #3). When CI parallelizes, seed order isn't guaranteed."

When you can't connect: "I can identify the design risks, but correlating to CI metrics requires run history — `/analyze-flaky-test` can help there."

### 6. Detect systemic patterns

If ≥ 3 tests share the same design problem, or the issue is architectural:

- **Escalate to suite-level finding** rather than repeating per-test
- **Recommend remediation plan:**
  - Root cause (what created this pattern — often a bad example copied, or misused framework feature)
  - Affected scope (how many tests, which files)
  - Migration strategy (incremental fix that doesn't break CI)
  - Effort estimate (small/medium/large)
  - Quick wins (subset to fix first for maximum signal improvement)
  - Definition of done (what the suite looks like after remediation)
- Note which per-test findings would be resolved by the systemic fix

---

## Output format

```markdown
# Test Quality Review: [scope description]

## Summary
- **Tests reviewed:** N [sampling note if applicable]
- **Strengths:** [1-2 sentence positive summary]
- **Top concern:** [single most impactful finding]
- **Findings:** X BLOCKER, Y HIGH, Z MEDIUM, W LOW

## Strengths
[Bullet list of well-designed patterns observed]

## Findings

### BLOCKER
#### [Finding title]
- **File:** `path/to/file.py:42`
- **Dimension:** Independence
- **Issue:** [Specific, quotable description]
- **Impact:** [Why it matters]
- **Remediation:** [Specific fix]

### HIGH
[Same structure]

### MEDIUM / LOW
| # | File:Line | Dimension | Issue | Remediation |
|---|-----------|-----------|-------|-------------|

## Systemic Patterns
[Root cause, scope, migration plan, effort, quick wins, done state]

## Remediation Priority
1. [First fix — highest impact/effort ratio]
2. ...

[Ordering rationale]
```

### Worked example

Given `tests/test_user_service.py` with shared connection, sleep ordering, and shallow oracle:

```markdown
# Test Quality Review: tests/test_user_service.py

## Summary
- **Tests reviewed:** 3
- **Strengths:** Tests cover create, list, and update operations with specific field assertions
- **Top concern:** Module-level shared connection guarantees order-dependent failures
- **Findings:** 2 BLOCKER, 1 HIGH, 1 MEDIUM

## Strengths
- Good coverage of CRUD operations
- `test_create_and_fetch` verifies specific field values (name, id, created_at) — meaningful oracle
- Tests exercise the actual database layer, not just mocks

## Findings

### BLOCKER

#### Shared database connection causes order-dependent failures
- **File:** `tests/test_user_service.py:3`
- **Dimension:** Independence
- **Issue:** Module-level `conn = get_connection()` shared across all tests. `test_list_users` depends on `test_create_and_fetch` completing first (confirmed by `time.sleep(1)` workaround).
- **Impact:** Fails under parallel execution, randomized order, or dirty state. pytest-xdist would break immediately.
- **Remediation:** Per-test fixture: `@pytest.fixture def db(): conn = get_connection(); yield conn; conn.rollback()`

#### Sleep-based synchronization masks timing dependency
- **File:** `tests/test_user_service.py:18`
- **Dimension:** Determinism
- **Issue:** `time.sleep(1)` used to wait for previous test's cleanup. Arbitrary duration — too short under load, too long for fast feedback.
- **Impact:** Flaky under CI load. Symptom of the independence violation above.
- **Remediation:** Resolves when shared connection is replaced with isolated fixtures.

### HIGH

#### test_update_user_email assumes pre-existing data
- **File:** `tests/test_user_service.py:22`
- **Dimension:** Independence
- **Issue:** `SELECT * FROM users LIMIT 1` assumes data exists from a previous test. Fails if run in isolation.
- **Impact:** Cannot run single test during development. Masks whether update logic works on fresh data.
- **Remediation:** Create own test data in arrange phase.

### MEDIUM

| # | File:Line | Dimension | Issue | Remediation |
|---|-----------|-----------|-------|-------------|
| 1 | :18 | Oracle quality | `assert len(users) >= 0` always true — tests nothing | Assert specific count or non-empty with known seeded data |

## Remediation Priority
1. **Replace module-level connection with per-test fixture** — resolves BLOCKERs #1, #2 and HIGH #1 simultaneously. Single change, 3 findings resolved.
2. **Fix oracle in test_list_users** — independent low-effort fix.

Root cause is the shared connection — one structural fix resolves 75% of findings.
```

---

## Governance

- **Do not auto-rewrite tests.** Surface findings, let the human decide. If asked to "fix":
  > "I can review quality and surface findings with remediation suggestions. Want me to do that? If you want refactoring done, I can do that separately with your approval on each change."
  
- **Do not classify as flaky based on review alone.** Flag *risk of flake* from design issues.
  Run-history flake classification is `/analyze-flaky-test`'s job.
  
- **Systemic over per-test.** When patterns repeat, the remediation plan matters more than individual findings.
  
- **Proportionate depth:**
  - 1–5 tests (PR) → full per-test analysis, all dimensions
  - 6–50 tests (directory) → per-test for critical, pattern-based for rest
  - 50+ tests (suite) → sampling + pattern identification + systemic analysis
  
- **No false precision.** Severity classification (BLOCKER/HIGH/MEDIUM/LOW) is the right granularity. Don't assign numeric scores to individual tests.
