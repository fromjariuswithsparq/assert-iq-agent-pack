// Package jira scores Outcome from escaped-defect history in Jira.
package jira

import (
	"context"
	"fmt"
	"strings"

	"github.com/assert-iq/qi-signal-aggregator/internal/adapters"
	"github.com/assert-iq/qi-signal-aggregator/internal/adapters/adapterutil"
	"github.com/assert-iq/qi-signal-aggregator/internal/models"
)

func init() {
	adapters.Register("jira", New)
}

type Adapter struct {
	settings map[string]any
}

func New(settings map[string]any) (adapters.Adapter, error) {
	return &Adapter{settings: settings}, nil
}

func (a *Adapter) Name() string             { return "jira" }
func (a *Adapter) Kind() adapters.LayerKind { return adapters.KindOutcome }

// jiraIssue is a tiny shape that works for both fixtures and the real
// /rest/api/3/search endpoint (where issue.fields.priority.name lives).
type jiraIssue struct {
	Key    string `json:"key"`
	Fields struct {
		Summary  string `json:"summary"`
		Priority struct {
			Name string `json:"name"`
		} `json:"priority"`
		IssueType struct {
			Name string `json:"name"`
		} `json:"issuetype"`
	} `json:"fields"`
}

type jiraResponse struct {
	Issues []jiraIssue `json:"issues"`
}

var criticalPriorities = map[string]bool{
	"p1":      true,
	"p2":      true,
	"highest": true,
	"high":    true,
	"blocker": true,
	"critical": true,
}

func (a *Adapter) Fetch(_ context.Context, fc models.FetchContext) (models.Layer, error) {
	var resp jiraResponse
	used, err := adapterutil.LoadFixture(a.settings, fc.Identifier, &resp)
	if err != nil {
		return models.Layer{State: models.StateUngraded, Reason: err.Error()}, err
	}
	if !used {
		if _, ok := fc.Secrets["jira_token"]; !ok {
			return models.Layer{
				State:  models.StateUngraded,
				Reason: "jira: no fixture_dir set and JIRA_TOKEN not exported",
			}, nil
		}
		return models.Layer{
			State:  models.StateUngraded,
			Reason: "jira live mode not implemented in v0.1; configure fixture_dir for offline runs",
		}, nil
	}

	escapes := 0
	critical := 0
	for _, iss := range resp.Issues {
		escapes++
		p := strings.ToLower(iss.Fields.Priority.Name)
		if criticalPriorities[p] {
			critical++
		}
	}

	state := models.StateStrong
	reason := ""
	if critical > 0 {
		state = models.StateWeak
		reason = fmt.Sprintf("%d critical-priority escaped defect(s)", critical)
	}

	return models.Layer{
		State:  state,
		Reason: reason,
		Metrics: map[string]any{
			"escapes_total":    escapes,
			"escapes_critical": critical,
		},
		Evidence: []models.Evidence{{
			Source: "jira (fixture)",
			Value:  fmt.Sprintf("%d escape(s); %d at critical priority", escapes, critical),
		}},
	}, nil
}
