#!/usr/bin/env python3
"""
E2E: the Dreaming hooks must actually FIRE, for both harnesses, on this platform.

WHY THIS EXISTS

Everything about the hook wiring used to be checked STRUCTURALLY -- is the shape
right, does the installer reference the right template -- and every structural
check passed while the feature was dead:

  * Claude Code got the Copilot shape (flat handler). Claude Code silently
    ignores a flat handler, so SessionStart and Stop never ran. The file was
    valid JSON, the installer referenced the right source, nothing failed.
  * The Copilot `windows` override was rendered by install.sh with an MSYS pack
    root ("/c/Users/..."). PowerShell cannot resolve that, so the handler hit
    `if (-not (Test-Path $s)) { exit 0 }` and exited SUCCESSFULLY, recording
    nothing.

Both failures are invisible to shape checks and to exit codes. The only test
that catches them is executing the command the harness would run and asserting
the OBSERVABLE state change. That is what this does:

    Stop hook        x5  ->  .dream/state.json sessions_since_dream == 5
                             and a dated log file exists
    SessionStart hook    ->  emits a systemMessage nudge at the threshold

CLAUDE_PLUGIN_ROOT is deliberately UNSET so the baked-in fallback path is the
one under test -- that is the half that was broken for Copilot on Windows.

Covers all four supported variations by construction: it picks this platform's
command out of each config, so running it on Windows exercises
Windows+Copilot and Windows+Claude, and on macOS the two Mac variations.

PORTABILITY: stdlib only. Run from the repo root.
"""

import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

IS_WIN = os.name == "nt"
DREAM = os.path.join(".assert-iq", "dreaming")
COPILOT_TPL = os.path.join(DREAM, "session-events.template.json")
CLAUDE_TPL = os.path.join(
    DREAM, "claude-hooks.windows.template.json" if IS_WIN
    else "claude-hooks.posix.template.json")

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


def render(template_path, pack_root):
    """Substitute __PACK_ROOT__ the way the installers do (JSON-escaped)."""
    raw = io.open(template_path, encoding="utf-8").read()
    escaped = pack_root.replace("\\", "\\\\").replace('"', '\\"')
    return json.loads(raw.replace("__PACK_ROOT__", escaped))


def copilot_command(doc, event):
    """The command VS Code Copilot would run on THIS platform."""
    h = (doc.get("hooks") or {}).get(event)
    if not h:
        return None
    h = h[0]
    if IS_WIN:
        key = "windows"
    elif sys.platform == "darwin":
        key = "osx"
    else:
        key = "linux"
    return h.get(key) or h.get("command")


def claude_command(doc, event):
    """The (command, shell) Claude Code would run."""
    groups = (doc.get("hooks") or {}).get(event)
    if not groups or "hooks" not in groups[0]:
        return None, None
    h = groups[0]["hooks"][0]
    return h.get("command"), h.get("shell")


# Every $-prefixed token, as the VS Code hook layer treats them.
DOLLAR_TOKEN = re.compile(r"\$[A-Za-z_][A-Za-z0-9_:]*")


def strip_dollar_tokens(cmd):
    r"""Reproduce the Windows + Copilot field failure.

    Something between the hook file and the interpreter substituted every
    $-prefixed token with nothing, so

        & { $r = if ($env:CLAUDE_PLUGIN_ROOT) { ... }; & $s }

    arrived at PowerShell as

        & {  = if () {  } else { 'C:\...' }; &  }

    -> ParserError, hooks never ran, nothing written to memory/logs/.

    This test used to invoke the command with shell=True, which on Windows is
    cmd.exe -- and cmd.exe does NOT touch '$'. So the suite stayed green while
    the feature was dead in the IDE. Applying the transform here is what makes
    the test model the real environment instead of a friendlier one.

    Note it is NOT plain shell expansion: "$env:CLAUDE_PLUGIN_ROOT" vanished
    whole rather than leaving ":CLAUDE_PLUGIN_ROOT" behind, and the POSIX
    payloads are single-quoted, which a shell would have protected. Since the
    exact rule belongs to a layer we cannot inspect, the commands must simply
    not depend on variables at all -- asserted statically by unit-hook-schema.py
    and proven to still work here.
    """
    return DOLLAR_TOKEN.sub("", cmd)


def run_copilot(cmd, stdin_text, env):
    # Copilot hands the string to the platform shell, with $-tokens already
    # substituted away. Both halves matter: the command must survive the
    # stripping AND still do its job.
    return subprocess.run(strip_dollar_tokens(cmd), shell=True,
                          input=stdin_text, env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          universal_newlines=True)


def run_claude(cmd, shell, stdin_text, env):
    # Claude Code runs the body with the declared interpreter, no wrapper.
    if shell == "powershell":
        host = shutil.which("pwsh") or shutil.which("powershell")
        if not host:
            return None
        argv = [host, "-NoProfile", "-Command", cmd]
    else:
        host = shutil.which("bash")
        if not host:
            return None
        argv = [host, "--noprofile", "--norc", "-c", cmd]
    return subprocess.run(argv, input=stdin_text, env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          universal_newlines=True)


