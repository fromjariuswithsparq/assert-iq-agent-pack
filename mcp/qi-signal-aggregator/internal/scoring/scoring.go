// Package scoring computes red flags and the final verdict. This package is
// pure: it has no I/O, no goroutines, no external state. The rubric mirrors
// the Python reference implementation captured in testdata/golden/.
//
// Integrity rule: a verdict may only be GREEN/GO if all four layers are
// STRONG and there are no red flags. Any UNGRADED layer caps the verdict
// at AMBER/GO_WITH_MITIGATION.
//
// Early-tier policy: per CLAUDE.md, early-maturity programs cannot publish
// optimistic verdicts; GREEN/GO are downgraded to AMBER/GO_WITH_MITIGATION.
package scoring

import (
	"github.com/assert-iq/qi-signal-aggregator/internal/models"
)

// DetectRedFlags returns the structured warnings that arise from the layer
// metrics. The eight flag IDs are stable identifiers; downstream consumers
// (skills, dashboards) may key on them.
func DetectRedFlags(layers models.Layers) []models.RedFlag {
	var flags []models.RedFlag

	changeM := layers.Change.Metrics
	protM := layers.Protection.Metrics
	trustM := layers.Trust.Metrics
	outcomeM := layers.Outcome.Metrics

	if asInt(changeM["late_changes"]) > 0 {
		flags = append(flags, models.RedFlag{
			ID:     "late_breaking_change",
			Signal: "Late-breaking change detected in PR scope",
			Impact: "Minimum AMBER per risk-assess-pr late-change materiality table",
		})
	}

	if blocked := asInt(trustM["blocked_count"]); blocked > 0 {
		flags = append(flags, models.RedFlag{
			ID:     "ci_checks_overridden",
			Signal: ftoa(blocked) + " blocked/skipped test(s) in run history",
			Impact: "Trust → WEAK; signals actively suppressed",
		})
	}

	if cov, ok := numeric(protM["coverage_pct"]); ok && cov < 60 {
		flags = append(flags, models.RedFlag{
			ID:     "coverage_below_floor",
			Signal: ftoa(int(cov)) + "% coverage is below the 60% universal floor",
			Impact: "Protection → WEAK; cannot reach STRONG without coverage uplift",
		})
	}

	if asInt(outcomeM["unresolved_p1"]) > 0 || asInt(outcomeM["escapes_critical"]) > 0 {
		flags = append(flags, models.RedFlag{
			ID:     "active_critical_incident",
			Signal: "Active P1/critical incident or unresolved error on touched component",
			Impact: "Outcome → WEAK; verdict cannot be GREEN/GO",
		})
	}

	if layers.Protection.State == models.StateUngraded && layers.Outcome.State == models.StateUngraded {
		flags = append(flags, models.RedFlag{
			ID:     "no_production_baseline",
			Signal: "Both Protection and Outcome layers UNGRADED",
			Impact: "Cannot assess baseline; verdict capped at AMBER",
		})
	}

	return flags
}

// ComputeVerdict implements the verdict matrix from risk-assess-pr (PR scope)
// and release-confidence (release scope), then applies early-tier capping.
// The parameter order matches the Python reference for ease of cross-reading.
func ComputeVerdict(
	layers models.Layers,
	scope models.Scope,
	tier models.MaturityTier,
	redFlags []models.RedFlag,
) models.Verdict {

	isRelease := scope == models.ScopeRelease

	states := []models.LayerState{
		layers.Change.State,
		layers.Protection.State,
		layers.Trust.State,
		layers.Outcome.State,
	}

	hasUngraded := false
	hasWeak := false
	allStrong := true
	weakCount := 0
	for _, s := range states {
		switch s {
		case models.StateUngraded:
			hasUngraded = true
			allStrong = false
		case models.StateWeak:
			hasWeak = true
			allStrong = false
			weakCount++
		}
	}

	var band models.VerdictBand
	var rationale string
	mitigation := false

	switch {
	case hasUngraded && !hasWeak:
		band = ifElse(isRelease, models.BandGoWithMitigation, models.BandAmber)
		rationale = "Partial-signal mode: one or more layers UNGRADED. Verdict capped per integrity rule."
		mitigation = true

	case allStrong && len(redFlags) == 0:
		band = ifElse(isRelease, models.BandGo, models.BandGreen)
		rationale = "All four layers STRONG; no red flags."
		mitigation = false

	case hasWeak && !hasUngraded && len(redFlags) == 0:
		if weakCount == 1 {
			band = ifElse(isRelease, models.BandGoWithMitigation, models.BandAmber)
			rationale = "One layer WEAK; mitigation required for the affected layer."
		} else {
			band = ifElse(isRelease, models.BandHold, models.BandRed)
			rationale = ftoa(weakCount) + " layers WEAK; aggregate signal does not support release."
		}
		mitigation = true

	case len(redFlags) > 0:
		critical := false
		for _, f := range redFlags {
			if f.ID == "active_critical_incident" || f.ID == "no_production_baseline" {
				critical = true
				break
			}
		}
		if critical || hasWeak {
			band = ifElse(isRelease, models.BandHold, models.BandRed)
			rationale = "Red flag(s) present alongside weak/ungraded signal — cannot ship without resolution."
		} else {
			band = ifElse(isRelease, models.BandGoWithMitigation, models.BandAmber)
			rationale = "Red flag(s) present; advisory mitigation required."
		}
		mitigation = true

	default:
		band = ifElse(isRelease, models.BandGoWithMitigation, models.BandAmber)
		rationale = "Mixed signal; mitigation required."
		mitigation = true
	}

	tierCapped := false
	if tier == models.TierEarly && (band == models.BandGreen || band == models.BandGo) {
		band = ifElse(isRelease, models.BandGoWithMitigation, models.BandAmber)
		rationale = "Early-tier policy: optimistic verdicts capped at AMBER/GO_WITH_MITIGATION (CLAUDE.md tier gating)."
		mitigation = true
		tierCapped = true
	}

	return models.Verdict{
		Band:               band,
		MitigationRequired: mitigation,
		Rationale:          rationale,
		TierCapped:         tierCapped,
	}
}

