// Package cli wires cobra subcommands. `serve` is the MCP stdio entrypoint
// IDEs invoke; `emit`, `demo`, and `health` are convenience CLI usages.
package cli

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/assert-iq/qi-signal-aggregator/internal/audit"
	"github.com/assert-iq/qi-signal-aggregator/internal/config"
	"github.com/assert-iq/qi-signal-aggregator/internal/hooks"
	"github.com/assert-iq/qi-signal-aggregator/internal/mcpserver"
	"github.com/assert-iq/qi-signal-aggregator/internal/models"
	"github.com/assert-iq/qi-signal-aggregator/internal/orchestrator"

	// Side-effect import — registers every built-in adapter.
	_ "github.com/assert-iq/qi-signal-aggregator/internal/adapters/all"

	"github.com/spf13/cobra"
)

var (
	flagConfig    string
	flagAuditPath string
)

func Execute() error {
	root := &cobra.Command{
		Use:   "qi-signal-aggregator",
		Short: "QI Signal Aggregator — MCP server + CLI for decision-grade quality signals",
	}
	root.PersistentFlags().StringVar(&flagConfig, "config", defaultConfigPath(), "path to .assert-iq/config.yaml")
	root.PersistentFlags().StringVar(&flagAuditPath, "audit", defaultAuditPath(), "path to audit JSONL log")

	root.AddCommand(serveCmd())
	root.AddCommand(emitCmd())
	root.AddCommand(demoCmd())
	root.AddCommand(healthCmd())

	// Default command when no subcommand is given: serve.
	root.RunE = serveCmd().RunE
	return root.Execute()
}

func defaultConfigPath() string {
	for _, p := range []string{".assert-iq/config.yaml", "config.yaml"} {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

func defaultAuditPath() string {
	return filepath.Join(".assert-iq", ".audit", "signals.jsonl")
}

func loadOrch() (*orchestrator.Orchestrator, error) {
	cfg, err := config.Load(flagConfig)
	if err != nil {
		return nil, err
	}
	// Adapter settings (fixture_dir, coverage path, junit glob, scan_root) are
	// expressed relative to the config file. Resolve them by chdir'ing to the
	// config's directory before adapters are built.
	if flagConfig != "" {
		if abs, err := filepath.Abs(flagConfig); err == nil {
			_ = os.Chdir(filepath.Dir(abs))
		}
	}
	aud, err := audit.New(flagAuditPath)
	if err != nil {
		return nil, err
	}
	return orchestrator.New(cfg, aud, hooks.New())
}

func serveCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "serve",
		Short: "Run as an MCP server over stdio (default)",
		RunE: func(_ *cobra.Command, _ []string) error {
			o, err := loadOrch()
			if err != nil {
				return err
			}
			s := mcpserver.New(o)
			return s.Run(context.Background())
		},
	}
}

func emitCmd() *cobra.Command {
	var (
		scope, id, outcome, note string
	)
	c := &cobra.Command{
		Use:   "emit",
		Short: "Record a post-decision outcome",
		RunE: func(_ *cobra.Command, _ []string) error {
			o, err := loadOrch()
			if err != nil {
				return err
			}
			o.Audit.RecordOutcome(models.Scope(scope), id, outcome, note)
			fmt.Println("recorded")
			return nil
		},
	}
	c.Flags().StringVar(&scope, "scope", "pr", "pr|release|merge|commit")
	c.Flags().StringVar(&id, "id", "", "identifier")
	c.Flags().StringVar(&outcome, "outcome", "", "escape|hotfix|clean|rollback")
	c.Flags().StringVar(&note, "note", "", "free-form note")
	return c
}

func demoCmd() *cobra.Command {
	var (
		scope, id string
	)
	c := &cobra.Command{
		Use:   "demo",
		Short: "Run a one-shot assessment and print the payload as JSON",
		RunE: func(_ *cobra.Command, _ []string) error {
			o, err := loadOrch()
			if err != nil {
				return err
			}
			payload, err := o.AssessAll(context.Background(), models.FetchContext{
				Scope:      models.Scope(scope),
				Identifier: id,
			})
			if err != nil {
				return err
			}
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(payload)
		},
	}
	c.Flags().StringVar(&scope, "scope", "pr", "pr|release|merge|commit")
	c.Flags().StringVar(&id, "id", "PR-001", "identifier")
	return c
}

func healthCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "health",
		Short: "Print server health and adapter inventory",
		RunE: func(_ *cobra.Command, _ []string) error {
			o, err := loadOrch()
			if err != nil {
				return err
			}
			configured := []string{}
			for _, names := range o.Cfg.Adapters {
				configured = append(configured, names...)
			}
			out := map[string]any{
				"ok":                   true,
				"schema_version":       models.SchemaVersion,
				"configured_adapters":  configured,
				"audit_path":           flagAuditPath,
				"config_path":          flagConfig,
				"maturity_tier":        o.Cfg.MaturityTier,
			}
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(out)
		},
	}
}
