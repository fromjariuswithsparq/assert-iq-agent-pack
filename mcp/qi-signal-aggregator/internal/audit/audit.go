// Package audit appends decision-grade events to a JSONL log. Raw evidence
// values are never written — only SHA256 digests — so the audit trail can
// be shared without leaking PII, tokens, or proprietary code paths.
package audit

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/assert-iq/qi-signal-aggregator/internal/models"
)

type Recorder struct {
	mu   sync.Mutex
	path string
}

func New(path string) (*Recorder, error) {
	if path == "" {
		return &Recorder{}, nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	return &Recorder{path: path}, nil
}

func (r *Recorder) write(event map[string]any) {
	if r == nil || r.path == "" {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	f, err := os.OpenFile(r.path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	event["ts"] = time.Now().UTC().Format(time.RFC3339Nano)
	raw, _ := json.Marshal(event)
	_, _ = f.Write(append(raw, '\n'))
}

// RecordAdapterCall logs that an adapter ran, including digest-only evidence.
func (r *Recorder) RecordAdapterCall(adapter string, fc models.FetchContext, layer models.Layer, err error) {
	r.write(map[string]any{
		"type":       "adapter_call",
		"adapter":    adapter,
		"scope":      fc.Scope,
		"identifier": fc.Identifier,
		"state":      layer.State,
		"evidence":   digestEvidence(layer.Evidence),
		"error":      errString(err),
	})
}

// RecordDecision logs the final verdict for a scoring run.
func (r *Recorder) RecordDecision(payload models.SignalPayload) {
	r.write(map[string]any{
		"type":                "decision",
		"scope":               payload.Scope,
		"identifier":          payload.Identifier,
		"verdict_band":        payload.Verdict.Band,
		"mitigation_required": payload.Verdict.MitigationRequired,
		"tier_capped":         payload.Verdict.TierCapped,
		"red_flag_ids":        redFlagIDs(payload.RedFlags),
	})
}

// RecordOutcome captures post-merge outcome (escape detected, hotfix, etc.).
func (r *Recorder) RecordOutcome(scope models.Scope, identifier, outcome, note string) {
	r.write(map[string]any{
		"type":       "outcome",
		"scope":      scope,
		"identifier": identifier,
		"outcome":    outcome,
		"note":       note,
	})
}

func digestEvidence(ev []models.Evidence) []string {
	out := make([]string, 0, len(ev))
	for _, e := range ev {
		b, _ := json.Marshal(e.Value)
		h := sha256.Sum256(b)
		out = append(out, fmt.Sprintf("%s:%s", e.Source, hex.EncodeToString(h[:8])))
	}
	return out
}

func redFlagIDs(flags []models.RedFlag) []string {
	out := make([]string, 0, len(flags))
	for _, f := range flags {
		out = append(out, f.ID)
	}
	return out
}

func errString(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}
