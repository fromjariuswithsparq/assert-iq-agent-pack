// Package adorepos scores the Change layer from an Azure DevOps pull request.
//
// Fixture mode (fixture_dir set) reads <fixture_dir>/<id>.json with the same
// shape as the github adapter so demos and tests stay symmetric.
//
// Live mode (no fixture_dir) hits the ADO REST API:
//   GET https://dev.azure.com/{org}/{project}/_apis/git/repositories/{repo}/pullrequests/{id}?api-version=7.1
//   GET .../pullrequests/{id}/iterations/{iter}/changes?api-version=7.1
// authenticated with a PAT from settings.secrets_env (default ADO_TOKEN).
//
// All canonical Change-layer metric keys (churn, files_changed, late_changes,
// sensitive_path, services_touched) match the github adapter so red-flag
// detection in internal/scoring works identically.
package adorepos

import (
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
	adapters.Register("ado_repos", New)
}

type Adapter struct {
	settings map[string]any
}

func New(settings map[string]any) (adapters.Adapter, error) {
	return &Adapter{settings: settings}, nil
}

func (a *Adapter) Name() string             { return "ado_repos" }
func (a *Adapter) Kind() adapters.LayerKind { return adapters.KindChange }

// fixturePR mirrors the github fixture shape (same canonical fields) so a
// team migrating from github to ado can re-use their demo data.
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

func (a *Adapter) Fetch(ctx context.Context, fc models.FetchContext) (models.Layer, error) {
	var pr fixturePR
	used, err := adapterutil.LoadFixture(a.settings, fc.Identifier, &pr)
	if err != nil {
		return models.Layer{State: models.StateUngraded, Reason: err.Error()}, err
	}
	if !used {
		// Live mode.
		live, lerr := a.fetchLive(ctx, fc)
		if lerr != nil {
			return models.Layer{State: models.StateUngraded, Reason: lerr.Error()}, nil
		}
		pr = live
	}

	return scorePR(pr, used), nil
}

func scorePR(pr fixturePR, fromFixture bool) models.Layer {
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
		reason = strings.Join(reasons, "; ")
	}

	source := "ado_repos (live)"
	if fromFixture {
		source = "ado_repos (fixture)"
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
			Source: source,
			Value:  fmt.Sprintf("PR #%d (%d changed files, +%d/-%d)", pr.Number, pr.ChangedFiles, pr.Additions, pr.Deletions),
		}},
	}
}

// --- live mode -------------------------------------------------------------

type adoPR struct {
	PullRequestID int    `json:"pullRequestId"`
	Title         string `json:"title"`
	Status        string `json:"status"`
	CreatedBy     struct {
		DisplayName string `json:"displayName"`
	} `json:"createdBy"`
	CreationDate    time.Time `json:"creationDate"`
	LastMergeCommit struct {
		CommitID string `json:"commitId"`
	} `json:"lastMergeCommit"`
}

type adoIterations struct {
	Value []struct {
		ID int `json:"id"`
	} `json:"value"`
}

type adoChange struct {
	ChangeType string `json:"changeType"`
	Item       struct {
		Path string `json:"path"`
	} `json:"item"`
}

type adoChanges struct {
	ChangeEntries []adoChange `json:"changeEntries"`
}

func (a *Adapter) fetchLive(ctx context.Context, fc models.FetchContext) (fixturePR, error) {
	org := adapterutil.String(a.settings, "org", "")
	project := adapterutil.String(a.settings, "project", "")
	repo := adapterutil.String(a.settings, "repository", "")
	tokenKey := adapterutil.String(a.settings, "secret_key", "ado_token")
	if org == "" || project == "" || repo == "" {
		return fixturePR{}, fmt.Errorf("ado_repos: org, project, and repository must be set in adapter_settings for live mode")
	}
	pat := fc.Secrets[tokenKey]
	if pat == "" {
		return fixturePR{}, fmt.Errorf("ado_repos: secret %q not resolved (live mode requires a PAT)", tokenKey)
	}

	prID, err := strconv.Atoi(strings.TrimPrefix(fc.Identifier, "PR-"))
	if err != nil {
		return fixturePR{}, fmt.Errorf("ado_repos: identifier %q is not numeric (expected '123' or 'PR-123')", fc.Identifier)
	}

	base := fmt.Sprintf("https://dev.azure.com/%s/%s/_apis/git/repositories/%s/pullrequests/%d",
		org, project, repo, prID)

	client := &http.Client{Timeout: 15 * time.Second}
	auth := "Basic " + base64.StdEncoding.EncodeToString([]byte(":"+pat))

	var pr adoPR
	if err := getJSON(ctx, client, auth, base+"?api-version=7.1", &pr); err != nil {
		return fixturePR{}, fmt.Errorf("ado_repos: pr fetch: %w", err)
	}

	// Get the latest iteration so we can resolve changed files.
	var iters adoIterations
	if err := getJSON(ctx, client, auth, base+"/iterations?api-version=7.1", &iters); err != nil {
		return fixturePR{}, fmt.Errorf("ado_repos: iterations: %w", err)
	}
	latest := 1
	for _, it := range iters.Value {
		if it.ID > latest {
			latest = it.ID
		}
	}

	var changes adoChanges
	if err := getJSON(ctx, client, auth,
		fmt.Sprintf("%s/iterations/%d/changes?api-version=7.1", base, latest), &changes); err != nil {
		return fixturePR{}, fmt.Errorf("ado_repos: changes: %w", err)
	}

	// ADO doesn't return additions/deletions on this endpoint; we approximate
	// with file count. A richer implementation would diff stats per file.
	out := fixturePR{
		Number:       pr.PullRequestID,
		Title:        pr.Title,
		ChangedFiles: len(changes.ChangeEntries),
	}
	out.ServicesTouched, out.TouchesSensitivePath = classifyPaths(changes.ChangeEntries, a.settings)
	out.LateBreakingChange = isLateBreaking(pr.CreationDate, a.settings)
	return out, nil
}

func classifyPaths(entries []adoChange, settings map[string]any) (services []string, sensitive bool) {
	seen := map[string]bool{}
	sensitivePrefixes := stringList(settings, "sensitive_paths")
	serviceRoots := stringList(settings, "service_roots")

	for _, e := range entries {
		p := strings.TrimPrefix(e.Item.Path, "/")
		for _, sp := range sensitivePrefixes {
			if strings.HasPrefix(p, strings.TrimPrefix(sp, "/")) {
				sensitive = true
			}
		}
		for _, root := range serviceRoots {
			cleaned := strings.TrimPrefix(root, "/")
			if strings.HasPrefix(p, cleaned+"/") {
				parts := strings.SplitN(strings.TrimPrefix(p, cleaned+"/"), "/", 2)
				if len(parts) > 0 && parts[0] != "" && !seen[parts[0]] {
					seen[parts[0]] = true
					services = append(services, parts[0])
				}
			}
		}
	}
	return services, sensitive
}

func isLateBreaking(created time.Time, settings map[string]any) bool {
	windowHrs := adapterutil.Int(settings, "late_window_hours", 0)
	if windowHrs <= 0 || created.IsZero() {
		return false
	}
	return time.Since(created) < time.Duration(windowHrs)*time.Hour
}

func stringList(settings map[string]any, key string) []string {
	raw, ok := settings[key].([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(raw))
	for _, v := range raw {
		if s, ok := v.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

func getJSON(ctx context.Context, client *http.Client, auth, url string, dst any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", auth)
	req.Header.Set("Accept", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return fmt.Errorf("HTTP %d from %s", resp.StatusCode, url)
	}
	return json.NewDecoder(resp.Body).Decode(dst)
}
