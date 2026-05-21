// Package models contains the data structures that mirror signal-schema.json v0.2.0.
// All structs use JSON tags so the wire format is byte-for-byte stable.
package models

// SchemaVersion is the version of .assert-iq/signal-schema.json this code emits.
const SchemaVersion = "0.2.0"

// LayerState is one of the three states a QI signal layer can occupy.
// STRONG = evidence is decision-grade.
// WEAK   = evidence is present but signals a problem.
// UNGRADED = no adapter could produce evidence (caps verdict at AMBER/GO_WITH_MITIGATION).
type LayerState string

const (
	StateStrong   LayerState = "STRONG"
	StateWeak     LayerState = "WEAK"
	StateUngraded LayerState = "UNGRADED"
)

// VerdictBand carries either a PR-scope verdict (GREEN/AMBER/RED) or a
// release-scope verdict (GO/GO_WITH_MITIGATION/HOLD). The choice depends on
// the requested scope, not on the value space itself.
type VerdictBand string

const (
	BandGreen            VerdictBand = "GREEN"
	BandAmber            VerdictBand = "AMBER"
	BandRed              VerdictBand = "RED"
	BandGo               VerdictBand = "GO"
	BandGoWithMitigation VerdictBand = "GO_WITH_MITIGATION"
	BandHold             VerdictBand = "HOLD"
)

// Scope is the kind of artifact being assessed.
type Scope string

const (
	ScopePR      Scope = "pr"
	ScopeRelease Scope = "release"
	ScopeMerge   Scope = "merge"
	ScopeCommit  Scope = "commit"
)

// MaturityTier mirrors .assert-iq/maturity-profile.md. early-tier callers
// have their optimistic verdicts capped at AMBER/GO_WITH_MITIGATION.
type MaturityTier string

const (
	TierEarly  MaturityTier = "early"
	TierMid    MaturityTier = "mid"
	TierHigher MaturityTier = "higher"
)

// Evidence is one citation backing a Layer's state.
// Value is intentionally `any` so adapters can carry numbers, strings, or
// small JSON objects; consumers should treat it as opaque except for display.
type Evidence struct {
	Source string  `json:"source"`
	Value  any     `json:"value"`
	Link   string  `json:"link,omitempty"`
	Weight float64 `json:"weight,omitempty"`
}

// Layer is one of the four QI signal layers (Change, Protection, Trust, Outcome).
type Layer struct {
	State    LayerState     `json:"state"`
	Reason   string         `json:"reason,omitempty"`
	Metrics  map[string]any `json:"metrics,omitempty"`
	Evidence []Evidence     `json:"evidence,omitempty"`
}

// Layers groups the four QI layers in canonical order.
type Layers struct {
	Change     Layer `json:"change"`
	Protection Layer `json:"protection"`
	Trust      Layer `json:"trust"`
	Outcome    Layer `json:"outcome"`
}

// RedFlag is a structured warning surfaced by scoring.DetectRedFlags.
type RedFlag struct {
	ID     string `json:"id"`
	Signal string `json:"signal"`
	Impact string `json:"impact"`
}

// Verdict is the synthesized decision.
type Verdict struct {
	Band                VerdictBand `json:"band"`
	MitigationRequired  bool        `json:"mitigation_required"`
	Rationale           string      `json:"rationale,omitempty"`
	TierCapped          bool        `json:"tier_capped,omitempty"`
}

// SignalPayload is the top-level emit object. Conforms to signal-schema.json v0.2.0.
type SignalPayload struct {
	SchemaVersion      string       `json:"schema_version"`
	RunID              string       `json:"run_id"`
	CommitSHA          string       `json:"commit_sha"`
	Branch             string       `json:"branch,omitempty"`
	PRID               string       `json:"pr_id,omitempty"`
	Scope              Scope        `json:"scope"`
	Identifier         string       `json:"identifier"`
	MaturityTier       MaturityTier `json:"maturity_tier"`
	PartialSignalMode  bool         `json:"partial_signal_mode"`
	GeneratedAt        string       `json:"generated_at"`
	Layers             Layers       `json:"layers"`
	RedFlags           []RedFlag    `json:"red_flags"`
	Verdict            Verdict      `json:"verdict"`
}

// FetchContext is passed to every adapter. Adapters must not mutate it.
type FetchContext struct {
	Scope          Scope
	Identifier     string
	LookbackDays   int
	RepoRoot       string
	AdapterConfig  map[string]map[string]any
	Secrets        map[string]string
}
