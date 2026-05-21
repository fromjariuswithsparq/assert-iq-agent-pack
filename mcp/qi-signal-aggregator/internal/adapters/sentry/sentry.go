// Package sentry scores Outcome from Sentry unresolved-issue counts.
package sentry

import (
	"context"
	"fmt"

	"github.com/assert-iq/qi-signal-aggregator/internal/adapters"
	"github.com/assert-iq/qi-signal-aggregator/internal/adapters/adapterutil"
	"github.com/assert-iq/qi-signal-aggregator/internal/models"
)

func init() {
	adapters.Register("sentry", New)
}

type Adapter struct {
	settings map[string]any
}

func New(settings map[string]any) (adapters.Adapter, error) {
	return &Adapter{settings: settings}, nil
}

func (a *Adapter) Name() string             { return "sentry" }
func (a *Adapter) Kind() adapters.LayerKind { return adapters.KindOutcome }

// Fixture / live response shape: a list of issues with a level field. We
// only count fatal/error levels as decision-grade; warnings do not gate.
type sentryIssue struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Level     string `json:"level"`
	Status    string `json:"status"`
	Component string `json:"component,omitempty"`
}

type sentryResponse struct {
	Issues []sentryIssue `json:"issues"`
}

func (a *Adapter) Fetch(_ context.Context, fc models.FetchContext) (models.Layer, error) {
	var resp sentryResponse
	used, err := adapterutil.LoadFixture(a.settings, fc.Identifier, &resp)
	if err != nil {
		return models.Layer{State: models.StateUngraded, Reason: err.Error()}, err
	}
	if !used {
		// Live mode requires a token; absence -> UNGRADED (never fabricate).
		if _, ok := fc.Secrets["sentry_token"]; !ok {
			return models.Layer{
				State:  models.StateUngraded,
				Reason: "sentry: no fixture_dir set and SENTRY_TOKEN not exported",
			}, nil
		}
		return models.Layer{
			State:  models.StateUngraded,
			Reason: "sentry live mode not implemented in v0.1; configure fixture_dir for offline runs",
		}, nil
	}

	unresolvedCritical := 0
	for _, iss := range resp.Issues {
		if iss.Status != "" && iss.Status != "unresolved" {
			continue
		}
		switch iss.Level {
		case "fatal", "error":
			unresolvedCritical++
		}
	}

	state := models.StateStrong
	reason := ""
	if unresolvedCritical > 0 {
		state = models.StateWeak
		reason = fmt.Sprintf("%d unresolved fatal/error issue(s) in Sentry", unresolvedCritical)
	}

	return models.Layer{
		State:  state,
		Reason: reason,
		Metrics: map[string]any{
			"unresolved_p1":    unresolvedCritical,
			"issues_total":     len(resp.Issues),
			// "active_critical_incident" mirrors the Python red-flag wiring.
			"active_critical_incident": unresolvedCritical > 0,
		},
		Evidence: []models.Evidence{{
			Source: "sentry (fixture)",
			Value:  fmt.Sprintf("%d issue(s); %d unresolved fatal/error", len(resp.Issues), unresolvedCritical),
		}},
	}, nil
}
