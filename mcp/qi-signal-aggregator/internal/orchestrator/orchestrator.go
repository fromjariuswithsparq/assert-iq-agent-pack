// Package orchestrator wires config, adapters, cache, and audit together.
// It runs the four QI layers concurrently with errgroup, merging multiple
// adapters per layer via scoring.MergeLayersByKind.
package orchestrator

import (
	"context"
	"fmt"
	"path/filepath"
	"sync"
	"time"

	"github.com/assert-iq/qi-signal-aggregator/internal/adapters"
	"github.com/assert-iq/qi-signal-aggregator/internal/audit"
	"github.com/assert-iq/qi-signal-aggregator/internal/cache"
	"github.com/assert-iq/qi-signal-aggregator/internal/config"
	"github.com/assert-iq/qi-signal-aggregator/internal/hooks"
	"github.com/assert-iq/qi-signal-aggregator/internal/models"
	"github.com/assert-iq/qi-signal-aggregator/internal/scoring"
	"golang.org/x/sync/errgroup"
)

type Orchestrator struct {
	Cfg      config.AggregatorConfig
	Cache    *cache.Cache
	Audit    *audit.Recorder
	Hooks    *hooks.Bus
	registry map[string]adapters.Adapter // name -> built adapter
}

func New(cfg config.AggregatorConfig, aud *audit.Recorder, hb *hooks.Bus) (*Orchestrator, error) {
	o := &Orchestrator{
		Cfg:      cfg,
		Cache:    cache.New(cfg.CacheDir),
		Audit:    aud,
		Hooks:    hb,
		registry: map[string]adapters.Adapter{},
	}
	// Build every adapter referenced in cfg.Adapters once at startup.
	for _, names := range cfg.Adapters {
		for _, n := range names {
			if _, ok := o.registry[n]; ok {
				continue
			}
			settings := cfg.AdapterSettings[n]
			a, err := adapters.Build(n, settings)
			if err != nil {
				return nil, fmt.Errorf("build adapter %q: %w", n, err)
			}
			o.registry[n] = a
		}
	}
	return o, nil
}

// AssessLayer runs the adapters configured for a single layer kind and
// returns the merged Layer.
func (o *Orchestrator) AssessLayer(ctx context.Context, kind string, fc models.FetchContext) (models.Layer, error) {
	names := o.Cfg.Adapters[kind]
	if len(names) == 0 {
		return models.Layer{State: models.StateUngraded, Reason: "no adapters configured for " + kind}, nil
	}
	ttl := o.Cfg.CacheTTLSeconds[kind]

	var mu sync.Mutex
	byAdapter := map[string]models.Layer{}

	g, ctx := errgroup.WithContext(ctx)
	for _, name := range names {
		name := name
		g.Go(func() error {
			a, ok := o.registry[name]
			if !ok {
				return nil // unknown — skip silently, AssessAll surfaces this elsewhere
			}
			cacheKey := fmt.Sprintf("%s|%s|%s|%s", name, fc.Scope, fc.Identifier, kind)
			var cached models.Layer
			if ttl > 0 {
				if hit, _ := o.Cache.Get(cacheKey, &cached); hit {
					mu.Lock()
					byAdapter[name] = cached
					mu.Unlock()
					return nil
				}
			}
			start := time.Now()
			layer, err := a.Fetch(ctx, fc)
			_ = start
			o.Audit.RecordAdapterCall(name, fc, layer, err)
			if err == nil && ttl > 0 {
				_ = o.Cache.Put(cacheKey, layer, ttl)
			}
			mu.Lock()
			byAdapter[name] = layer
			mu.Unlock()
			return nil
		})
	}
	if err := g.Wait(); err != nil {
		return models.Layer{State: models.StateUngraded, Reason: err.Error()}, err
	}
	return scoring.MergeLayersByKind(byAdapter, kind), nil
}

// AssessAll runs all four layers concurrently and produces a full SignalPayload.
func (o *Orchestrator) AssessAll(ctx context.Context, fc models.FetchContext) (models.SignalPayload, error) {
	fc.AdapterConfig = o.Cfg.AdapterSettings
	fc.Secrets = o.Cfg.ResolveSecrets()
	if fc.RepoRoot == "" {
		fc.RepoRoot, _ = filepath.Abs(".")
	}

	var (
		layers models.Layers
		mu     sync.Mutex
	)
	g, ctx := errgroup.WithContext(ctx)

	kinds := []struct {
		name string
		set  func(models.Layer)
	}{
		{"change", func(l models.Layer) { layers.Change = l }},
		{"protection", func(l models.Layer) { layers.Protection = l }},
		{"trust", func(l models.Layer) { layers.Trust = l }},
		{"outcome", func(l models.Layer) { layers.Outcome = l }},
	}
	for _, k := range kinds {
		k := k
		g.Go(func() error {
			lay, _ := o.AssessLayer(ctx, k.name, fc)
			mu.Lock()
			k.set(lay)
			mu.Unlock()
			return nil
		})
	}
	if err := g.Wait(); err != nil {
		return models.SignalPayload{}, err
	}

	flags := scoring.DetectRedFlags(layers)
	verdict := scoring.ComputeVerdict(layers, fc.Scope, o.Cfg.MaturityTier, flags)

	payload := models.SignalPayload{
		SchemaVersion: models.SchemaVersion,
		Scope:         fc.Scope,
		Identifier:    fc.Identifier,
		MaturityTier:  o.Cfg.MaturityTier,
		GeneratedAt:   time.Now().UTC().Format(time.RFC3339),
		Layers:        layers,
		RedFlags:      flags,
		Verdict:       verdict,
	}
	o.Audit.RecordDecision(payload)
	o.Hooks.EmitDecision(payload)
	return payload, nil
}
