package scoring_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"testing"

	"github.com/assert-iq/qi-signal-aggregator/internal/models"
	"github.com/assert-iq/qi-signal-aggregator/internal/scoring"
)

// goldenScenario is the wire format produced by the Python reference run and
// stored in mcp/qi-signal-aggregator/testdata/golden/*.json. The Go scoring
// engine must reproduce the "expected" block exactly for every scenario.
type goldenScenario struct {
	Scenario     string              `json:"scenario"`
	Scope        models.Scope        `json:"scope"`
	MaturityTier models.MaturityTier `json:"maturity_tier"`
	Input        struct {
		Change     goldenLayer `json:"change"`
		Protection goldenLayer `json:"protection"`
		Trust      goldenLayer `json:"trust"`
		Outcome    goldenLayer `json:"outcome"`
	} `json:"input"`
	Expected struct {
		VerdictBand        models.VerdictBand `json:"verdict_band"`
		MitigationRequired bool               `json:"mitigation_required"`
		Rationale          string             `json:"rationale"`
		TierCapped         bool               `json:"tier_capped"`
		RedFlags           []string           `json:"red_flags"`
	} `json:"expected"`
}

type goldenLayer struct {
	State   models.LayerState `json:"state"`
	Metrics map[string]any    `json:"metrics"`
}

func (g goldenLayer) toModel() models.Layer {
	return models.Layer{State: g.State, Metrics: g.Metrics}
}

// TestScoringParity walks every JSON file under testdata/golden/ and confirms
// the Go scoring engine matches the Python reference output byte-for-byte
// on the fields the schema treats as decision-grade (band, mitigation,
// tier_capped, red_flag IDs). Rationale strings are checked too because
// downstream consumers display them; if you change the wording in scoring.go
// you must regenerate the goldens deliberately.
func TestScoringParity(t *testing.T) {
	files, err := filepath.Glob("../../testdata/golden/*.json")
	if err != nil {
		t.Fatalf("glob: %v", err)
	}
	if len(files) == 0 {
		t.Fatal("no golden files found under testdata/golden/")
	}

	for _, f := range files {
		f := f
		t.Run(filepath.Base(f), func(t *testing.T) {
			raw, err := os.ReadFile(f)
			if err != nil {
				t.Fatalf("read: %v", err)
			}
			var g goldenScenario
			if err := json.Unmarshal(raw, &g); err != nil {
				t.Fatalf("unmarshal: %v", err)
			}

			layers := models.Layers{
				Change:     g.Input.Change.toModel(),
				Protection: g.Input.Protection.toModel(),
				Trust:      g.Input.Trust.toModel(),
				Outcome:    g.Input.Outcome.toModel(),
			}

			flags := scoring.DetectRedFlags(layers)
			gotFlagIDs := make([]string, 0, len(flags))
			for _, fl := range flags {
				gotFlagIDs = append(gotFlagIDs, fl.ID)
			}
			sort.Strings(gotFlagIDs)

			wantFlagIDs := append([]string(nil), g.Expected.RedFlags...)
			sort.Strings(wantFlagIDs)

			if !equalStrings(gotFlagIDs, wantFlagIDs) {
				t.Errorf("red_flags mismatch:\n  got:  %v\n  want: %v", gotFlagIDs, wantFlagIDs)
			}

			v := scoring.ComputeVerdict(layers, g.Scope, g.MaturityTier, flags)

			if v.Band != g.Expected.VerdictBand {
				t.Errorf("band: got %q want %q", v.Band, g.Expected.VerdictBand)
			}
			if v.MitigationRequired != g.Expected.MitigationRequired {
				t.Errorf("mitigation_required: got %v want %v", v.MitigationRequired, g.Expected.MitigationRequired)
			}
			if v.TierCapped != g.Expected.TierCapped {
				t.Errorf("tier_capped: got %v want %v", v.TierCapped, g.Expected.TierCapped)
			}
			if v.Rationale != g.Expected.Rationale {
				t.Errorf("rationale drift:\n  got:  %q\n  want: %q", v.Rationale, g.Expected.Rationale)
			}
		})
	}
}

func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
