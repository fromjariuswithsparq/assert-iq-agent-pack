// Package traceability scores Protection by counting how many source files
// under scan_root carry a "qi-trace:" marker linking them to a work item.
package traceability

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/assert-iq/qi-signal-aggregator/internal/adapters"
	"github.com/assert-iq/qi-signal-aggregator/internal/adapters/adapterutil"
	"github.com/assert-iq/qi-signal-aggregator/internal/models"
)

func init() {
	adapters.Register("qi_traceability_scan", New)
}

type Adapter struct {
	scanRoot string
	exts     map[string]bool
}

func New(settings map[string]any) (adapters.Adapter, error) {
	root := adapterutil.String(settings, "scan_root", ".")
	// Default to a sensible polyglot set; users can override via "extensions"
	// in adapter_settings if they have an exotic stack.
	defaults := []string{".cs", ".py", ".ts", ".tsx", ".js", ".jsx", ".java", ".go", ".rs", ".kt", ".swift", ".rb"}
	exts := map[string]bool{}
	for _, e := range defaults {
		exts[e] = true
	}
	return &Adapter{scanRoot: root, exts: exts}, nil
}

func (a *Adapter) Name() string             { return "qi_traceability_scan" }
func (a *Adapter) Kind() adapters.LayerKind { return adapters.KindProtection }

var traceRE = regexp.MustCompile(`(?i)qi-trace\s*:`)

func (a *Adapter) Fetch(_ context.Context, _ models.FetchContext) (models.Layer, error) {
	if _, err := os.Stat(a.scanRoot); err != nil {
		return models.Layer{
			State:  models.StateUngraded,
			Reason: fmt.Sprintf("traceability: scan_root %q not accessible", a.scanRoot),
		}, nil
	}

	scanned := 0
	traced := 0

	err := filepath.WalkDir(a.scanRoot, func(p string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return nil // tolerate unreadable subtrees
		}
		if d.IsDir() {
			// Skip vendor / VCS / cache directories that are not source.
			name := d.Name()
			if name == ".git" || name == "node_modules" || name == "vendor" || name == "dist" || name == "build" || name == ".cache" {
				return filepath.SkipDir
			}
			return nil
		}
		ext := strings.ToLower(filepath.Ext(p))
		if !a.exts[ext] {
			return nil
		}
		raw, err := os.ReadFile(p)
		if err != nil {
			return nil
		}
		scanned++
		if traceRE.Match(raw) {
			traced++
		}
		return nil
	})
	if err != nil {
		return models.Layer{State: models.StateUngraded, Reason: err.Error()}, err
	}

	tracedPct := 0.0
	if scanned > 0 {
		tracedPct = (float64(traced) / float64(scanned)) * 100
	}

	state := models.StateWeak
	if scanned == 0 {
		state = models.StateUngraded
	} else if tracedPct >= 80 {
		state = models.StateStrong
	}

	return models.Layer{
		State: state,
		Metrics: map[string]any{
			"traced_pct":    tracedPct,
			"files_scanned": scanned,
			"files_traced":  traced,
		},
		Evidence: []models.Evidence{{
			Source: "qi_traceability_scan",
			Value:  fmt.Sprintf("%d of %d source files carry qi-trace marker (%.0f%%)", traced, scanned, tracedPct),
			Link:   a.scanRoot,
		}},
	}, nil
}
