// Package adapters defines the Adapter interface that every signal-source
// plugin implements, plus a static registry for the 6 default adapters.
//
// Custom adapters (v0.2): a subprocess protocol is planned but not in v0.1.
// To add a new adapter today, drop a package under internal/adapters/, call
// Register() from its init(), and rebuild.
package adapters

import (
	"context"
	"fmt"
	"sort"
	"sync"

	"github.com/assert-iq/qi-signal-aggregator/internal/models"
)

// LayerKind identifies which of the four QI layers an adapter contributes to.
type LayerKind string

const (
	KindChange     LayerKind = "change"
	KindProtection LayerKind = "protection"
	KindTrust      LayerKind = "trust"
	KindOutcome    LayerKind = "outcome"
)

// Adapter is the contract every signal source implements. Implementations
// must be safe for concurrent use by Fetch() — the orchestrator may call
// the same adapter for several scopes in parallel.
type Adapter interface {
	// Name is the registry key (e.g. "github", "coverage_xml").
	Name() string
	// Kind is the QI layer this adapter contributes to.
	Kind() LayerKind
	// Fetch produces a Layer for the given context. It must NEVER panic; a
	// failure should be returned as (Layer{State: UNGRADED, Reason: "..."}, err)
	// so the caller can decide whether to log+continue or abort.
	Fetch(ctx context.Context, fc models.FetchContext) (models.Layer, error)
}

// Factory produces an Adapter from per-adapter YAML settings. Factories run
// at server startup so wiring errors surface fast.
type Factory func(settings map[string]any) (Adapter, error)

var (
	registryMu sync.RWMutex
	registry   = map[string]Factory{}
)

// Register associates a factory with a name. Panics on duplicate registration
// because that is a programming error, never a runtime condition.
func Register(name string, f Factory) {
	registryMu.Lock()
	defer registryMu.Unlock()
	if _, ok := registry[name]; ok {
		panic(fmt.Sprintf("adapter %q already registered", name))
	}
	registry[name] = f
}

// Build instantiates the named adapter with its settings.
func Build(name string, settings map[string]any) (Adapter, error) {
	registryMu.RLock()
	f, ok := registry[name]
	registryMu.RUnlock()
	if !ok {
		return nil, fmt.Errorf("adapter %q is not registered", name)
	}
	return f(settings)
}

// Known returns a sorted list of registered adapter names. Used by `health`.
func Known() []string {
	registryMu.RLock()
	defer registryMu.RUnlock()
	names := make([]string, 0, len(registry))
	for n := range registry {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}