def fresh_memory(root):
    mem = tempfile.mkdtemp(prefix="aiq-hookexec-", dir=root)
    for sub in (".dream", "logs", "topics"):
        os.makedirs(os.path.join(mem, sub), exist_ok=True)
    with io.open(os.path.join(mem, ".dream", "state.json"), "w",
                 encoding="utf-8", newline="\n") as f:
        f.write('{\n  "last_dream_utc": null,\n  "sessions_since_dream": 0\n}\n')
    return mem


def hook_env(mem):
    env = dict(os.environ)
    env["AIQ_MEMORY_DIR"] = mem
    env["AIQ_DREAM_MIN_SESSIONS"] = "5"
    env["AIQ_DREAM_MIN_HOURS"] = "24"
    # The baked fallback path is what we are testing; do not let a real
    # CLAUDE_PLUGIN_ROOT mask a wrongly-rendered one.
    env.pop("CLAUDE_PLUGIN_ROOT", None)
    env.pop("AIQ_DREAMING_DISABLED", None)
    env.pop("AIQ_PACK_ROOT", None)
    return env


def sessions_in(mem):
    p = os.path.join(mem, ".dream", "state.json")
    try:
        return json.load(io.open(p, encoding="utf-8")).get("sessions_since_dream")
    except Exception as e:
        return "unreadable (%s)" % type(e).__name__


def has_log(mem):
    for root, _dirs, files in os.walk(os.path.join(mem, "logs")):
        if any(f.endswith(".md") for f in files):
            return True
    return False


def exercise(label, runner):
    """runner(event, stdin, env) -> CompletedProcess or None."""
    work = tempfile.mkdtemp(prefix="aiq-hookwork-")
    try:
        mem = fresh_memory(work)
        env = hook_env(mem)

        first = None
        for i in range(1, 6):
            res = runner("Stop", '{"session_id":"s%d"}' % i, env)
            if res is None:
                print("SKIP %s: required interpreter not found" % label)
                return
            if first is None:
                first = res

        if first.returncode != 0:
            bad("%s Stop hook exited %d (stderr: %s)"
                % (label, first.returncode, (first.stderr or "").strip()[:200]))
        elif "continue" not in (first.stdout or ""):
            bad("%s Stop hook did not emit a {\"continue\":true} envelope (got: %r)"
                % (label, (first.stdout or "").strip()[:200]))
        else:
            ok("%s Stop hook returns a valid envelope" % label)

        n = sessions_in(mem)
        if n == 5:
            ok("%s Stop hook recorded 5 sessions (state.json updated)" % label)
        else:
            bad("%s Stop hook ran but sessions_since_dream is %r, expected 5 -- "
                "the handler exited 0 without doing anything (classic wrong "
                "baked pack root, or a shape the harness ignores)" % (label, n))

        if has_log(mem):
            ok("%s Stop hook wrote a dated log file" % label)
        else:
            bad("%s Stop hook wrote no log file under logs/" % label)

        res = runner("SessionStart", "{}", env)
        out = (res.stdout or "") if res else ""
        if res is None:
            print("SKIP %s SessionStart: interpreter not found" % label)
        elif "systemMessage" in out:
            ok("%s SessionStart hook fired the /dream nudge at the threshold" % label)
        else:
            bad("%s SessionStart hook did not nudge at 5 sessions (rc=%s, out=%r)"
                % (label, res.returncode, out.strip()[:200]))
    finally:
        shutil.rmtree(work, ignore_errors=True)


print("=== E2E: Dreaming hook execution (both harnesses, this platform) ===")
print("platform: %s   harness commands: %s"
      % (sys.platform, "windows/powershell" if IS_WIN else "posix/bash"))
print("")

pack_root = os.path.abspath(".")

missing = [p for p in (COPILOT_TPL, CLAUDE_TPL) if not os.path.isfile(p)]
if missing:
    for m in missing:
        bad("missing template: %s" % m)
else:
    cop = render(COPILOT_TPL, pack_root)
    cla = render(CLAUDE_TPL, pack_root)

    def copilot_runner(event, stdin_text, env):
        cmd = copilot_command(cop, event)
        if not cmd:
            return None
        return run_copilot(cmd, stdin_text, env)

    def claude_runner(event, stdin_text, env):
        cmd, shell = claude_command(cla, event)
        if not cmd:
            return None
        return run_claude(cmd, shell, stdin_text, env)

    exercise("Copilot", copilot_runner)
    exercise("Claude Code", claude_runner)

print("")
print("=== Results: %d PASS, %d FAIL ===" % (passed, failed))
sys.exit(1 if failed else 0)
