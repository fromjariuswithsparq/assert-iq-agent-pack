#!/usr/bin/env python3
"""
UNIT: Kiro harness surfaces must match the schema Kiro 1.0.337 actually enforces.

WHY THIS EXISTS

Kiro is the pack's third harness, and its PUBLIC DOCS ARE WRONG in three places
that would each ship a silently-broken file. Every rule below was derived from
the zod schemas and bundled system prompts inside the shipped kiro-agent
extension, not from kiro.dev. The full contract is .assert-iq/kiro-harness.md.

The three doc errors:

  1. Agent files are documented as .kiro/agents/*.json. The binary requires
     MARKDOWN with YAML frontmatter -- Kiro's own bundled authoring guidance
     says "Agent files MUST be markdown files with .md extension", and the
     parser errors with "No front matter found" on an empty header.
  2. `allowedTools` and `toolsSettings` are recommended by the docs for
     auto-approval and subagent gating. Both sit in the parser's
     `hasCliOnlyFields` list, so the IDE IGNORES them. Emitting them looks like
     configuration and does nothing.
  3. The hook schema shipped at extension-resources/hook.json is the
     DEPRECATED when/then format, which has no shell-command action at all.
     The live format is {"version":"v1", hooks:[...]}.

And the failure mode that motivates the strictest check here:

  Kiro custom agents do NOT inherit steering or skills the way the default
  agent does -- they load only what `resources` names. Worse, INVALID RESOURCE
  ENTRIES ARE DROPPED SILENTLY. So an agent with a typo'd glob runs with no QI
  rulebook at all, produces confident-sounding output with none of the
  four-layer discipline, and reports no error anywhere. That is the single
  worst outcome available on this harness, so both globs are asserted on every
  agent.

PORTABILITY: stdlib only, UTF-8 stdout forced for Windows consoles. No YAML
dependency -- the frontmatter parser here is deliberately minimal and only
understands the shapes sync-kiro emits.
Run from the repo root.
"""

import io
import json
import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

KIRO = ".kiro"
STEERING_DIR = KIRO + "/steering"
AGENTS_DIR = KIRO + "/agents"
MCP_JSON = KIRO + "/settings/mcp.json"
DREAM = ".assert-iq/dreaming"
KIRO_POSIX_TPL = DREAM + "/kiro-hooks.posix.template.json"
KIRO_WIN_TPL = DREAM + "/kiro-hooks.windows.template.json"

# SteeringContextFrontMatterSchema: enum(["always","fileMatch","manual","auto"])
INCLUSION_MODES = ("always", "fileMatch", "manual", "auto")

# V2_HOOK_TRIGGERS, verbatim from the bundle.
HOOK_TRIGGERS = (
    "PostFileCreate", "PostFileSave", "PostFileDelete",
    "PreToolUse", "PostToolUse", "UserPromptSubmit",
    "SessionStart", "Stop", "PreTaskExec", "PostTaskExec", "Manual",
)

# Capability tags Kiro resolves for an agent's `tools`. Kiro's own guidance is
# to use TAGS EXCLUSIVELY, never tool names, because names churn (fs_write,
# fsWrite and str_replace all coexist in 1.0.337) while tags are the stable
# surface.
TOOL_TAGS = (
    "read", "write", "shell", "web", "subagent", "spec", "context",
    "@mcp", "@powers", "@builtin", "@subagent", "@subagent-explicit", "*",
)

# dispatchKind: enum(["sub-agent","custom-agent","spec"])
DISPATCH_KINDS = ("sub-agent", "custom-agent", "spec")

# hasCliOnlyFields -- present in the docs, ignored by the IDE.
CLI_ONLY_FIELDS = ("allowedTools", "toolsSettings")

REQUIRED_AGENT_RESOURCES = (
    "file://.kiro/steering/**/*.md",
    "skill://.kiro/skills/**/SKILL.md",
)

passed = 0
failed = 0


def ok(m):
    global passed
    print("PASS " + m)
    passed += 1


def bad(m):
    global failed
    print("FAIL " + m)
    failed += 1


def load_json(path):
    if not os.path.isfile(path):
        bad("%s: missing" % path)
        return None
    try:
        return json.load(io.open(path, encoding="utf-8"))
    except Exception as e:
        bad("%s: not valid JSON (%s)" % (path, e))
        return None


