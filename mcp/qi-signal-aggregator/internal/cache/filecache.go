// Package filecache is a tiny per-key file cache with epoch+TTL metadata.
// It exists so adapter calls that hit real APIs (GitHub, Sentry, Jira) do
// not get hammered on every IDE refresh.
package cache

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

type Cache struct {
	Root string
}

type meta struct {
	StoredAt int64 `json:"stored_at"`
	TTLSec   int   `json:"ttl_sec"`
}

func New(root string) *Cache {
	return &Cache{Root: root}
}

// Get returns the cached payload if present and not expired.
func (c *Cache) Get(key string, dst any) (hit bool, err error) {
	if c.Root == "" {
		return false, nil
	}
	dataPath := c.path(key, ".json")
	metaPath := c.path(key, ".meta")

	mraw, err := os.ReadFile(metaPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return false, nil
		}
		return false, err
	}
	var m meta
	if err := json.Unmarshal(mraw, &m); err != nil {
		return false, nil
	}
	if time.Now().Unix()-m.StoredAt > int64(m.TTLSec) {
		return false, nil
	}
	draw, err := os.ReadFile(dataPath)
	if err != nil {
		return false, nil
	}
	if err := json.Unmarshal(draw, dst); err != nil {
		return false, nil
	}
	return true, nil
}

// Put writes value under key with the given TTL in seconds.
func (c *Cache) Put(key string, value any, ttlSec int) error {
	if c.Root == "" {
		return nil
	}
	if err := os.MkdirAll(c.Root, 0o755); err != nil {
		return err
	}
	dataRaw, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	metaRaw, err := json.Marshal(meta{StoredAt: time.Now().Unix(), TTLSec: ttlSec})
	if err != nil {
		return err
	}
	if err := os.WriteFile(c.path(key, ".json"), dataRaw, 0o644); err != nil {
		return err
	}
	return os.WriteFile(c.path(key, ".meta"), metaRaw, 0o644)
}

func (c *Cache) path(key, ext string) string {
	safe := fmt.Sprintf("%x", []byte(key))
	return filepath.Join(c.Root, safe+ext)
}
