// Package githubadapter scores the Change layer from a GitHub PR.
// Fixture mode (fixture_dir set) reads samples/fixtures/github/<id>.json so
// CI and demos run hermetically. Live mode is reserved for v0.2 — the
// GitHub API call is stubbed but exits UNGRADED with a clear reason.
package githubadapter

import (
	"context"
	"fmt"

	"github.com/assert-iq/qi-signal-aggregator/internal/adapters"
	"github.com/assert-iq/qi-signal-aggregator/internal/adapters/adapterutil"
	"github.com/assert-iq/qi-signal-aggregator/internal/models"
)

func init() {
	adapters.Register("github", New)
}

type Adapter struct {
	settings map[string]any
}

func New(settings map[string]any) (adapters.Adapter, error) {
	return &Adapter{settings: settings}, nil
}

func (a *Adapter) Name() string             { return "github" }
func (a *Adapter) Kind() adapters.LayerKind { return adapters.KindChange }

// fixturePR matches the on-disk shape under samples/fixtures/github/*.json.
type fixturePR struct {
	Number               int      `json:"number"`
	Title                string   `json:"title"`
	ChangedFiles         int      `json:"changed_files"`
	Additions            int      `json:"additions"`
	Deletions            int      `json:"deletions"`
	ServicesTouched      []string `json:"services_touched"`
	LateBreakingChange   bool     `json:"late_breaking_change"`
	TouchesSensitivePath bool     `json:"touches_sensitive_path"`
}

func (a *Adapter) Fetch(_ context.Context, fc models.FetchContext) (models.Layer, error) {
	var pr fixturePR
	used, err := adapterutil.LoadFixture(a.settings, fc.Identifier, &pr)
	if err != nil {
		return models.Layer{State: models.StateUngraded, Reason: err.Error()}, err
	}
	if !used {
		return models.Layer{
			State:  models.StateUngraded,
			Reason: "github live mode not implemented in v0.1; configure fixture_dir for offline runs",
		}, nil
	}

	churn := pr.Additions + pr.Deletions
	servicesTouched := len(pr.ServicesTouched)

	weak := false
	reasons := []string{}
	if churn >= 200 {
		weak = true
		reasons = append(reasons, fmt.Sprintf("churn=%d ≥ 200", churn))
	}
	if pr.ChangedFiles > 10 {
		weak = true
		reasons = append(reasons, fmt.Sprintf("files_changed=%d > 10", pr.ChangedFiles))
	}
	if pr.LateBreakingChange {
		weak = true
		reasons = append(reasons, "late-breaking change detected")
	}
	if pr.TouchesSensitivePath {
		weak = true
		reasons = append(reasons, "touches sensitive path")
	}
	if servicesTouched >= 2 {
		weak = true
		reasons = append(reasons, fmt.Sprintf("services_touched=%d ≥ 2", servicesTouched))
	}

	lateChanges := 0
	if pr.LateBreakingChange {
		lateChanges = 1
	}

	state := models.StateStrong
	reason := ""
	if weak {
		state = models.StateWeak
		reason = joinSemi(reasons)
	}

	return models.Layer{
		State:  state,
		Reason: reason,
		Metrics: map[string]any{
			"churn":            churn,
			"files_changed":    pr.ChangedFiles,
			"late_changes":     lateChanges,
			"sensitive_path":   pr.TouchesSensitivePath,
			"services_touched": servicesTouched,
		},
		Evidence: []models.Evidence{{
			Source: "github (fixture)",
			Value:  fmt.Sprintf("PR #%d (%d changed files, +%d/-%d)", pr.Number, pr.ChangedFiles, pr.Additions, pr.Deletions),
		}},
	}, nil
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
