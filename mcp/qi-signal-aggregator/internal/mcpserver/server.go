// Package mcpserver wires the orchestrator to the Model Context Protocol via
// the official Go SDK. Seven tools are exposed; their input/output structs
// are typed so the SDK can generate JSON schemas automatically.
package mcpserver

import (
	"context"
	"fmt"

	"github.com/assert-iq/qi-signal-aggregator/internal/models"
	"github.com/assert-iq/qi-signal-aggregator/internal/orchestrator"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// ---- input/output types ----

type AssessInput struct {
	Scope        string `json:"scope" jsonschema:"PR|release|merge|commit; default pr"`
	Identifier   string `json:"identifier" jsonschema:"PR number, release tag, merge SHA, or commit"`
	LookbackDays int    `json:"lookback_days,omitempty"`
}

type EmitInput struct {
	Scope      string `json:"scope"`
	Identifier string `json:"identifier"`
	Outcome    string `json:"outcome" jsonschema:"escape|hotfix|clean|rollback"`
	Note       string `json:"note,omitempty"`
}

type HealthOutput struct {
	OK              bool     `json:"ok"`
	SchemaVersion   string   `json:"schema_version"`
	KnownAdapters   []string `json:"known_adapters"`
	ConfiguredAdapt []string `json:"configured_adapters"`
}

// Server bundles a Go-SDK MCP server with the orchestrator.
type Server struct {
	orch *orchestrator.Orchestrator
	srv  *mcp.Server
}

func New(orch *orchestrator.Orchestrator) *Server {
	s := mcp.NewServer(&mcp.Implementation{
		Name:    "qi-signal-aggregator",
		Version: "0.2.0",
	}, nil)

	out := &Server{orch: orch, srv: s}
	out.registerTools()
	return out
}

// Run starts the stdio transport. Blocks until the client disconnects.
func (s *Server) Run(ctx context.Context) error {
	return s.srv.Run(ctx, &mcp.StdioTransport{})
}

func (s *Server) registerTools() {
	mcp.AddTool(s.srv, &mcp.Tool{
		Name:        "get_decision_confidence",
		Description: "Synthesize all four QI layers into a verdict for the requested scope.",
	}, s.handleAll)

	mcp.AddTool(s.srv, &mcp.Tool{
		Name:        "assess_change",
		Description: "Score the Change layer only (PR churn, late changes, sensitive paths).",
	}, s.handleLayer("change"))

	mcp.AddTool(s.srv, &mcp.Tool{
		Name:        "assess_protection",
		Description: "Score the Protection layer only (coverage, traceability).",
	}, s.handleLayer("protection"))

	mcp.AddTool(s.srv, &mcp.Tool{
		Name:        "assess_trust",
		Description: "Score the Trust layer only (test stability, blocked/skipped).",
	}, s.handleLayer("trust"))

	mcp.AddTool(s.srv, &mcp.Tool{
		Name:        "assess_outcome",
		Description: "Score the Outcome layer only (incidents, escapes).",
	}, s.handleLayer("outcome"))

	mcp.AddTool(s.srv, &mcp.Tool{
		Name:        "emit_signal",
		Description: "Record a post-decision outcome (escape, hotfix, clean, rollback).",
	}, s.handleEmit)

	mcp.AddTool(s.srv, &mcp.Tool{
		Name:        "health",
		Description: "Return server health and the list of configured/registered adapters.",
	}, s.handleHealth)
}

// ---- handlers (typed via Go SDK generics) ----

func (s *Server) handleAll(
	ctx context.Context,
	_ *mcp.CallToolRequest,
	in AssessInput,
) (*mcp.CallToolResult, models.SignalPayload, error) {
	payload, err := s.orch.AssessAll(ctx, fc(in))
	if err != nil {
		return nil, payload, err
	}
	return nil, payload, nil
}

func (s *Server) handleLayer(kind string) func(context.Context, *mcp.CallToolRequest, AssessInput) (*mcp.CallToolResult, models.Layer, error) {
	return func(ctx context.Context, _ *mcp.CallToolRequest, in AssessInput) (*mcp.CallToolResult, models.Layer, error) {
		layer, err := s.orch.AssessLayer(ctx, kind, fc(in))
		if err != nil {
			return nil, layer, err
		}
		return nil, layer, nil
	}
}

func (s *Server) handleEmit(
	_ context.Context,
	_ *mcp.CallToolRequest,
	in EmitInput,
) (*mcp.CallToolResult, map[string]string, error) {
	if in.Scope == "" || in.Identifier == "" || in.Outcome == "" {
		return nil, nil, fmt.Errorf("scope, identifier, and outcome are required")
	}
	s.orch.Audit.RecordOutcome(models.Scope(in.Scope), in.Identifier, in.Outcome, in.Note)
	s.orch.Hooks.EmitOutcome(models.Scope(in.Scope), in.Identifier, in.Outcome)
	return nil, map[string]string{"recorded": "ok"}, nil
}

func (s *Server) handleHealth(
	_ context.Context,
	_ *mcp.CallToolRequest,
	_ struct{},
) (*mcp.CallToolResult, HealthOutput, error) {
	configured := []string{}
	for _, names := range s.orch.Cfg.Adapters {
		configured = append(configured, names...)
	}
	return nil, HealthOutput{
		OK:              true,
		SchemaVersion:   models.SchemaVersion,
		KnownAdapters:   knownAdapters(),
		ConfiguredAdapt: configured,
	}, nil
}

func fc(in AssessInput) models.FetchContext {
	scope := models.ScopePR
	if in.Scope != "" {
		scope = models.Scope(in.Scope)
	}
	return models.FetchContext{
		Scope:        scope,
		Identifier:   in.Identifier,
		LookbackDays: in.LookbackDays,
	}
}
