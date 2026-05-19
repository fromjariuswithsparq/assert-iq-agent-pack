---
name: generate-automated-api-test
description: "Generate API tests for a contract or work item — schema validation, error envelopes, auth scenarios."
---

# Generate automated API test

Produce framework-conformant API tests. API tests validate the contract
between services — they are higher-leverage than UI tests and lower-level
than business workflows.

## Inputs

- Target: endpoint, OpenAPI/Swagger reference, or work item ID.
- Framework: read `test_framework.primary` from `~/Library/Application Support/Code/User/prompts/.assert-iq/config.yaml`
  (commonly RestAssured, supertest, pytest-requests, Postman/Newman).

## Procedure

1. Identify the contract:
   - Pull OpenAPI/Swagger if available
   - Otherwise, infer from controller/handler code or work item description
   - Identify request schema, response schema, status codes, headers, auth

2. Generate tests covering:
   - **Happy path** — valid request, 2xx response, schema-validated body
   - **Authentication** — unauthenticated, wrong-role, expired-token paths
   - **Authorization** — cross-tenant, cross-user access where applicable
   - **Validation errors** — required fields missing, type mismatches,
     boundary violations → expected 4xx with error envelope assertions
   - **Server errors** — graceful failure of dependencies if testable in
     the configured environment
   - **Idempotency** — for endpoints that claim idempotency, verify it
   - **Pagination, filtering, sorting** — where the endpoint supports them

3. Assertion strategy:
   - Status code + response schema (full schema validation, not field cherry-pick)
   - Critical business fields by name
   - Error envelopes follow the project's error contract
   - Response time ceiling where the project enforces an SLA

4. Test data:
   - Use the project's data factory or fixture pattern
   - Generate via `/generate-test-data` if needed
   - Clean up created entities in teardown

5. Apply `~/Library/Application Support/Code/User/prompts/qi-test-design.instructions.md` rules; include `///<qi-trace: WORK-ITEM />` header.

## Governance

- Do not test against production endpoints. Confirm the target environment.
- Do not commit credentials or tokens. Use the project's secret management.
- Do not skip schema validation in favor of cherry-picked fields — schema
  drift is one of the most common silent failure modes.
- For endpoints handling PII, reference test data only; never embed real
  customer data in tests.
