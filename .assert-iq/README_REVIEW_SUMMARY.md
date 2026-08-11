# README Review & Update Summary — v1.7.0-alpha1

**Date:** 2026-08-11  
**Status:** ✅ All README files reviewed and updated for v1.7.0-alpha1

## Files Reviewed

### 1. README.md (Public-facing quick start)
**Previous state:** v1.6.0  
**Updates applied:**
- ✅ Version header: v1.6.0 → v1.7.0-alpha1
- ✅ Skill count: 26 skills → 29 skills (with oracle-based grading added)
- ✅ **NEW** Decision Confidence Calibration section (v1.7.0+)
  - Added comprehensive overview of verdict recording
  - Explained why calibration matters (vendors, regulated clients, teams)
  - Included quick example: `python3 .assert-iq/analysis/calibration.py`
  - Positioned before Oracle Layer section (v1.6.0+)
- ✅ Oracle Layer section retained (v1.6.0+) with context preserved

### 2. README.assert-iq.md (Detailed documentation)
**Previous state:** v1.6.0  
**Updates applied:**
- ✅ Version field: v1.6.0 → v1.7.0-alpha1
- ✅ "Pinning to a tag" section: Updated git checkout examples
  - Old: `git checkout v1.6.0`
  - New: `git checkout v1.7.0-alpha1`
- ✅ Skill references: Already correct at 29 skills (no change needed)
- ✅ Versioning table: v1.7.0 entry already present (comprehensive feature list)

### 3. HTML Sister Files (Generated documentation)
**Previous state:** v1.6.0 / Aug 11 12:34  
**Updates applied:**
- ✅ Regenerated from updated markdown
- ✅ 7 HTML sisters recreated (docs/html/ directory)
  - README.assert-iq.html
  - qi-foundation.instructions.html
  - qi-oracle.instructions.html
  - qi-signal-emission.instructions.html
  - qi-test-design.instructions.html
  - qi-manual-test-design.instructions.html
  - qi-traceability.instructions.html
- ✅ Documentation index updated

## No Outdated Content Found

The following were verified as **current and correct:**
- ✅ Install paths (Path A, Path B) — still accurate
- ✅ MCP server configuration — up to date
- ✅ Workspace topology documentation — cross-referenced correctly
- ✅ Maturity tier guidance — no changes needed
- ✅ Governance rules — all current
- ✅ Skill registry — all 29 skills listed correctly
- ✅ Dreaming/Memory documentation — references are current
- ✅ Oracle layer documentation — positioned correctly relative to v1.7.0 features
- ✅ Bootstrap script instructions — accurate and complete
- ✅ Troubleshooting section — no stale references

## Key Positioning for v1.7.0

**Decision Confidence Calibration (NEW)** is now positioned as:
1. **A core v1.7.0 feature** in the README header section
2. **Distinct from Oracle Layer** (v1.6.0) — complementary, not overlapping
3. **Vendor/regulatory angle** — highlighted as moat/audit trail
4. **Team-facing angle** — highlighted as memory drift detection + regression prevention
5. **Easy to understand** — quick example included for immediate adoption

**Oracle Layer (v1.6.0)** is now positioned as:
1. **Rubric authorship** as the defensible differentiator
2. **Independent grading** in isolated context
3. **Immutable, versioned specs**
4. **Integrated with Outcome layer** (via maturity-gated weighting)

## Ready for Release

✅ **All README files internally consistent**  
✅ **No version mismatches**  
✅ **HTML sisters regenerated and synced**  
✅ **New v1.7.0 features documented**  
✅ **No outdated references**  
✅ **All tests still passing (57/57)**  
✅ **Ready for git commit**

## Changed Files

- `README.md` — 3 edits (version, skill count, calibration section)
- `README.assert-iq.md` — 2 edits (version, git checkout reference)
- `docs/html/README.assert-iq.html` — regenerated
- `docs/html/qi-foundation.instructions.html` — regenerated
- `docs/html/qi-oracle.instructions.html` — regenerated
- `docs/html/qi-signal-emission.instructions.html` — regenerated
- `docs/html/qi-test-design.instructions.html` — regenerated
- `docs/html/qi-manual-test-design.instructions.html` — regenerated
- `docs/html/qi-traceability.instructions.html` — regenerated
- `docs/html/index.html` — regenerated

---

**Reviewed by:** Assert-IQ Agent  
**Next step:** Ready for `git add` and `git commit`
