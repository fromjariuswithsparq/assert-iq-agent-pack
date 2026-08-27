#!/usr/bin/env python3
"""
UNIT: Dreaming hook wiring schema (two harnesses, two incompatible schemas).

WHY THIS EXISTS

Dreaming is wired through session-event hooks, and the two harnesses do NOT
share a hook schema:

  VS Code Copilot  handlers sit DIRECTLY in the event array, and OS-specific
                   command variants are given as osx / linux / windows keys.
  Claude Code      requires a matcher-group wrapper with a nested "hooks"
                   array, has NO platform keys, and selects the interpreter
                   with a "shell" field.

The installers used to copy the Copilot-shaped session-events.json straight into
.claude/settings.json. Claude Code silently ignores a flat handler, so neither
SessionStart (dream gate) nor Stop (session recorder) ever fired under Claude
Code -- while the same file kept working under VS Code on macOS, which is why it
looked like a platform problem rather than a schema problem.

Two further traps this locks down:
  * The Claude command body must NOT re-invoke its own interpreter. With
    shell="powershell" the body is already run by PowerShell, so a nested
    `powershell -Command "..."` wrapper double-processes the quoting and dies
    with a ParserError.
  * The POSIX and Windows Claude templates must cover the same events and point
    at the matching per-platform script.

PORTABILITY: stdlib only, UTF-8 stdout forced for Windows consoles.
Run from the repo root.
"""

import io
import json
import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

DREAM = ".assert-iq/dreaming"
COPILOT_TPL = DREAM + "/session-events.template.json"
CLAUDE_POSIX_TPL = DREAM + "/claude-hooks.posix.template.json"
CLAUDE_WIN_TPL = DREAM + "/claude-hooks.windows.template.json"
EVENTS = ("SessionStart", "Stop")
PLATFORM_KEYS = ("osx", "linux", "windows")

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


def load(path):
    if not os.path.isfile(path):
        return None
    try:
        return json.load(io.open(path, encoding="utf-8"))
    except Exception as e:
        bad("%s: not valid JSON (%s)" % (path, e))
        return None


def check_copilot(doc):
    # Copilot: flat handlers, platform keys allowed and expected.
    hooks = doc.get("hooks") or {}
    for ev in EVENTS:
        handlers = hooks.get(ev)
        if not handlers:
            bad("copilot template missing event %s" % ev)
            continue
        h = handlers[0]
        if "hooks" in h:
            bad("copilot template %s uses a matcher group; Copilot expects a flat handler" % ev)
            continue
        if "command" not in h:
            bad("copilot template %s handler has no command" % ev)
            continue
        if not any(k in h for k in PLATFORM_KEYS):
            bad("copilot template %s has no osx/linux/windows override "
                "(Windows would fall back to the bash command)" % ev)
            continue
        ok("copilot template %s: flat handler with platform overrides" % ev)

        # NO COMMAND IN THE COPILOT HOOK FILE MAY DEPEND ON A "$" VARIABLE.
        #
        # Field failure (Windows + Copilot): something between the hook file
        # and the interpreter replaced every $-prefixed token with nothing, so
        #     & { $r = if ($env:CLAUDE_PLUGIN_ROOT) { ... }; & $s }
        # reached PowerShell as
        #     & {  = if () {  } else { 'C:\...' }; &  }
        # which died with a ParserError. The hooks never ran and nothing was
        # ever written to .assert-iq/memory/logs/.
        #
        # It is NOT plain shell expansion: "$env:CLAUDE_PLUGIN_ROOT" vanished
        # whole instead of leaving ":CLAUDE_PLUGIN_ROOT" behind, and the
        # single-quoted POSIX payloads would have been protected from a shell.
        # Rather than guess the escaping rules of a layer we cannot inspect,
        # depend on no variables at all: the installers bake in an absolute
        # path, and dream-utils.{ps1,sh} derive AIQ_PACK_ROOT from their own
        # location, so nothing here needs an environment variable.
        #
        # Cheap static check, because it is the one that would have caught it.
        # e2e-hook-execution.py then proves the commands still WORK when the
        # $-stripping is applied.
        for key in ("command",) + PLATFORM_KEYS:
            cmd = h.get(key)
            if not cmd or "$" not in cmd:
                continue
            bad("copilot template %s[%s] contains '$' -- $-tokens are stripped "
                "before the interpreter sees them, which silently killed the "
                "Dreaming hooks on Windows. Bake the absolute path in instead: %s"
                % (ev, key, cmd[:120]))
        if not any("$" in (h.get(k) or "") for k in ("command",) + PLATFORM_KEYS):
            ok("copilot template %s: no command depends on a $ variable" % ev)


