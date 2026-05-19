# Quality Intelligence Maturity Profile

> Customize this document during the QI Diagnostic. Re-evaluate quarterly
> or on material change to delivery practice.

## Current tier

**Tier**: `mid`  *(one of: early | mid | higher)*

**Effective**: YYYY-MM-DD
**Re-evaluation due**: YYYY-MM-DD (quarterly)

## Rationale

Document the evidence basis for the chosen tier. This explains *why* this
tier — which directly drives skill-level behavior across the pack.

### Indicators present (supporting the chosen tier)

- [ ] Working agreements documented and followed
- [ ] Definition of Ready in active use
- [ ] Definition of Done in active use
- [ ] Regression suite exists and runs on every PR
- [ ] Defect containment metrics tracked
- [ ] Environment stability tracked
- [ ] Requirement-to-test traceability present (any form)
- [ ] Risk-based release decisions documented
- [ ] Cross-functional release governance in place
- [ ] Telemetry-informed prioritization in active use
- [ ] AI-assisted delivery with governance in place

### Indicators absent (gaps that would shift the tier down)

- ...

### Indicators that would shift the tier up

- ...

## Tier behavior summary

| Behavior | This tier |
|---|---|
| Foundation + traceability + manual generation | enabled |
| Automated test generation | enabled (mid+) / advisory (early) |
| Risk assessment on PRs | enabled (mid+) / advisory (early) |
| Agentic Healing | enabled in suggest-only mode (mid) / autonomous (higher) / disabled (early) |
| Release confidence reports | enabled (mid+) / disabled (early) |
| Routing classifier flags manual ACs as automation candidates | enabled (higher only) |
| Manual fallback produced even when AC routes to automation | enabled (early only) |

## Re-evaluation triggers

Re-evaluate the tier ahead of schedule when any of these occur:
- New compliance posture introduced
- New tooling adopted that materially changes signal availability
- Team composition changes by >30%
- Sustained escape-rate change (up or down) over 2 release cycles
- Major architectural shift (microservices migration, platform change)

## Approval

| Role | Name | Date |
|---|---|---|
| QI sponsor (Sparq) | | |
| Client QE lead | | |
| Client delivery lead | | |