def split_frontmatter(path):
    """Return (frontmatter_lines, ok). Empty frontmatter is an error in Kiro."""
    try:
        text = io.open(path, encoding="utf-8").read()
    except Exception as e:
        bad("%s: unreadable (%s)" % (path, e))
        return [], False
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    if not lines or lines[0].strip() != "---":
        bad("%s: no YAML frontmatter (Kiro: 'No front matter found')" % path)
        return [], False
    out = []
    for line in lines[1:]:
        if line.strip() == "---":
            return out, True
        out.append(line)
    bad("%s: frontmatter never closed" % path)
    return out, False


def fm_scalar(fm, key):
    pat = re.compile(r"^%s:\s*(.*)$" % re.escape(key))
    for line in fm:
        m = pat.match(line)
        if m:
            return m.group(1).strip()
    return None


def fm_list(fm, key):
    """Read a YAML list, either inline [a, b] or a block of '  - item' lines."""
    inline = fm_scalar(fm, key)
    if inline is None:
        return None
    inline = inline.strip()
    if inline.startswith("[") and inline.endswith("]"):
        body = inline[1:-1]
        return [unquote(x.strip()) for x in body.split(",") if x.strip()]
    if inline != "":
        return [unquote(inline)]
    # Block form: the lines following "key:" that start with "- ".
    items = []
    seen_key = False
    for line in fm:
        if re.match(r"^%s:\s*$" % re.escape(key), line):
            seen_key = True
            continue
        if seen_key:
            stripped = line.strip()
            if stripped.startswith("- "):
                items.append(unquote(stripped[2:].strip()))
            elif stripped == "":
                continue
            else:
                break
    return items


def unquote(s):
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        return s[1:-1]
    return s


# ---------------------------------------------------------------------------
# Steering
# ---------------------------------------------------------------------------
def check_steering():
    if not os.path.isdir(STEERING_DIR):
        bad("%s: missing (Kiro reads instructions from here and nowhere else)" % STEERING_DIR)
        return
    files = sorted(f for f in os.listdir(STEERING_DIR) if f.endswith(".md"))
    if not files:
        bad("%s: no steering files" % STEERING_DIR)
        return

    always = 0
    for name in files:
        path = STEERING_DIR + "/" + name
        fm, good = split_frontmatter(path)
        if not good:
            continue
        inc = fm_scalar(fm, "inclusion")
        if inc is None:
            # Absent inclusion means "always" to Kiro. The pack always states
            # it so intent survives a reader who does not know that default.
            bad("%s: no inclusion (pack policy: always state it explicitly)" % name)
            continue
        inc = unquote(inc)
        if inc not in INCLUSION_MODES:
            bad("%s: inclusion '%s' not in %s" % (name, inc, ", ".join(INCLUSION_MODES)))
            continue
        if inc == "always":
            always += 1
        if inc == "fileMatch":
            pats = fm_list(fm, "fileMatchPattern")
            if not pats:
                # Kiro: "fileMatchPattern required when inclusion is fileMatch".
                # Without it the file is INERT -- it loads for nothing.
                bad("%s: inclusion fileMatch with no fileMatchPattern (file is inert)" % name)
                continue
            braces = [p for p in pats if "{" in p or "}" in p]
            if braces:
                # Brace support in fileMatchPattern is unverified. sync-kiro
                # expands them precisely so this can never ship.
                bad("%s: unexpanded brace group(s) in fileMatchPattern: %s" % (name, braces))
                continue
            ok("%s: fileMatch with %d expanded pattern(s)" % (name, len(pats)))
        elif inc == "auto":
            # Kiro logs "Progressive steering file missing description" and
            # DROPS the file. The pack does not use auto for that reason.
            if not fm_scalar(fm, "description"):
                bad("%s: inclusion auto with no description (Kiro drops it silently)" % name)
            else:
                ok("%s: inclusion auto with description" % name)
        else:
            ok("%s: inclusion %s" % (name, inc))

    if always >= 1:
        ok("steering: %d always-on file(s) (the QI rulebook reaches every turn)" % always)
    else:
        bad("steering: no inclusion:always file -- the QI foundation would never load")


