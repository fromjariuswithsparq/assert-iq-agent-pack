// Package hooks is a no-op stub for v0.1. The hook bus exists so other
// packages can call Emit() without conditional checks; in a future release
// this will dispatch to actual subscribers (CI signal emit, dashboards).
package hooks

import "github.com/assert-iq/qi-signal-aggregator/internal/models"

type Bus struct{}

func New() *Bus { return &Bus{} }

func (b *Bus) EmitDecision(_ models.SignalPayload) {}
func (b *Bus) EmitOutcome(_ models.Scope, _ string, _ string) {}
