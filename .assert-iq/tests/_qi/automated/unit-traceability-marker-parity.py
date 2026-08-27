#!/usr/bin/env python3
"""
UNIT: qi-traceability.instructions.md must document every marker_style that
.assert-iq/config.yaml accepts.

WHY THIS EXISTS

config.yaml designates the instruction file as `traceability.rules_path` -- the
config points AT the file. They drifted anyway, and nothing noticed for the
file's entire life:

  config.yaml offered  : generic, qi_trace_xml, javadoc, jsdoc, python_doc,
                         python_decorator, go_comment, rust_doc, ruby, swift_doc
  the file documented  : 7 of those, under different names

`generic` -- the SHIPPED DEFAULT -- was absent entirely, along with
python_decorator, rust_doc, ruby and swift_doc. So a repo left on defaults, or
tailored to any of those four, pointed `marker_style` at a style its own rules
file never described. Nothing failed; the agent simply invented a format.

This is the same class of bug as the generated Copilot agents and docs/html:
two artifacts that must agree, with no check that they do. A style added to
config tomorrow would drift again the same way.

WHAT IT CHECKS

Every `marker_style` enum value in config.yaml appears in the instruction file.
Deliberately one-directional: the file may mention extra names (it documents
`csharp_xml` as a legacy alias), but it may never be missing one config offers.

PORTABILITY: stdlib only, no yaml dependency (the enum lives in comments, so it
is parsed textually either way). Run from the repo root.
"""

import io
import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

CONFIG = os.path.join(".assert-iq", "config.yaml")
RULES = os.path.join(".github", "instructions", "qi-traceability.instructions.md")

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


def read(path):
    return io.open(path, encoding="utf-8-sig", errors="replace").read()


def marker_styles(cfg_text):
    """Pull the marker_style enum out of the config's option comments.

    The values are documented as comment lines shaped like:
        #   generic      -> // qi-trace: <WORK-ITEM>
    inside the `traceability:` block, plus the active `marker_style:` value.
    """
    block = cfg_text.split("traceability:", 1)
    if len(block) < 2:
        return set(), None
    # Stop at the next top-level key so we never pick up an unrelated enum.
    body = re.split(r"\n(?=[a-z_]+:)", block[1])[0]

    styles = set()
    for line in body.splitlines():
        s = line.strip()
        if not s.startswith("#"):
            continue
        # `#   <name>  ->  <form>` or `#   <name> → <form>`
        m = re.match(r"#\s{2,}([a-z_]+)\s*(?:->|→)", s)
        if m:
            styles.add(m.group(1))

    active = None
    m = re.search(r'^\s*marker_style:\s*"?([a-z_]+)"?', body, re.M)
    if m:
        active = m.group(1)
    return styles, active


print("=== UNIT: traceability marker_style parity (config <-> rules file) ===")
print("")

missing_files = [p for p in (CONFIG, RULES) if not os.path.isfile(p)]
if missing_files:
    for p in missing_files:
        bad("missing file: %s" % p)
else:
    cfg = read(CONFIG)
    rules = read(RULES)
    styles, active = marker_styles(cfg)

    if len(styles) < 5:
        bad("could not parse the marker_style enum out of %s (found %d: %s) -- "
            "if the option comments were reformatted, update this parser"
            % (CONFIG, len(styles), sorted(styles)))
    else:
        ok("parsed %d marker_style values from config.yaml" % len(styles))

        undocumented = sorted(s for s in styles if s not in rules)
        if undocumented:
            bad("config.yaml offers marker_style value(s) that %s never "
                "documents: %s -- a repo set to one of these points at a style "
                "its own rules file does not describe, and the agent will "
                "invent a format. Add them to the marker-style table."
                % (RULES, ", ".join(undocumented)))
        else:
            ok("all %d marker_style value(s) are documented in the rules file"
               % len(styles))

        # The shipped default deserves its own assertion: it is the value most
        # installs actually run on, and it was the one missing.
        if active:
            if active in rules:
                ok("the active default (marker_style: %s) is documented" % active)
            else:
                bad("the ACTIVE marker_style (%s) is not documented in %s -- "
                    "this is the value every untailored install uses"
                    % (active, RULES))

    # The rules file must not re-narrow itself to one stack. This is what made
    # the file inert on non-.NET repos: applyTo excluded every other language.
    m = re.search(r'^applyTo:\s*"([^"]+)"', rules, re.M)
    if not m:
        bad("%s has no applyTo in its frontmatter" % RULES)
    elif m.group(1).strip() == "**/*.{cs,xaml}":
        bad("%s applyTo is back to the .NET-only glob '**/*.{cs,xaml}' -- the "
            "file then never loads for TS/Python/Go/Java/Ruby/Rust/Swift repos, "
            "so traceability silently does not apply on most stacks. Ship "
            "inclusive; let /assert-iq-tailor narrow it." % RULES)
    else:
        ok("applyTo is not narrowed to the .NET-only glob")

print("")
print("=== Results: %d PASS, %d FAIL ===" % (passed, failed))
sys.exit(1 if failed else 0)