# ---------------------------------------------------------------------------
# Agents
# ---------------------------------------------------------------------------
def check_agents():
    if not os.path.isdir(AGENTS_DIR):
        bad("%s: missing" % AGENTS_DIR)
        return
    names = sorted(f for f in os.listdir(AGENTS_DIR) if f.endswith(".md"))
    if not names:
        bad("%s: no agent files" % AGENTS_DIR)
        return

    # Doc error #1: agents must be .md, never .json.
    strays = sorted(f for f in os.listdir(AGENTS_DIR) if f.endswith(".json"))
    if strays:
        bad("%s: .json agent file(s) %s -- Kiro requires .md with frontmatter"
            % (AGENTS_DIR, strays))
    else:
        ok("agents: all %d are .md (docs say .json; the binary requires .md)" % len(names))

    for name in names:
        path = AGENTS_DIR + "/" + name
        fm, good = split_frontmatter(path)
        if not good:
            continue

        if not fm_scalar(fm, "name"):
            bad("%s: no name" % name)
        if not fm_scalar(fm, "description"):
            bad("%s: no description (Kiro routes sub-agents by description)" % name)

        tools = fm_list(fm, "tools") or []
        if not tools:
            bad("%s: no tools" % name)
        else:
            unknown = [t for t in tools if t not in TOOL_TAGS and not t.startswith("@")]
            if unknown:
                bad("%s: tools %s are not capability TAGS -- Kiro's guidance is "
                    "tags only, because tool names churn" % (name, unknown))
            else:
                ok("%s: tools are tags (%s)" % (name, ", ".join(tools)))

        dk = fm_scalar(fm, "dispatchKind")
        if dk is not None:
            dk = unquote(dk)
            if dk not in DISPATCH_KINDS:
                bad("%s: dispatchKind '%s' not in %s" % (name, dk, ", ".join(DISPATCH_KINDS)))

        # Doc error #2: CLI-only fields do nothing in the IDE.
        present_cli = [f for f in CLI_ONLY_FIELDS if fm_scalar(fm, f) is not None]
        if present_cli:
            bad("%s: %s are CLI-only (hasCliOnlyFields) -- the IDE ignores them"
                % (name, ", ".join(present_cli)))

        # THE BIG ONE. No steering + no skills = an agent with no QI rulebook,
        # and invalid entries are dropped silently so there is no error to see.
        resources = fm_list(fm, "resources") or []
        missing = [r for r in REQUIRED_AGENT_RESOURCES if r not in resources]
        if missing:
            bad("%s: resources missing %s -- this agent would run with NO QI "
                "rulebook, silently (custom agents do not inherit steering/skills, "
                "and invalid entries are dropped without error)"
                % (name, ", ".join(missing)))
        else:
            ok("%s: declares both steering and skill resources" % name)


# ---------------------------------------------------------------------------
# Hook templates
# ---------------------------------------------------------------------------
def check_hook_template(path, want_interp):
    doc = load_json(path)
    if doc is None:
        return
    base = os.path.basename(path)

    if doc.get("version") != "v1":
        # Doc error #3: the deprecated shape has no version key and no command
        # action at all.
        bad("%s: version is %r, must be the literal \"v1\"" % (base, doc.get("version")))
        return
    hooks = doc.get("hooks")
    if not isinstance(hooks, list) or not hooks:
        bad("%s: hooks[] must have at least one entry" % base)
        return

    triggers = []
    for h in hooks:
        nm = h.get("name")
        if not nm or not str(nm).strip():
            bad("%s: a hook has no name (required, min length 1)" % base)
            continue
        trig = h.get("trigger")
        if trig not in HOOK_TRIGGERS:
            bad("%s [%s]: trigger %r not in V2_HOOK_TRIGGERS" % (base, nm, trig))
            continue
        triggers.append(trig)

        action = h.get("action") or {}
        if action.get("type") != "command":
            bad("%s [%s]: action.type must be 'command' for Dreaming" % (base, nm))
            continue
        cmd = action.get("command") or ""
        if not cmd.strip():
            bad("%s [%s]: action.command must be non-empty" % (base, nm))
            continue

        # Kiro spawns with shell:true -- /bin/sh on POSIX, cmd.exe on Windows.
        # Neither runs bash-isms or PowerShell unaided, so the command must
        # name its interpreter.
        if want_interp not in cmd:
            bad("%s [%s]: command does not invoke %s (shell:true means "
                "/bin/sh or cmd.exe, not bash or powershell)" % (base, nm, want_interp))
            continue

        # ${WORKSPACE_ROOT} is Kiro's ONLY substitution. __PACK_ROOT__ is the
        # installer-baked fallback for a pack outside the workspace. Losing
        # either one silently breaks Dreaming for one install shape.
        if "${WORKSPACE_ROOT}" not in cmd:
            bad("%s [%s]: no ${WORKSPACE_ROOT} (Kiro's only substitution)" % (base, nm))
            continue
        if "__PACK_ROOT__" not in cmd:
            bad("%s [%s]: no __PACK_ROOT__ fallback for the installer to bake"
                % (base, nm))
            continue

        # The nudge must be emitted in Kiro's protocol, not Claude's. Kiro
        # forwards SessionStart stdout VERBATIM, so a Claude JSON envelope
        # would be pasted into the user's chat.
        if "AIQ_HOOK_OUTPUT=plain" not in cmd and "AIQ_HOOK_OUTPUT='plain'" not in cmd:
            bad("%s [%s]: does not set AIQ_HOOK_OUTPUT=plain -- Kiro would "
                "forward the Claude JSON envelope into the chat" % (base, nm))
            continue

        tmo = h.get("timeout")
        if tmo is not None and (not isinstance(tmo, int) or isinstance(tmo, bool) or tmo < 0):
            bad("%s [%s]: timeout must be a non-negative integer (seconds)" % (base, nm))
            continue

        ok("%s [%s]: %s -> command, interpreter + both roots + plain output" % (base, nm, trig))

    for need in ("SessionStart", "Stop"):
        if need not in triggers:
            bad("%s: no %s hook (Dreaming needs the gate and the recorder)" % (base, need))


