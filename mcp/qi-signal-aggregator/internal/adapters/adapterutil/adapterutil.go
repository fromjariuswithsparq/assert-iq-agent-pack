// Package adapterutil holds helpers shared across the built-in adapters.
package adapterutil

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// LoadFixture reads a JSON file from settings["fixture_dir"]/<identifier>.json
// and unmarshals it into dst. Returns (false, nil) if fixture_dir is not set
// — callers should then take the live-API path. Any other error is fatal.
func LoadFixture(settings map[string]any, identifier string, dst any) (used bool, err error) {
	dir, ok := settings["fixture_dir"].(string)
	if !ok || dir == "" {
		return false, nil
	}
	path := filepath.Join(dir, identifier+".json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return false, fmt.Errorf("fixture %s: %w", path, err)
	}
	if err := json.Unmarshal(raw, dst); err != nil {
		return false, fmt.Errorf("fixture %s parse: %w", path, err)
	}
	return true, nil
}

// String pulls a string setting with a default.
func String(settings map[string]any, key, def string) string {
	if v, ok := settings[key].(string); ok {
		return v
	}
	return def
}

// Int pulls a numeric setting (YAML may decode as int or float64) with a default.
func Int(settings map[string]any, key string, def int) int {
	switch v := settings[key].(type) {
	case int:
		return v
	case int64:
		return int(v)
	case float64:
		return int(v)
	}
	return def
}
