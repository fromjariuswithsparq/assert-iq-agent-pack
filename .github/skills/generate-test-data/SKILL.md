---
name: generate-test-data
mode: agent
description: "Generate deterministic, framework-conformant test data for a scenario — no flakes from data drift."
---

# Generate test data

Test data is where flakiness and brittleness are born. Produce deterministic,
isolated, PII-safe test data using the project's existing factory pattern.

## Inputs

- Target scenario: AC reference, test name, or freeform description.
- Data shape: entities, relationships, volumes needed.
- Framework / language: read from `.assert-iq/config.yaml`.

## Procedure

1. Inspect the project for existing data patterns:
   - Test factories (FactoryBoy, Factory Bot, AutoFixture, faker-js, etc.)
   - Fixture files (JSON, YAML, SQL seeds)
   - Database migrations / seed scripts
   - API stubs / contract mocks

   Use what exists. Do not introduce a new data approach without confirmation.

2. Identify the data needs:
   - Required entities and their relationships
   - Required field values (boundary, edge, realistic-but-fake)
   - Required state (e.g., user with X subscription, order in Y status)
   - Volume (single record vs. dataset for pagination tests)

3. Generate the data with these rules:
   - **Deterministic** — same scenario produces same data; seed any randomness
   - **Isolated** — each test owns its data; no shared mutable state
   - **PII-safe** — no real names, emails, addresses, payment data; use the
     project's safe-data conventions (e.g., `@example.com`, `5555-prefix`
     test cards)
   - **Realistic shape** — values respect the schema's constraints, not just
     types (e.g., a phone field has a phone-shaped value)
   - **Cleanup-aware** — surface a teardown strategy with the data

4. Output:
   - The data factory call(s) or fixture file
   - The teardown approach
   - A note on any assumptions (e.g., "assumes `seed_users()` has run")

## Governance

- Never use production data. Never reference real customer identifiers.
- Never include credentials, tokens, or API keys in test data files.
- Never generate data that violates the project's compliance posture
  (HIPAA / PCI / SOX / GDPR) — use the project's compliant test-data layer.
- If the project has no data factory and the scenario requires non-trivial
  data, propose a factory approach before generating ad-hoc data.