def check_claude(doc, path, want_shell, want_script):
    hooks = doc.get("hooks") or {}
    for ev in EVENTS:
        groups = hooks.get(ev)
        if not groups:
            bad("%s missing event %s" % (path, ev))
            continue
        g = groups[0]
        if "hooks" not in g:
            bad("%s %s: handler sits directly in the event array; Claude Code "
                "requires a matcher group with a nested 'hooks' array and "
                "silently ignores a flat handler" % (path, ev))
            continue
        h = g["hooks"][0]
        problems = []
        present = [k for k in PLATFORM_KEYS if k in h]
        if present:
            problems.append("platform key(s) %s are not part of the Claude "
                            "schema (use 'shell')" % sorted(present))
        if h.get("shell") != want_shell:
            problems.append("shell=%r, expected %r" % (h.get("shell"), want_shell))
        cmd = h.get("command", "")
        if not cmd:
            problems.append("empty command")
        # The declared shell already runs the body; re-invoking it nests
        # interpreters and breaks quoting.
        low = cmd.lower()
        if want_shell == "powershell" and low.startswith("powershell"):
            problems.append("command re-invokes powershell even though "
                            "shell=powershell (nested interpreter breaks quoting)")
        if want_shell == "bash" and low.startswith("bash "):
            problems.append("command re-invokes bash even though shell=bash")
        if want_script[ev] not in cmd:
            problems.append("command does not reference %s" % want_script[ev])
        if "__PACK_ROOT__" not in cmd:
            problems.append("command has no __PACK_ROOT__ placeholder to substitute")
        if problems:
            for pr in problems:
                bad("%s %s: %s" % (path, ev, pr))
        else:
            ok("%s %s: matcher group, shell=%s, native body, correct script"
               % (path, ev, want_shell))


print("=== UNIT: Dreaming hook wiring schema ===")
print("")

cop = load(COPILOT_TPL)
if cop is None:
    bad("missing " + COPILOT_TPL)
else:
    check_copilot(cop)

posix = load(CLAUDE_POSIX_TPL)
if posix is None:
    bad("missing " + CLAUDE_POSIX_TPL + " (Claude Code hooks would be unwired)")
else:
    check_claude(posix, CLAUDE_POSIX_TPL, "bash",
                 {"SessionStart": "dream-gate.sh", "Stop": "dream-record-session.sh"})

win = load(CLAUDE_WIN_TPL)
if win is None:
    bad("missing " + CLAUDE_WIN_TPL + " (Claude Code hooks would be unwired on Windows)")
else:
    check_claude(win, CLAUDE_WIN_TPL, "powershell",
                 {"SessionStart": "dream-gate.ps1", "Stop": "dream-record-session.ps1"})

# The two Claude templates must stay in step with each other and with Copilot.
if posix and win:
    if sorted(posix.get("hooks", {})) == sorted(win.get("hooks", {})):
        ok("Claude posix/windows templates cover the same events")
    else:
        bad("Claude posix/windows templates cover different events: %s vs %s"
            % (sorted(posix.get("hooks", {})), sorted(win.get("hooks", {}))))
