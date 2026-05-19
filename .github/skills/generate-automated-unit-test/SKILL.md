---
name: generate-automated-unit-test
mode: agent
description: "Generate unit tests for a function, class, or module — happy path, edge cases, error handling."
---

# Generate automated unit test

Produce framework-conformant unit tests. Unit means: in-process, mocked at
the right boundary, deterministic, fast.

## Inputs

- Target: function, class, or module path.
- Framework: read `test_framework.primary` from `~/Library/Application Support/Code/User/prompts/.assert-iq/config.yaml`.

## Procedure

1. Inspect the target. Identify:
   - Pure logic vs. side effects
   - External dependencies (DB, network, filesystem, time, randomness)
   - Branching paths and boundary conditions
2. Choose the mock boundary. Mock at the dependency seam, not at the
   subject under test.
3. Generate tests covering:
   - Happy path (typical valid input)
   - Edge cases (empty, null, max, min, unicode where relevant)
   - Error handling (each thrown/returned error path)
   - State transitions (where relevant)
4. Structure each test using AAA (Arrange-Act-Assert) or the project's
   established pattern. Do not introduce a new pattern.
5. Apply `~/Library/Application Support/Code/User/prompts/qi-test-design.instructions.md` rules; include `///<qi-trace: WORK-ITEM />` header.
6. Run a self-review: are tests independent? Fast? Deterministic? Do they
   test behavior, not implementation?

## Governance

- Do not test private members directly. Test behavior via the public surface.
- Do not introduce new mocking libraries. Use what the project uses.
- Mark tests with the work item that motivated them.