def check_hook_parity():
    a = load_json(KIRO_POSIX_TPL)
    b = load_json(KIRO_WIN_TPL)
    if a is None or b is None:
        return
    ta = sorted(h.get("trigger") for h in a.get("hooks", []))
    tb = sorted(h.get("trigger") for h in b.get("hooks", []))
    if ta != tb:
        bad("kiro hook templates cover different triggers: posix=%s windows=%s" % (ta, tb))
    else:
        ok("kiro hook templates cover the same triggers (%s)" % ", ".join(ta))


# ---------------------------------------------------------------------------
# MCP
# ---------------------------------------------------------------------------
def check_mcp():
    doc = load_json(MCP_JSON)
    if doc is None:
        return

    if "mcpServers" not in doc:
        bad("%s: top-level key must be 'mcpServers' (VS Code uses 'servers')" % MCP_JSON)
        return
    if "servers" in doc:
        bad("%s: has a VS Code 'servers' key; Kiro reads 'mcpServers'" % MCP_JSON)
    if "inputs" in doc:
        bad("%s: has an 'inputs' array; Kiro has no prompt mechanism, so it "
            "does nothing and the credentials never resolve" % MCP_JSON)

    servers = doc["mcpServers"]
    if not servers:
        bad("%s: no servers" % MCP_JSON)
        return

    blob = json.dumps(doc)

    # Kiro infers stdio vs http from command vs url; there is no type field.
    typed = sorted(k for k, v in servers.items() if isinstance(v, dict) and "type" in v)
    if typed:
        bad("%s: %s carry a VS Code 'type' field; Kiro infers transport"
            % (MCP_JSON, ", ".join(typed)))
    else:
        ok("mcp.json: no 'type' fields (transport inferred from command vs url)")

    if "${input:" in blob:
        bad("%s: ${input:...} survives; Kiro cannot prompt, so these stay "
            "literal and every affected server fails to authenticate" % MCP_JSON)
    else:
        ok("mcp.json: no ${input:...} placeholders")

    if "${workspaceFolder}" in blob:
        bad("%s: ${workspaceFolder} survives; Kiro's expander is "
            "${[A-Za-z_][A-Za-z0-9_]*} against the ENVIRONMENT, so this is "
            "looked up as a variable named workspaceFolder and left literal" % MCP_JSON)
    else:
        ok("mcp.json: no ${workspaceFolder} (not a Kiro concept)")

    # Every placeholder must be a name Kiro's expander can actually match.
    bad_vars = sorted(set(
        m for m in re.findall(r"\$\{([^}]*)\}", blob)
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", m)
    ))
    if bad_vars:
        bad("%s: placeholder(s) %s cannot match Kiro's expander pattern"
            % (MCP_JSON, bad_vars))
    else:
        ok("mcp.json: all ${...} placeholders match Kiro's expander pattern")

    enabled = sorted(k for k, v in servers.items()
                     if isinstance(v, dict) and v.get("disabled") is not True)
    if enabled:
        bad("%s: %s not disabled; a committed config should not spawn "
            "subprocesses until the user opts in" % (MCP_JSON, ", ".join(enabled)))
    else:
        ok("mcp.json: all %d servers ship disabled (opt-in)" % len(servers))

    # A committed file must never carry a real secret.
    leaks = []
    for name, cfg in servers.items():
        if not isinstance(cfg, dict):
            continue
        for section in ("env", "headers"):
            for k, v in (cfg.get(section) or {}).items():
                if isinstance(v, str) and v and "${" not in v:
                    leaks.append("%s.%s.%s" % (name, section, k))
    if leaks:
        bad("%s: literal value(s) in %s -- credentials must be ${ENV_VAR}"
            % (MCP_JSON, ", ".join(leaks)))
    else:
        ok("mcp.json: no literal credential values")


