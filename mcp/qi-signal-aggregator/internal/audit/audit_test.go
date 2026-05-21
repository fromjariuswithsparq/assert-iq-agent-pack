package audit

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/assert-iq/qi-signal-aggregator/internal/models"
)

// TestAuditRedactsRawEvidence is the security gate for the audit subsystem:
// no matter what an adapter passes in as evidence value (including secrets,
// tokens, or PII), the audit log must NEVER contain that raw value. Only
// digests escape to disk.
func TestAuditRedactsRawEvidence(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "audit.jsonl")
	r, err := New(path)
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	secret := "ghp_super_secret_token_DO_NOT_LEAK_42"
	layer := models.Layer{
		State: models.StateStrong,
		Evidence: []models.Evidence{
			{Source: "test", Value: secret},
		},
	}
	r.RecordAdapterCall("github", models.FetchContext{
		Scope:      models.ScopePR,
		Identifier: "PR-001",
	}, layer, nil)

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if strings.Contains(string(raw), secret) {
		t.Fatalf("audit log leaked raw evidence value")
	}

	// And the line must parse as JSON with an evidence array of digest strings.
	var rec map[string]any
	if err := json.Unmarshal(raw[:len(raw)-1], &rec); err != nil {
		t.Fatalf("audit line not valid JSON: %v", err)
	}
	if _, ok := rec["evidence"].([]any); !ok {
		t.Fatalf("expected evidence array, got %T", rec["evidence"])
	}
}
