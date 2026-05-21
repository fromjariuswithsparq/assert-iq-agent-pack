// Package adapters: this file is the side-effect import surface — importing
// `_ "github.com/.../internal/adapters/all"` registers every built-in adapter.
package all

import (
	_ "github.com/assert-iq/qi-signal-aggregator/internal/adapters/adoboards"
	_ "github.com/assert-iq/qi-signal-aggregator/internal/adapters/adorepos"
	_ "github.com/assert-iq/qi-signal-aggregator/internal/adapters/coverage"
	_ "github.com/assert-iq/qi-signal-aggregator/internal/adapters/githubadapter"
	_ "github.com/assert-iq/qi-signal-aggregator/internal/adapters/jira"
	_ "github.com/assert-iq/qi-signal-aggregator/internal/adapters/junit"
	_ "github.com/assert-iq/qi-signal-aggregator/internal/adapters/sentry"
	_ "github.com/assert-iq/qi-signal-aggregator/internal/adapters/traceability"
)
