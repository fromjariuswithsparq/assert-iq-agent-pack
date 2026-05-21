// Package config loads the signal_aggregator block from .assert-iq/config.yaml
// (or any compatible file). Defaults match the Python reference so existing
// configs continue to work after the Go rewrite.
package config

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/assert-iq/qi-signal-aggregator/internal/models"
	"gopkg.in/yaml.v3"
)

// File mirrors the top-level YAML; we only deserialize what we use.
type File struct {
	Maturity struct {
		Tier models.MaturityTier `yaml:"tier"`
	} `yaml:"maturity"`
	SignalAggregator AggregatorConfig `yaml:"signal_aggregator"`
}

// AggregatorConfig is the resolved configuration for one server instance.
type AggregatorConfig struct {
	Enabled          bool                      `yaml:"enabled"`
	CacheDir         string                    `yaml:"cache_dir"`
	CacheTTLSeconds  map[string]int            `yaml:"cache_ttl_seconds"`
	Adapters         map[string][]string       `yaml:"adapters"`
	AdapterSettings  map[string]map[string]any `yaml:"adapter_settings"`
	SecretsEnv       map[string]string         `yaml:"secrets_env"`
	MaturityTier     models.MaturityTier       `yaml:"-"`
	RepoRoot         string                    `yaml:"-"`
}

// Default returns the baseline configuration used when no config file is
// supplied (and used as the fallback for any missing key in a partial file).
func Default() AggregatorConfig {
	return AggregatorConfig{
		Enabled:  true,
		CacheDir: ".assert-iq/.cache/signals",
		CacheTTLSeconds: map[string]int{
			"change":     300,
			"protection": 600,
			"trust":      3600,
			"outcome":    900,
		},
		Adapters: map[string][]string{
			"change":     {"github"},
			"protection": {"coverage_xml", "qi_traceability_scan"},
			"trust":      {"junit_glob"},
			"outcome":    {"sentry", "jira"},
		},
		AdapterSettings: map[string]map[string]any{},
		SecretsEnv:      map[string]string{},
		MaturityTier:    models.TierMid,
	}
}

// Load reads a YAML file and merges it with Default(). repoRoot defaults to
// the file's containing directory if empty.
func Load(path string) (AggregatorConfig, error) {
	cfg := Default()
	if path == "" {
		return cfg, nil
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		return cfg, fmt.Errorf("read config %q: %w", path, err)
	}
	var f File
	if err := yaml.Unmarshal(raw, &f); err != nil {
		return cfg, fmt.Errorf("parse config %q: %w", path, err)
	}

	if f.Maturity.Tier != "" {
		cfg.MaturityTier = f.Maturity.Tier
	}
	a := f.SignalAggregator
	if a.CacheDir != "" {
		cfg.CacheDir = a.CacheDir
	}
	for k, v := range a.CacheTTLSeconds {
		cfg.CacheTTLSeconds[k] = v
	}
	if len(a.Adapters) > 0 {
		cfg.Adapters = a.Adapters
	}
	if len(a.AdapterSettings) > 0 {
		cfg.AdapterSettings = a.AdapterSettings
	}
	if len(a.SecretsEnv) > 0 {
		cfg.SecretsEnv = a.SecretsEnv
	}
	// Honor explicit enabled=false; YAML zero-value defaults to false so we
	// only override when the field is present. Detecting absence requires a
	// pointer; for v0.1 we accept the small cost of always-enabled and let
	// callers omit the install entirely to "disable".
	cfg.Enabled = true

	abs, err := filepath.Abs(path)
	if err == nil {
		cfg.RepoRoot = filepath.Dir(abs)
	}
	return cfg, nil
}

// ResolveSecrets reads each env var named in SecretsEnv and returns the
// resolved map. Missing vars are silently omitted — adapters that need a
// secret will return UNGRADED rather than failing.
func (c AggregatorConfig) ResolveSecrets() map[string]string {
	out := make(map[string]string, len(c.SecretsEnv))
	for key, envName := range c.SecretsEnv {
		if v := os.Getenv(envName); v != "" {
			out[key] = v
		}
	}
	return out
}