# ---------------------------------------------------------------------------
# Skills
# ---------------------------------------------------------------------------
SKILLS_DIR = ".github/skills"


def check_skills():
    """Every SKILL.md needs name + description frontmatter, or Kiro drops it.

    Kiro is the strictest consumer of the Agent Skills standard the pack ships
    to. It REJECTS a skill whose SKILL.md has no YAML frontmatter --
    `skill.validation.failed {"event":"skill.frontmatter.missing"}` -- and the
    skill is then simply absent: no slash command, no auto-routing, no error
    the user ever sees.

    Found live: 3 of 30 skills (assert-iq-bootstrap, define-quality-rubric,
    grade-with-rubric) started straight at `# /skill-name` with no frontmatter
    at all. Claude Code tolerated that and fell back to the H1 heading, so it
    looked fine on two harnesses for as long as those skills have existed --
    which is exactly why it survived: nothing enforced the standard, and the
    lenient harnesses hid it.

    The tree lives at .github/skills and is symlinked to .claude/skills and
    .kiro/skills, so checking it once covers all three harnesses.
    """
    if not os.path.isdir(SKILLS_DIR):
        bad("%s: missing" % SKILLS_DIR)
        return
    names = sorted(d for d in os.listdir(SKILLS_DIR)
                   if os.path.isfile(os.path.join(SKILLS_DIR, d, "SKILL.md")))
    if not names:
        bad("%s: no skills" % SKILLS_DIR)
        return

    broken = []
    for name in names:
        path = "%s/%s/SKILL.md" % (SKILLS_DIR, name)
        try:
            text = io.open(path, encoding="utf-8").read()
        except Exception as e:
            bad("%s: unreadable (%s)" % (path, e))
            continue
        lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
        if not lines or lines[0].strip() != "---":
            broken.append((name, "no YAML frontmatter"))
            continue
        fm = []
        for line in lines[1:]:
            if line.strip() == "---":
                break
            fm.append(line)
        fm_name = fm_scalar(fm, "name")
        fm_desc = fm_scalar(fm, "description")
        if not fm_name:
            broken.append((name, "no name"))
        elif unquote(fm_name) != name:
            # Kiro requires name to match the folder.
            broken.append((name, "name '%s' does not match folder" % unquote(fm_name)))
        elif not fm_desc:
            broken.append((name, "no description"))

    if broken:
        for name, why in broken:
            bad("skill %s: %s -- Kiro drops it silently (no slash command, "
                "no auto-routing, no error)" % (name, why))
    else:
        ok("skills: all %d have name + description frontmatter" % len(names))


# ---------------------------------------------------------------------------
def main():
    print("=== Kiro harness schema ===")
    print("")
    print("--- skills ---")
    check_skills()
    print("")
    print("--- steering ---")
    check_steering()
    print("")
    print("--- agents ---")
    check_agents()
    print("")
    print("--- hook templates ---")
    check_hook_template(KIRO_POSIX_TPL, "bash")
    check_hook_template(KIRO_WIN_TPL, "powershell")
    check_hook_parity()
    print("")
    print("--- mcp ---")
    check_mcp()
    print("")
    print("=== Results: %d PASS, %d FAIL ===" % (passed, failed))
    if failed:
        print("")
        print("Contract: .assert-iq/kiro-harness.md")
        return 1
    print("Kiro surfaces match the schema Kiro 1.0.337 enforces.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
