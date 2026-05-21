// Package adoboards scores the Outcome layer from Azure DevOps work items
// (bugs / escaped defects).
//
// Fixture mode reads <fixture_dir>/<id>.json matching the real ADO
// `_apis/wit/workitems?ids=...` response shape:
//
//   {
//     "value": [
//       { "id": 1234,
//         "fields": {
//           "System.WorkItemType": "Bug",
//           "System.Title": "...",
//           "Microsoft.VSTS.Common.Severity": "1 - Critical",
//           "Microsoft.VSTS.Common.Priority": 1
//         }
//       }
//     ]
//   }
//
// Live mode executes a WIQL query (template from settings.wiql, with {id}
// substituted from FetchContext.Identifier) to find related bugs, then
// fetches their fields. PAT comes from secrets_env (default ADO_TOKEN).
//
// Canonical Outcome-layer metrics (escapes_total, escapes_critical) match
// the jira adapter so red-flag detection is identical.
package adoboards

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/assert-iq/qi-signal-aggregator/internal/adapters"
	"github.com/assert-iq/qi-signal-aggregator/internal/adapters/adapterutil"
	"github.com/assert-iq/qi-signal-aggregator/internal/models"
)

func init() {
	adapters.Register("ado_boards", New)
}

type Adapter struct {
	settings map[string]any
}

func New(settings map[string]any) (adapters.Adapter, error) {
	return &Adapter{settings: settings}, nil
}

func (a *Adapter) Name() string             { return "ado_boards" }
func (a *Adapter) Kind() adapters.LayerKind { return adapters.KindOutcome }

type workItem struct {
	ID     int            `json:"id"`
	Fields map[string]any `json:"fields"`
}

type wiResponse struct {
	Value []workItem `json:"value"`
}

func (a *Adapter) Fetch(ctx context.Context, fc models.FetchContext) (models.Layer, error) {
	var resp wiResponse
	used, err := adapterutil.LoadFixture(a.settings, fc.Identifier, &resp)
	if err != nil {
		return models.Layer{State: models.StateUngraded, Reason: err.Error()}, err
	}
	if !used {
		live, lerr := a.fetchLive(ctx, fc)
		if lerr != nil {
			return models.Layer{State: models.StateUngraded, Reason: lerr.Error()}, nil
		}
		resp = live
	}

	escapes := 0
	critical := 0
	for _, wi := range resp.Value {
		escapes++
		if isCritical(wi.Fields) {
			critical++
		}
	}

	state := models.StateStrong
	reason := ""
	if critical > 0 {
		state = models.StateWeak
		reason = fmt.Sprintf("%d critical-severity escaped defect(s)", critical)
	}

	src := "ado_boards (live)"
	if used {
		src = "ado_boards (fixture)"
	}
	return models.Layer{
		State:  state,
		Reason: reason,
		Metrics: map[string]any{
			"escapes_total":    escapes,
			"escapes_critical": critical,
		},
		Evidence: []models.Evidence{{
			Source: src,
			Value:  fmt.Sprintf("%d escape(s); %d at critical severity", escapes, critical),
		}},
	}, nil
}

// isCritical returns true when an ADO bug should count as a critical escape.
// Heuristic mirrors how teams actually triage in ADO: Severity field set to
// 1 / Critical OR Priority field = 1.
func isCritical(fields map[string]any) bool {
	sev := strings.ToLower(fmt.Sprint(fields["Microsoft.VSTS.Common.Severity"]))
	if strings.HasPrefix(sev, "1") || strings.Contains(sev, "critical") {
		return true
	}
	switch p := fields["Microsoft.VSTS.Common.Priority"].(type) {
	case float64:
		if p == 1 {
			return true
		}
	case int:
		if p == 1 {
			return true
		}
	case string:
		if strings.TrimSpace(p) == "1" {
			return true
		}
	}
	return false
}

// --- live mode -------------------------------------------------------------

type wiqlRequest struct {
	Query string `json:"query"`
}

type wiqlResponse struct {
	WorkItems []struct {
		ID int `json:"id"`
	} `json:"workItems"`
}

func (a *Adapter) fetchLive(ctx context.Context, fc models.FetchContext) (wiResponse, error) {
	org := adapterutil.String(a.settings, "org", "")
	project := adapterutil.String(a.settings, "project", "")
	tokenKey := adapterutil.String(a.settings, "secret_key", "ado_token")
	wiql := adapterutil.String(a.settings, "wiql", "")
	if org == "" || project == "" || wiql == "" {
		return wiResponse{}, fmt.Errorf("ado_boards: org, project, and wiql must be set in adapter_settings for live mode")
	}
	pat := fc.Secrets[tokenKey]
	if pat == "" {
		return wiResponse{}, fmt.Errorf("ado_boards: secret %q not resolved (live mode requires a PAT)", tokenKey)
	}

	query := strings.ReplaceAll(wiql, "{id}", fc.Identifier)
	client := &http.Client{Timeout: 15 * time.Second}
	auth := "Basic " + base64.StdEncoding.EncodeToString([]byte(":"+pat))

	// 1. WIQL search to get matching work item IDs.
	body, _ := json.Marshal(wiqlRequest{Query: query})
	wiqlURL := fmt.Sprintf("https://dev.azure.com/%s/%s/_apis/wit/wiql?api-version=7.1", org, project)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, wiqlURL, bytes.NewReader(body))
	if err != nil {
		return wiResponse{}, err
	}
	req.Header.Set("Authorization", auth)
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return wiResponse{}, fmt.Errorf("ado_boards: wiql: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return wiResponse{}, fmt.Errorf("ado_boards: wiql HTTP %d", resp.StatusCode)
	}
	var wresp wiqlResponse
	if err := json.NewDecoder(resp.Body).Decode(&wresp); err != nil {
		return wiResponse{}, fmt.Errorf("ado_boards: wiql decode: %w", err)
	}
	if len(wresp.WorkItems) == 0 {
		return wiResponse{}, nil
	}

	// 2. Batch fetch fields for those IDs.
	ids := make([]string, 0, len(wresp.WorkItems))
	for _, w := range wresp.WorkItems {
		ids = append(ids, strconv.Itoa(w.ID))
	}
	fieldsURL := fmt.Sprintf(
		"https://dev.azure.com/%s/%s/_apis/wit/workitems?ids=%s&fields=System.Title,System.WorkItemType,Microsoft.VSTS.Common.Severity,Microsoft.VSTS.Common.Priority&api-version=7.1",
		org, project, strings.Join(ids, ","))
	req2, err := http.NewRequestWithContext(ctx, http.MethodGet, fieldsURL, nil)
	if err != nil {
		return wiResponse{}, err
	}
	req2.Header.Set("Authorization", auth)
	req2.Header.Set("Accept", "application/json")
	resp2, err := client.Do(req2)
	if err != nil {
		return wiResponse{}, fmt.Errorf("ado_boards: workitems: %w", err)
	}
	defer resp2.Body.Close()
	if resp2.StatusCode >= 400 {
		return wiResponse{}, fmt.Errorf("ado_boards: workitems HTTP %d", resp2.StatusCode)
	}
	var out wiResponse
	if err := json.NewDecoder(resp2.Body).Decode(&out); err != nil {
		return wiResponse{}, fmt.Errorf("ado_boards: workitems decode: %w", err)
	}
	return out, nil
}
