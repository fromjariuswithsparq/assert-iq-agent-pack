// Package junit scores Trust by aggregating JUnit-style XML files across a glob.
package junit

import (
	"context"
	"encoding/xml"
	"fmt"
	"os"
	"path/filepath"

	"github.com/assert-iq/qi-signal-aggregator/internal/adapters"
	"github.com/assert-iq/qi-signal-aggregator/internal/adapters/adapterutil"
	"github.com/assert-iq/qi-signal-aggregator/internal/models"
)

func init() {
	adapters.Register("junit_glob", New)
}

type Adapter struct {
	glob string
}

func New(settings map[string]any) (adapters.Adapter, error) {
	g := adapterutil.String(settings, "glob", "junit/*.xml")
	return &Adapter{glob: g}, nil
}

func (a *Adapter) Name() string             { return "junit_glob" }
func (a *Adapter) Kind() adapters.LayerKind { return adapters.KindTrust }

// Minimal subset of JUnit XML we care about: testsuite + testcase nodes,
// with optional failure/error/skipped child elements.
type testsuite struct {
	XMLName   xml.Name   `xml:"testsuite"`
	Tests     int        `xml:"tests,attr"`
	Failures  int        `xml:"failures,attr"`
	Errors    int        `xml:"errors,attr"`
	Skipped   int        `xml:"skipped,attr"`
	TestCases []testcase `xml:"testcase"`
}

type testcase struct {
	Name    string  `xml:"name,attr"`
	Failure *struct{} `xml:"failure"`
	Error   *struct{} `xml:"error"`
	Skipped *struct{} `xml:"skipped"`
}

type testsuites struct {
	XMLName    xml.Name    `xml:"testsuites"`
	Testsuites []testsuite `xml:"testsuite"`
}

func (a *Adapter) Fetch(_ context.Context, _ models.FetchContext) (models.Layer, error) {
	matches, err := filepath.Glob(a.glob)
	if err != nil {
		return models.Layer{State: models.StateUngraded, Reason: err.Error()}, err
	}
	if len(matches) == 0 {
		return models.Layer{
			State:  models.StateUngraded,
			Reason: fmt.Sprintf("junit: no files matched %q", a.glob),
		}, nil
	}

	// We treat the same testcase name appearing across multiple runs as the
	// flake signal: if a test passes in some runs and fails in others, it's
	// flaky. Counted via per-name failure ratio.
	type result struct{ pass, fail int }
	perTest := map[string]*result{}
	blocked := 0
	totalRuns := 0

	parseSuite := func(s testsuite) {
		blocked += s.Skipped
		for _, tc := range s.TestCases {
			totalRuns++
			r, ok := perTest[tc.Name]
			if !ok {
				r = &result{}
				perTest[tc.Name] = r
			}
			if tc.Failure != nil || tc.Error != nil {
				r.fail++
			} else if tc.Skipped == nil {
				r.pass++
			}
		}
	}

	for _, m := range matches {
		raw, err := os.ReadFile(m)
		if err != nil {
			continue
		}
		// Try testsuites wrapper first, fall back to bare testsuite.
		var wrap testsuites
		if err := xml.Unmarshal(raw, &wrap); err == nil && len(wrap.Testsuites) > 0 {
			for _, s := range wrap.Testsuites {
				parseSuite(s)
			}
			continue
		}
		var s testsuite
		if err := xml.Unmarshal(raw, &s); err == nil {
			parseSuite(s)
		}
	}

	flaky := 0
	for _, r := range perTest {
		// A test is flaky if it has BOTH pass and fail records in the window.
		if r.pass > 0 && r.fail > 0 {
			flaky++
		}
	}

	flakyPct := 0.0
	if len(perTest) > 0 {
		flakyPct = (float64(flaky) / float64(len(perTest))) * 100
	}

	state := models.StateStrong
	reasons := []string{}
	if flakyPct > 5 {
		state = models.StateWeak
		reasons = append(reasons, fmt.Sprintf("flaky_pct=%.1f%% > 5%%", flakyPct))
	}
	if blocked > 0 {
		state = models.StateWeak
		reasons = append(reasons, fmt.Sprintf("blocked_count=%d", blocked))
	}

	out := models.Layer{
		State: state,
		Metrics: map[string]any{
			"flaky_pct":     flakyPct,
			"flaky_count":   flaky,
			"blocked_count": blocked,
			"tests_seen":    len(perTest),
			"total_runs":    totalRuns,
		},
		Evidence: []models.Evidence{{
			Source: "junit_glob",
			Value:  fmt.Sprintf("%d tests across %d runs; %d flaky; %d blocked", len(perTest), totalRuns, flaky, blocked),
			Link:   a.glob,
		}},
	}
	if len(reasons) > 0 {
		out.Reason = joinSemi(reasons)
	}
	return out, nil
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
