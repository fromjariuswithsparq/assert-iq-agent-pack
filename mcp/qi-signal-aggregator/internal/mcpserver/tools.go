package mcpserver

import "github.com/assert-iq/qi-signal-aggregator/internal/adapters"

// knownAdapters is a thin shim so server.go does not import the adapters
// package directly — keeps the public surface of mcpserver minimal.
func knownAdapters() []string { return adapters.Known() }