// MergeLayersByKind applies the worst-critical-path rule when multiple
// adapters contribute to a single layer (e.g., coverage_xml AND
// qi_traceability_scan both cover Protection). The merged layer takes the
// worst contributing state; evidence is concatenated; metrics are namespaced
// with the adapter name to avoid collisions.
func MergeLayersByKind(byAdapter map[string]models.Layer, kind string) models.Layer {
	if len(byAdapter) == 0 {
		return models.Layer{
			State:  models.StateUngraded,
			Reason: "no adapters configured for " + kind,
		}
	}

	rank := map[models.LayerState]int{
		models.StateStrong:   0,
		models.StateUngraded: 1,
		models.StateWeak:     2,
	}

	worst := models.StateStrong
	mergedMetrics := map[string]any{}
	var mergedEvidence []models.Evidence
	var reasons []string

	for name, lay := range byAdapter {
		if rank[lay.State] > rank[worst] {
			worst = lay.State
		}
		for k, v := range lay.Metrics {
			// Adapter-namespaced copy preserves provenance for downstream
			// inspection (e.g., dashboards that want per-adapter breakdown).
			mergedMetrics[name+"."+k] = v
			// Canonical copy is what scoring.DetectRedFlags reads. When
			// multiple adapters contribute the same key, keep the worst
			// value: max for numbers, OR for booleans. This mirrors the
			// "worst critical path" semantic on the state itself.
			if existing, ok := mergedMetrics[k]; ok {
				mergedMetrics[k] = worstMetric(existing, v)
			} else {
				mergedMetrics[k] = v
			}
		}
		mergedEvidence = append(mergedEvidence, lay.Evidence...)
		if lay.State == models.StateUngraded && lay.Reason != "" {
			reasons = append(reasons, name+": "+lay.Reason)
		}
	}

	out := models.Layer{
		State:    worst,
		Metrics:  mergedMetrics,
		Evidence: mergedEvidence,
	}
	if worst == models.StateUngraded && len(reasons) > 0 {
		out.Reason = joinSemi(reasons)
	}
	return out
}

// ---- internal helpers ----

func ifElse[T any](cond bool, a, b T) T {
	if cond {
		return a
	}
	return b
}

func asInt(v any) int {
	switch x := v.(type) {
	case int:
		return x
	case int64:
		return int(x)
	case float64:
		return int(x)
	case float32:
		return int(x)
	default:
		return 0
	}
}

func numeric(v any) (float64, bool) {
	switch x := v.(type) {
	case int:
		return float64(x), true
	case int64:
		return float64(x), true
	case float64:
		return x, true
	case float32:
		return float64(x), true
	default:
		return 0, false
	}
}

// worstMetric chooses the more-pessimistic of two metric values. For
// booleans this is OR (any adapter saying true wins). For numerics it's
// max — every red-flag-relevant numeric (counts, percentages over a floor)
// is "bigger == worse" in the current rubric. Mixed types fall back to b.
func worstMetric(a, b any) any {
	if av, ok := a.(bool); ok {
		if bv, ok := b.(bool); ok {
			return av || bv
		}
	}
	if af, aok := numeric(a); aok {
		if bf, bok := numeric(b); bok {
			if bf > af {
				return b
			}
			return a
		}
	}
	return b
}

func ftoa(n int) string {
	// Small fixed-allocation integer-to-decimal — avoids pulling in strconv
	// for one call site. Behavior identical to strconv.Itoa for our range.
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}

func joinSemi(parts []string) string {
	out := ""
	for i, p := range parts {
		if i > 0 {
			out += "; "
		}
		out += p
	}
	return out
}
