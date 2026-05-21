// Package coverage scores the Protection layer from a Cobertura-style XML
// coverage report.
package coverage

import (
	"context"
	"encoding/xml"
	"fmt"
	"os"

	"github.com/assert-iq/qi-signal-aggregator/internal/adapters"
	"github.com/assert-iq/qi-signal-aggregator/internal/adapters/adapterutil"
	"github.com/assert-iq/qi-signal-aggregator/internal/models"
)

func init() {
	adapters.Register("coverage_xml", New)
}

type Adapter struct {
	path string
}

func New(settings map[string]any) (adapters.Adapter, error) {
	p := adapterutil.String(settings, "path", "coverage.xml")
	return &Adapter{path: p}, nil
}

func (a *Adapter) Name() string             { return "coverage_xml" }
func (a *Adapter) Kind() adapters.LayerKind { return adapters.KindProtection }

// cobertura captures the line-rate attribute on the root element only.
type cobertura struct {
	XMLName  xml.Name `xml:"coverage"`
	LineRate float64  `xml:"line-rate,attr"`
}

func (a *Adapter) Fetch(_ context.Context, _ models.FetchContext) (models.Layer, error) {
	raw, err := os.ReadFile(a.path)
	if err != nil {
		return models.Layer{
			State:  models.StateUngraded,
			Reason: fmt.Sprintf("coverage_xml: cannot read %q: %v", a.path, err),
		}, nil
	}
	var c cobertura
	if err := xml.Unmarshal(raw, &c); err != nil {
		return models.Layer{
			State:  models.StateUngraded,
			Reason: fmt.Sprintf("coverage_xml: parse %q: %v", a.path, err),
		}, nil
	}

	pct := c.LineRate * 100
	state := models.StateWeak
	if pct >= 80 {
		state = models.StateStrong
	}

	return models.Layer{
		State: state,
		Metrics: map[string]any{
			"coverage_pct": pct,
		},
		Evidence: []models.Evidence{{
			Source: "coverage_xml",
			Value:  fmt.Sprintf("line-rate=%.2f%%", pct),
			Link:   a.path,
		}},
	}, nil
}