if cop and posix:
    if sorted(cop.get("hooks", {})) == sorted(posix.get("hooks", {})):
        ok("Copilot and Claude templates cover the same events")
    else:
        bad("Copilot and Claude templates cover different events: %s vs %s"
            % (sorted(cop.get("hooks", {})), sorted(posix.get("hooks", {}))))

# The installers must never point .claude/settings.json at the Copilot render.
for script, needle in (("install.sh", "claude-hooks.posix.template.json"),
                       ("install.ps1", "claude-hooks.windows.template.json"),
                       ("scripts/bootstrap.sh", "claude-hooks.posix.template.json"),
                       ("scripts/bootstrap.ps1", "claude-hooks.windows.template.json")):
    if not os.path.isfile(script):
        bad("missing installer %s" % script)
        continue
    body = io.open(script, encoding="utf-8", errors="replace").read()
    if needle in body:
        ok("%s renders the Claude-shaped template" % script)
    else:
        bad("%s never references %s -- it is probably still copying the "
            "Copilot-shaped hooks into .claude/settings.json" % (script, needle))


# Referencing the template is not the same as being able to render it. In
# bootstrap.ps1 the renderer helper referenced the Claude template but never
# dot-sourced render-events.ps1 -- a dot-source inside a sibling function does
# not reach a new function's scope -- so Render-EventsTemplate was undefined,
# the call threw CommandNotFound, the surrounding try/catch swallowed it into a
# 'missing-template' record, and NO .claude/settings.json was written at all.
# The bug was invisible to the reference check above, so assert that the render
# library is loaded in the same scope that renders the template.
def enclosing_block(lines, idx, header_re):
    """Slice of `lines` for the function enclosing line `idx` (header to next header)."""
    import re
    start = 0
    for i in range(idx, -1, -1):
        if re.match(header_re, lines[i]):
            start = i
            break
    end = len(lines)
    for i in range(idx + 1, len(lines)):
        if re.match(header_re, lines[i]):
            end = i
            break
    return lines[start:end]


RENDER_SCOPE = (
    # installer, claude template, render lib, function-header pattern
    ("install.sh", "claude-hooks.posix.template.json", "render-events.sh", None),
    ("install.ps1", "claude-hooks.windows.template.json", "render-events.ps1", None),
    ("scripts/bootstrap.sh", "claude-hooks.posix.template.json", "render-events.sh",
     r"^[A-Za-z_][A-Za-z0-9_]*\(\)\s*\{"),
    ("scripts/bootstrap.ps1", "claude-hooks.windows.template.json", "render-events.ps1",
     r"^function\s+[A-Za-z0-9\-]+\s*\{"),
)

for script, tpl, lib, header_re in RENDER_SCOPE:
    if not os.path.isfile(script):
        continue  # already reported as missing above
    import re as _re
    lines = io.open(script, encoding="utf-8", errors="replace").read().splitlines()
    # Only the line that BINDS the template path is a render site. The same path
    # also appears in the 'missing-template' diagnostic, which renders nothing.
    bind_re = _re.compile(r"(^|[^\w$])\$?template\s*=", _re.IGNORECASE)
    hits = [i for i, ln in enumerate(lines)
            if tpl in ln and not ln.lstrip().startswith("#") and bind_re.search(ln)]
    if not hits:
        continue  # already reported by the reference check
    scope_label = "file" if header_re is None else "enclosing function"
    missing = []
    for i in hits:
        block = lines if header_re is None else enclosing_block(lines, i, header_re)
        if not any(lib in b for b in block):
            missing.append(i + 1)
    if missing:
        bad("%s: the %s rendering %s never loads %s (line(s) %s) -- the render "
            "call will fail and the installer will silently write no "
            ".claude/settings.json"
            % (script, scope_label, tpl, lib,
               ", ".join(str(m) for m in missing)))
    else:
        ok("%s loads %s in the %s that renders the Claude template"
           % (script, lib, scope_label))

print("")
print("=== Results: %d PASS, %d FAIL ===" % (passed, failed))
sys.exit(1 if failed else 0)
