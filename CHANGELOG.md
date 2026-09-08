# Changelog

All notable changes to the Assert.IQ Agent Pack are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.3] — 2026-09-04

### Added (a feature guide — the pack listed its features but never explained them)

The README advertises eight features as eight cards. A developer evaluating the
pack could see *that* Dreaming and the Oracle Layer and Multi-Agent
Orchestration existed, and had no way to learn **when or why** to reach for any
of them. The full docs describe how the pack is built; nothing described how to
use it, feature by feature, for someone meeting it for the first time.

- **New `FEATURES.md` and its HTML sister `FEATURES.html`** — every one of the
  eight features and all **31 skills**, each broken down the same way: what it
  is, how to use it, when to use it (including when *not* to), and why it
  matters. Written for a first-year engineer and a non-technical stakeholder at
  the same time, so neither has to skip anything. Opens with a plain-language
  glossary of the eight recurring terms, a "which feature do I need?" chooser,
  and closes with a first-two-weeks sequence.
- **The eight README cards are now links.** Each card in *QI inside your IDE*
  navigates straight to that feature's section, on both the HTML landing page
  and in `README.md` — where the list also grew from six bullets to the eight
  the cards actually show.
- **Every feature and skill is individually addressable and searchable.** The
  guide contributes **86 headings** to the cross-page search index, including
  all 31 skills by command name, so typing `flake` lands on
  `/analyze-flaky-test`. Anchors are stable and one-per-heading.

### Fixed (release and doc tooling did not know about a new doc pair)

Three gaps surfaced while wiring the guide in — each one a place where adding a
doc page would have silently drifted:

- **`build-search-index.py` emitted malformed HTML.** Injecting a generated
  `id` into a heading that already carried attributes produced
  `<h3id="…" class="…">` — no space after the tag name — because one variable
  was doing double duty as the separator before the id *and* after it. No
  existing page had an attributed heading, so it had never fired. A heading in
  that state also stops matching the indexer's own regex, so the section
  quietly drops out of site search.
- **`make-release.sh` did not bump the new pair's version banners.** Added
  `FEATURES.md` and `FEATURES.html` to `bump_doc_banners` and `RELEASE_PATHS`,
  plus an anchored pattern for the guide's `· Feature Guide` hero badge. Two
  releases have already needed follow-up commits to fix versions the release
  script left stale; this keeps the count from growing.
- **`unit-doc-parity.py` did not guard the new pair.** `FEATURES.md` ↔
  `FEATURES.html` is now in `PAIRS` and passes with **zero declared
  exceptions** — the two files were aligned to one heading structure rather
  than granted 50 allowances. Feature names are `h2`, skills are `h3` (so site
  search indexes them; the index reads `h1`–`h3` only), and phase groups are
  visual labels in both files rather than headings, so a divider named "Plan"
  never lands in search results.

### Added — Kiro (Amazon's agentic IDE) as a third harness

The pack previously supported Claude Code and VS Code Copilot. A Kiro user
got exactly one thing: the root `AGENTS.md`, which Kiro discovers natively
as always-on steering — and whose every pointer aimed at `.github/*` or
`.claude/*`, paths Kiro never reads. A table of contents for a book that
wasn't there.

Every schema fact below was verified against a real **Kiro 1.0.337**
install by reading the zod schemas and bundled system prompts inside the
shipped `kiro-agent` extension, **not** from kiro.dev. The docs are wrong
in three places that would each have shipped a silently-broken file:

- Agent files are documented as `.kiro/agents/*.json`. The binary requires
  **markdown with YAML frontmatter** — Kiro's own bundled authoring
  guidance says *"Agent files MUST be markdown files with .md extension"*.
- `allowedTools` and `toolsSettings` are recommended by the docs but sit in
  the parser's `hasCliOnlyFields` list, so the IDE **ignores both**.
- The hook schema shipped at `extension-resources/hook.json` is the
  **deprecated** `when`/`then` format, which has no shell-command action at
  all. The live format is `{"version":"v1", hooks:[…]}`.

`.assert-iq/kiro-harness.md` records the whole contract, including what
remains unverified, so the next person doesn't re-derive it.

**Surfaces.** `.kiro/steering/` (instructions), `.kiro/agents/` (lead,
planner, 8 specialists), `.kiro/skills` (symlink to the one canonical
`.github/skills` tree — all three harnesses now run byte-identical
skills), `.kiro/hooks/` (Dreaming), `.kiro/settings/mcp.json`.

**Generated, not hand-maintained.** `scripts/sync-kiro.{sh,ps1}` renders
steering from `.github/instructions/` (mapping `applyTo` →
`inclusion`/`fileMatchPattern`) and the specialists from
`.claude/agents/specialists/` (mapping Claude tool names → Kiro capability
**tags**, per Kiro's own guidance that tags survive tool renames while
names do not). Hand-maintaining the QI rulebook across three harnesses is
what failed at v2.0; two was already one too many.

The rejected alternative was thin steering files pointing at
`.github/instructions/` via Kiro's `#[[file:…]]` reference. A Kiro-only
consumer who never installed `.github/` gets a dangling reference that
degrades **silently** — the exact failure shape this pack keeps hitting.
Generation plus `--check` fails loudly.

**Dreaming ports** because Kiro's v1 hooks support `SessionStart` and
`Stop` with `action.type: "command"`. Two new templates, rendered by the
installer. Kiro substitutes `${WORKSPACE_ROOT}` (its only substitution,
and its `CLAUDE_PLUGIN_ROOT` equivalent); the installer-baked
`__PACK_ROOT__` is the fallback. Commands name their interpreter
explicitly because Kiro spawns with `shell:true` — `/bin/sh` on POSIX,
`cmd.exe` on Windows.

**New `AIQ_HOOK_OUTPUT` protocol switch** in `dream-utils.{sh,ps1}`.
Claude Code and Copilot read hook stdout as a JSON envelope; Kiro forwards
`SessionStart` stdout **verbatim**, so the Claude envelope would be pasted
into the user's chat at every session start. `plain` emits the nudge text
alone and nothing when there is no nudge. Default is unchanged
(`claude`) — adding a third harness must not change what the first two
receive.

**MCP** translated to `.kiro/settings/mcp.json`: `mcpServers` not
`servers`, no `type` field (transport inferred), `${ENV_VAR}` instead of
`${input:…}` (Kiro cannot prompt), and `${AIQ_REPO_PATH}` instead of
`${workspaceFolder}`. All 20 servers ship `disabled: true`. The gotcha
`.kiro/settings/MCP.md` documents: exporting the variable is **not
enough** — Kiro expands `${VAR}` only for names approved in
`kiroAgent.mcpApprovedEnvVars`, and an unapproved one stays literal, so the
server starts, sends `Bearer ${ADO_PAT}`, and fails to authenticate with no
hint that no substitution occurred.

**Installers.** `install.{sh,ps1}` render the hook file and link
`.kiro/skills`; `scripts/bootstrap.{sh,ps1}` gain `--kiro=workspace|skip`
(`-Kiro`) with manifest, uninstall and trial-mode coverage. No `user`
scope: Kiro does resolve `~/.kiro/`, but global-vs-workspace precedence per
file name is unverified, and shipping an unverified scope would be the
quiet half-support this release removes.

**Tests.** New `unit-kiro-schema.py` (40 assertions) validates all four
surfaces against the schema the binary enforces; mutation-tested to confirm
it catches a missing agent resource glob, a `fileMatch` with no pattern, a
reintroduced `type` field, and a hook that loses the plain output protocol.
New parity checks **P7** (generated Kiro files current) and **P8** (the two
sync implementations' tool maps agree), mirroring P5/P6.

### Fixed — generated-file `--check` was line-ending dependent

Pre-existing, found while adding the Kiro syncs and reproduced on both. On
Windows with `core.autocrlf=true` (the **default**), a clean clone checks
the generated markdown out as CRLF, because `.gitattributes` had `*.md
text`. The bash `--check` modes compared LF-rendered output against raw
bytes, so **every generated file came back STALE** — telling a maintainer
on a fresh Windows clone that their generated agents were out of date when
they were byte-correct, and failing parity check P5 for a reason unrelated
to parity. Only the bash side was affected; both `.ps1` syncs have always
normalized on read.

Fixed twice over: `.gitattributes` pins the three generated trees to
`eol=lf`, and both bash scripts strip CR before comparing (which also
covers a hand-copied tree whose attributes never applied).

### Fixed — a full install wrote a 0-byte manifest on Windows

Also pre-existing, also latent until the Kiro surfaces crossed the
threshold. `manifest_write` passed the whole entry array to `jq` via
`--argjson`, which puts it on the **command line**: 138 entries of absolute
paths is 36,503 bytes against MSYS/Windows' ~32KB argv limit. `jq` died with
*"Argument list too long"*, but the shell had already truncated the target
via `>`, so the install **reported success and left a 0-byte manifest**.

That is the worst possible shape. The manifest is what uninstall reads to
know what to remove and what upgrade diffs against — an empty one means the
pack has silently lost track of everything it installed, uninstall becomes a
no-op that claims to have worked, and the next upgrade sees a fresh install.

Now uses `--slurpfile` (same JSON, read from disk, no argv cost at any
count), and both branches stage to a temp and `mv` only on success, so a
failed write leaves the previous manifest intact and returns non-zero.
`bootstrap.ps1` was never affected — it builds JSON natively.

### Fixed — installing into a workspace that already had its own skills broke every Assert.IQ skill

Reported from the field. A developer installed into an existing Kiro
workspace that already held **his own skills** in `.kiro/skills`. Afterwards
he could not invoke a single Assert.IQ skill. `.kiro/skills.assert-iq-new`
held all 31 of ours; `.kiro/skills` still held only his.

The sidecar did its job — it refused to destroy his work — but the outcome
was still a broken install, because **Kiro reads only `.kiro/skills`** and a
sidecar directory is invisible to it. The skills surface is one directory,
and the installer wanted to own the whole thing: a symlink cannot express
"his skills *and* ours".

**The skills destination is now merged, not claimed.** Three cases, one rule
— reclaim what is ours, merge into what is not, never delete what we did not
put there:

| Destination | Before | Now |
|---|---|---|
| absent | symlink | symlink (unchanged) |
| pack-owned symlink | unchanged | unchanged |
| **empty directory** | sidecar → install broken | reclaimed, symlinked |
| **pack copy from a prior run** | sidecar → re-install broke itself | reclaimed, symlinked |
| **user's own skills** | sidecar → skills unreachable | **merged in alongside** |
| a *file* named `skills` | sidecar | sidecar (loudly) |

"Ours" is decided by comparing bytes, not by consulting the install
manifest. The manifest is exactly what is unreliable in this situation: it
can be stale, it can predate the entry, and it has been observed written as
0 bytes when a `jq` call blew the Windows argv limit. Bytes on disk cannot
lie. A file the user edited, or one they added, makes the whole directory
non-disposable.

**Uninstall is surgical.** The merge copies per file through the same
`copy_tree` / `Copy-TreeScoped` path everything else uses, so every file we
add gets its own manifest entry. `--uninstall` removes exactly those and
leaves the user's skills untouched — and the directory itself survives,
because the empty-directory sweep only removes a directory that is actually
empty. Verified end to end: a workspace with 2 user skills went to 33 after
install, back to exactly those 2 after uninstall, content intact.

The trade-off, stated plainly: merged skills are **copies**, so they do not
auto-update the way the symlink does. Re-running the installer refreshes
them. That is the price of sharing the directory, and it is worth it — a
stale skill is recoverable, an unreachable one is not.

**`install.sh` / `install.ps1` had a worse version of the same bug.** Their
skills step called `rm -rf` on the destination unconditionally. Since both
are documented as "run after dropping the pack into a repo", that path can
be the user's own repo — so a user who kept skills in `.claude/skills` or
`.kiro/skills` had them **deleted outright**. Silent data loss, not just
breakage. Both now reclaim only what is theirs and merge otherwise.

All of this applies to `.claude/skills` too — the logic is shared, and the
same latent bug was there for Claude Code users the whole time. Kiro just
surfaced it, because a Kiro workspace is far more likely to already have a
`skills` directory in use.

Regression coverage: case 45 in `e2e-bootstrap.sh` and its twin case 46 in
`e2e-bootstrap.ps1` exercise all three directory states plus the surgical
uninstall. Verified to fail against the pre-fix installer.

### Fixed — 3 skills had no frontmatter and were invisible to Kiro

`assert-iq-bootstrap`, `define-quality-rubric` and `grade-with-rubric`
opened straight at `# /skill-name` with no YAML frontmatter. The Agent
Skills standard requires `name` + `description`, so Kiro rejected all three
(`skill.frontmatter.missing`) and they were simply absent — no slash
command, no auto-routing, no error. 27 of 30 skills worked; 3 did not,
invisibly.

Pre-existing, and it survived because the other two harnesses are lenient:
Claude Code fell back to the H1 heading, so the skills listed with a
description of literally `/assert-iq-bootstrap`. Degraded but present, and
nothing enforced the standard. Adding a strict harness surfaced it in the
first live run. `unit-kiro-schema.py` now asserts frontmatter on all 30.

### Verified against a running Kiro

Kiro 1.0.337 was opened on this repo and its logs read back:

- `v2 hooks loaded 2 standalone hooks from .kiro/hooks/` — the v1 hook
  schema is accepted as written.
- `skill.validation.failed` count went **6 → 0** after the frontmatter fix;
  all skills now validate.
- `hooks.v2.executionDisabledUntrustedWorkspace` — the untrusted-workspace
  behaviour documented in the contract, confirmed live. Hooks *load* but do
  not *execute* until the folder is trusted.
- **Dreaming runs end to end.** With the workspace trusted, Kiro fires the
  `SessionStart` gate and the `Stop` recorder and the memory store updates —
  confirmed by the pack author in a separate workspace. This was the last
  unproven link in the chain: the v1 hook schema, the `${WORKSPACE_ROOT}`
  substitution, the `shell:true` interpreter handling, and the
  `AIQ_HOOK_OUTPUT=plain` protocol switch are all exercised by that path.

A real install was also performed by the author into a separate workspace
with Kiro, independently of the fixtures below.

Full bootstrap install **and uninstall** verified end to end on
`bootstrap.ps1`: 37s install, 9s uninstall, 138 manifest paths (24 Kiro),
31 skills visible through the `.kiro/skills` symlink, trial-mode exclude
written and removed, **0 leftover files**, and `.github/skills` intact
afterwards — the symlink-delete trap does not fire.

### Known gaps

- The `bootstrap.sh` uninstall completes its `.kiro`, `.claude` and
  `.github` removal correctly but its `.assert-iq` sweep is very slow under
  MSYS. That is the documented MSYS penalty `bootstrap.sh` already refuses
  to run into by default (it must be overridden with `AIQ_ALLOW_MSYS=1`);
  Windows users are directed to `bootstrap.ps1`, which is clean and fast.
- Brace expansion in Kiro's `fileMatchPattern` is unverified, so
  `sync-kiro` expands braces into explicit array entries rather than
  betting on it.
- Steering *content* reaching the model, and specialist sub-agent
  delegation, were verified structurally (schema + Kiro's own loader logs)
  rather than by inspecting a live conversation.
- `unit-legacy-exclude-strip.sh` covers a `bootstrap.sh` code path, so it
  reports NOT APPLICABLE on Windows (see above). The same behaviour has no
  `bootstrap.ps1` twin yet, so that fix is currently unguarded on Windows.

---
### Fixed (the /dream safety procedure was documented but unwired)

`qi-foundation.instructions.md` > *Memory Poisoning Prevention* promised four
things around `/dream`: sanity checks, a memory snapshot, an append-only
provenance record, and a post-dream golden-corpus regression check. **None of
them existed.** Nothing anywhere wrote `provenance.json`, `.snapshots/` stayed
empty, and the `/dream` skill never mentioned steps 1, 2 or 4.

The cost went past tidiness. The reproducibility contract in the same
instruction file opens with `tar xzf .snapshots/mem-<version>.tar.gz` — a step
that **could never have worked**, because no snapshot was ever taken.

`integration-dream-provenance.sh` passed the whole time: it asserted only that
`provenance.json` existed and parsed, never that anything wrote to it. An
existence check on an append-only audit log is close to worthless on its own,
so it now also asserts the producer exists and that `/dream` invokes it. Both
new checks fail against the previous state.

- **New `.assert-iq/analysis/dream-safety.py`** implements the deterministic
  half of the procedure: `pre` (sanity, snapshot, open cycle, prune to
  `snapshot_retention`), `post --cycle-id` (record `memory_version_after`), and
  `regression --cycle-id --results` (divergence vs. the golden corpus). One
  stdlib-only Python file rather than a `.sh`/`.ps1` pair — the pack already
  resolves an interpreter on every platform, so this adds no second parity
  surface. Exit codes are the contract: **0** proceed, **1** blocked, **2**
  environment error.
- **Gates follow the maturity tier**, as the instruction says: `higher`
  enforces, `early`/`mid` warn. A blocked run still takes its snapshot, so a
  refused dream leaves a restore point.
- **The judgement half stays with the model.** A script cannot reproduce a risk
  assessment, so `/dream` re-runs the corpus and writes JSONL; the script does
  the divergence maths and the gate. The unimplementable half was not faked.
- **`/dream` now invokes both steps**, and `qi-foundation.instructions.md` was
  rewritten so the instruction and the implementation describe the same thing.
- Sanity results come from `memory-sanity.py`'s individual check functions
  rather than by parsing its printed report, so a wording change there cannot
  silently turn the gate into a no-op. Provenance is written via a temp file and
  `replace()`; an interrupted run would otherwise truncate the audit log and
  lose every prior cycle. Cycle ids disambiguate with a `-2` suffix, since the
  stamp is second-resolution and a duplicate id would make the log ambiguous
  and let the second run overwrite the first one's archive.

### Fixed (uninstall left a stranded block in `.git/info/exclude`)

Found on a real project after a manual uninstall: `.github/`, `.vscode/`,
`.claude/`, `CLAUDE.md` and `AGENTS.md` were **still ignored by git** with the
pack long gone. `git check-ignore` confirmed a new `.github/workflows/ci.yml`
would have been silently invisible to git — a CI workflow that never gets
committed, with no error to explain why.

`strip_exclude_block` only ever matched the exact managed marker pair
(`# >>> assert-iq trial mode (managed) >>>` … `<<<`). The block in that
workspace had a human-worded header and no delimiters, so uninstall could not
see it, printed *"No Assert.IQ managed block found — nothing to remove"*, and
exited successfully. That header string appears nowhere in this repo or in any
commit in its history, so no version of the scripts wrote it — most likely an
agent hand-rolled it from the bootstrap skill's prose instead of running the
script. The same blind spot affected `--graduate`.

Both installers now fall back to an unmarked-block sweep before reporting
nothing to remove. It is allowlist-driven and deliberately conservative: it
starts only at a comment naming Assert.IQ, swallows the explanatory comments
that follow, then removes only paths a trial install is known to write. The
first unrecognized line ends the block — a blank line, an unowned path, or a
comment once the paths have started, so a user comment written directly beneath
the pack entries is kept. An exclude file with no pack content is left
byte-identical.

Covered by `unit-legacy-exclude-strip.sh`, which fails 5 checks against the
previous installer, including the original symptom.

### Added (`/calibration-report`)

The skill tracked as "Phase 6, not yet created" since v1.7.0. `calibration.py`
already computed Brier score, confusion matrix, per-layer fidelity and drift;
there was no skill to run and interpret it, so the capability was unreachable
from chat. The skill wraps the existing script — it does not reimplement the
maths — and interprets the output against the maturity tier, leading with a
verdict on the verdicts rather than pasting JSON. **31 skills total** (was 30).

### Changed (two stale work logs no longer ship to clients)

`IMPLEMENTATION_SUMMARY.md` and `README_REVIEW_SUMMARY.md` are point-in-time
engineering logs from the v1.7.0-alpha1 cycle, and both installed into every
consumer workspace. They carried claims that were already false — "57/57 tests
passing" (the suite is 29), "No commits made — ready for review before
integration", and a Known Limitations table still marking as pending three
things that had shipped. A client opening `.assert-iq/` read a half-finished
product.

Both are now excluded from the install payload in `bootstrap.sh` and
`bootstrap.ps1`, using the same `NonPayload` mechanism that stopped shipping
the pack's own test suite — so an upgrade also cleans them out of existing
installs. They stay in the pack repo as history, each with a banner marking it
a historical record. What a release contains is the CHANGELOG's job.

---

## [2.1.2] — 2026-09-03

### Changed (install documentation rewritten for a first-time reader)

Feedback from people trialling the pack: the install instructions were hard
to follow and never made clear which commands belonged to which operating
system.

**Landing page (`README.md` / `README.html`).** Getting Started now covers
install, update, and uninstall, each split into **On a Mac** and **On
Windows**. Install surfaces trial mode only; the other paths and flags
(`--graduate`, `--mode=committed`, the three presets, Path A) moved to
`README.assert-iq.md`. The *Presets vs modes* explainer and the preset
comparison table existed **only** on the landing page, so they were moved
rather than deleted.

**The environment check is now an explicit step**, 3 of 4, flagged as
not-skippable, with a section explaining which of its verdicts block you
(`Not ready`) and which do not (`WARN`). It was previously a passing mention
that was easy to miss. It is placed *after* `cd`-ing into the target project
rather than before: `check-environment` inspects the directory it runs from —
whether that is a git repo, whether the pack is already installed there — so
run from the pack folder it reports on the wrong directory and warns "not
inside a git repo".

**Deep doc (`README.assert-iq.md` / `.html`).** Every code block mixed both
platforms, so copying one ran the macOS command *and* the Windows command.
All eight are split and labelled. Added a glossary of the nine terms the
document leans on (project, pack folder, trial mode, user-global, symlink,
surface, skill…) and replaced jargon in place — *idempotent*, *TTY* /
*non-TTY*, *chicken-and-egg*, *à la carte*, *PAT*.

### Fixed (install commands that pointed at the wrong directory)

- **`--uninstall` and `--graduate` were documented as
  `scripts/bootstrap.sh --uninstall`** — a relative path implying you are
  standing in the pack folder. `bootstrap.sh` sets `WORKSPACE="$PWD"`, so run
  that way it targets the pack folder rather than your project: following the
  documentation literally did not uninstall the thing you meant. Every
  example now `cd`s into the project and points at the pack by full path,
  with the rule stated explicitly.

- **PowerShell paths were inconsistent** — `~\…` in the deep doc versus
  `$HOME\…` on the landing page. Standardised on `$HOME\`, which is
  unambiguous on both Windows PowerShell 5.1 and PowerShell 7.

- **Troubleshooting carried no platform-specific entries**, although platform
  failures are what newcomers actually hit. Added six, each drawn from the
  codebase rather than invented: `pwsh` vs `powershell`, `python3` not
  existing on Windows, the Developer Mode symlink/copy fallback
  (`bootstrap.ps1:2363`), the CRLF `$'\r': command not found` error (verbatim
  from `.gitattributes`), running from the wrong folder, and skills not
  appearing until the editor is reloaded.

- **Duplicate `id="get-started"` in `README.html`** — introduced by the
  heading rename, since `<section>` already carried that id. Invalid HTML,
  and `build-search-index.py` would have emitted `get-started-2` for the
  heading. The id now lives on the heading alone.

- **The environment requirements table contradicted the new instructions**,
  still advertising `install.sh` and "jq required for `bootstrap.sh
  --upgrade`" when neither appears on the page any more.

Verified by executing every documented macOS command against a scratch repo
(`check-environment.sh`, `--mode=trial`, `--uninstall --dry-run`,
`--graduate`, `--uninstall`), and by checking all six documented PowerShell
flags against `bootstrap.ps1`'s `param()` block. No PowerShell is available
on the authoring machine, so the Windows commands are verified against the
scripts' parameter definitions rather than by execution.

---

## [2.1.1] — 2026-08-27

### Changed (qi-traceability.instructions.md is now language-agnostic)

Run through `/eval-optimizer` as project instructions (TC 35% / OQ 35% /
Eff 15% / Rob 15%) against five cases. Composite **52.7 → 83.7** against a
43.4 baseline, converged in one iteration. The original scored **87 on .NET
and 30–35 on every other stack**, and on two of the five cases it scored
*below* baseline — applying it to a TypeScript or Go task was worse than
having no instruction, because its only worked examples were C#/XAML.

- **`applyTo` was `"**/*.{cs,xaml}"`** — the narrowest glob of all six
  instruction files. In Copilot the file never loaded for `.ts`, `.py`, or
  `.go`, so on most stacks its contribution was zero while the body
  reinforced the limit ("production C# / XAML code"). Now 21 source
  extensions. The default is deliberately **inclusive** so a fresh install is
  never silently inert; `/assert-iq-tailor` narrows it. That inversion is the
  actual fix — shipping exclusive meant the pack's traceability rule did not
  apply to the majority of repos that install it.

- **It never referenced its own configuration surface.** `config.yaml`
  defines 10 `traceability.marker_style` values and designates this file as
  `traceability.rules_path` — the config points at it. The file documented
  **none of the ten by name**, describing seven language families in prose
  instead, so `marker_style` could not be resolved by matching at all;
  `generic` (the shipped default) had no counterpart, and
  `python_decorator`, `rust_doc`, `ruby`, `swift_doc` had no coverage even in
  prose. New §1 carries the table verbatim from config, adds the precedence
  rule (**configured value wins over language idiom**, so a polyglot repo
  that standardizes stays parseable), and a stated-substitution fallback.

- **38 of 71 lines were MAUI / Xamarin.UITest specifics** — three
  near-identical C# blocks anchoring the file to a stack that reached end of
  support in May 2024. Generalized to §5 "markup paired with code-behind"
  (MAUI/Xamarin XAML, Razor, Vue/Svelte SFCs) with the .NET examples kept as
  instances and a JS/TS example added. The `[TestFixture]` example was
  dropped: it traced *test* classes, which `qi-test-design.instructions.md`
  owns. That costs the .NET case 2.5 points and buys ~50 on every other
  stack.

- **Added** the boundary that was missing entirely — what does *not* carry a
  marker (private helpers, renames, refactors, generated code, tests), since
  over-tagging makes the matrix noisy enough to be ignored — and a
  no-fabrication rule for missing work-item IDs: emit
  `work-item="TODO(qi-trace): unresolved"` and say what is missing. A guessed
  ID produces a matrix that looks complete and audits false.

- **Preserved verbatim:** the four required fields, and "never silently drop
  or alter an existing trace — flag it and ask." Those were the original's
  genuine strengths and carried cases 2 and 5.

- **New guard:** `unit-traceability-marker-parity.py` asserts every
  `marker_style` enum value in `config.yaml` appears in the instruction file,
  that the active default specifically is documented, and that `applyTo` has
  not been re-narrowed to the .NET-only glob. This drift survived the file's
  entire life with nothing to catch it — the same shape as the generated
  Copilot agents and `docs/html`: two artifacts that must agree, with no
  check that they do. Negative-tested against the original file: 1 PASS / 3
  FAIL.

- `CLAUDE.md` and `/assert-iq-tailor` Phase 5 both described this as the
  C#/XAML file; both corrected. Phase 5 now says to **narrow** the glob and
  to prefer setting `marker_style` over editing the file's table.

**Not verified:** Copilot's glob matcher was not executed, so a 21-extension
brace list is unconfirmed in a live session — worth one manual check on a
`.py` and a `.ts` file.


### Fixed (setup steps /assert-iq-tailor never asked about)

- **`manual_test_management` was absent from the tailor pass entirely.** It
  ships as a working default (`tool: "markdown"`), not a `<PLACEHOLDER>`, so
  "fill every placeholder" never caught it and no phase asked. It drives
  `/generate-manual-test-case`, `/generate-exploratory-charter`, and the import
  format `qi-manual-test-design.instructions.md` expects — a team on ADO Test
  Plans, Xray, Zephyr, or TestRail silently kept generating markdown into
  `./tests/_qi/manual/`. Working defaults that are wrong for most teams are
  worse than placeholders: they satisfy every "unfilled value" check.
  Now detected in Phase 1, asked in Phase 2, and set in Phase 3.

- **`signals.sink` and `dreaming` were dangling forward references.** Phase 5
  told the agent to point CI emission at "the configured signal sink" and
  Phase 6 read `dreaming.*`, but Phase 3 configured neither. Both are now set
  in Phase 3, where every other key is.

- **`client.account_id`** was missing from Phase 3's client list while shipping
  as a live `<Engagement or project ID>` placeholder, so it survived the pass.

- **The generated Copilot specialist agents were unguarded.** The skill did not
  mention agents at all, and no skill in the pack mentioned `sync-agents`.
  Phase 6's opt-in deep mode invites body rewrites, with nothing to stop that
  from reaching `.github/agents/specialists/*.agent.md` — which is GENERATED
  from `.claude/agents/specialists/*.md`. Editing the generated side is
  reverted by the next sync; editing the source without syncing fails parity
  checks P5/P6. Now an explicit out-of-scope note plus an anti-pattern.

- **The environment doctor was referenced by no skill.**
  `scripts/check-environment.{sh,ps1}` shipped in 2.1.0 unreferenced. Phase 0
  now runs it and calls out the two failures that make a tailoring pass
  actively misleading: no working Python 3 (the calibration, memory-sanity and
  verdict tooling the config points at cannot run) and `.claude/skills` present
  as a copy rather than a symlink (Claude reads a stale snapshot, so
  skill-facing config changes appear to do nothing).

### Changed (model IDs default to claude-opus-5)

- `oracle.grader.model` was `"claude-3-5-sonnet"` and
  `dreaming.background_service.model` was `"claude-Opus-4-8"` — the second is
  not a valid model ID at all (note the capital O). Neither key is read by any
  code, so nothing ever failed and nothing surfaced the error; a wrong ID in
  config appears only at the first real call. Both now default to
  `claude-opus-5`, as does the one value that IS consumed at runtime, the
  hardcoded `DreamConfig.model` in `dreaming/service/dreaming_service.py`
  (previously `claude-sonnet-4-6`, valid but older-generation).
- Documented examples updated to match: `/grade-with-rubric`'s sample verdict,
  `ORACLE_QUICK_START.md`, and `oracles-readme.html`.
- `/assert-iq-tailor` Phase 3 now validates model IDs rather than trusting the
  shipped default, and records these two as the reason the check exists.

### Fixed (Windows PowerShell 5.1 wrote a BOM into every merged JSON file)

`Write-AtomicFile` in `scripts/bootstrap.ps1` -- the single writer behind the
install manifest, `.claude/settings.json`, `.vscode/settings.json` and every
marker-merged markdown file -- staged its temp file with
`Set-Content -Encoding $Encoding`, `$Encoding` defaulting to `'UTF8'`. On
Windows PowerShell 5.1 (the host on a stock Windows box, and one the pack
declares supported and tested) `-Encoding UTF8` means UTF-8 **with** a BOM.
PowerShell 7 means UTF-8 *without* one, which is why no pwsh-7 or macOS run
ever surfaced this.

Symptom: every install on 5.1 wrote `.assert-iq/.install-manifest.json`
beginning `EF BB BF`, which `json.load(open(..., encoding="utf-8"))` rejects
outright -- `Unexpected UTF-8 BOM (decode using utf-8-sig)` -- and which a
strict `JSON.parse` refuses in `.claude/settings.json`, silently un-wiring the
Dreaming hooks the installer had just finished writing.

- `Write-AtomicFile` now stages through `Write-AiqUtf8` (.NET
  `UTF8Encoding($false)`), like every other writer in the pack. Its unused
  `-Encoding` parameter is gone. Byte output is otherwise unchanged -- one
  trailing `[Environment]::NewLine` -- so the trailing-newline fixed point in
  `Merge-MarkdownFile` still holds and re-merges stay idempotent.
- **Why the existing guard missed it:** check 1b in
  `unit-script-portability.py` matched the *literal* string `-Encoding UTF8`,
  and this call site named the encoding through a variable. The check now
  flags `Set-Content` / `Add-Content` / `Out-File` in shipped `.ps1` **by
  cmdlet, regardless of arguments** -- no argument to those three is both
  BOM-safe and ANSI-safe across 5.1 and 7, so the rule is now simply "shipped
  PowerShell writes text through `Write-AiqUtf8`."



### Fixed (verdict recording was dead on a stock Python 3)

`.assert-iq/analysis/verdict-recorder.py` imported `yaml` at module scope.
PyYAML is declared nowhere in the pack -- no `requirements.txt`, no `pip` call
in either installer -- and the README lists bare "Python 3" as the only Python
requirement. On a stock interpreter the import took the whole module down,
including `VerdictRecorder` and `compute_memory_hash`, neither of which touches
YAML. Verdict recording was therefore inert on Windows, macOS, Claude Code and
Copilot alike -- and with it the reproducibility contract and audit trail that
`qi-foundation.instructions.md` promises.

- `yaml` is now imported lazily inside `load_config`, with a stdlib fallback
  reader for the block-mapping subset of `config.yaml`. Returning `{}` instead
  would make `are_verdicts_enabled()` False and silently disable the audit
  trail rather than failing loudly. The fallback omits block scalars and block
  sequences rather than guessing at them, so it can never hand back a
  plausible-looking wrong value. Cross-checked against PyYAML 6.0.3 over the
  whole config: 0 disagreements, 0 invented values.
- `VERDICT_INTEGRATION_GUIDE.md` shipped a copy-paste reimplementation of
  `compute_memory_hash` carrying three of the hashing bugs below; it now points
  at the library instead.
- New guards: `unit-verdict-recorder-stdlib.py`.

### Fixed (`memory_version` differed by platform on an unchanged memory store)

`compute_memory_hash` is what makes a verdict reproducible -- it stamps the
state of `.assert-iq/memory/` into every verdict record. Four defects made the
same store hash differently depending on where it was hashed, which surfaces
downstream as memory drift on a store nobody edited.

- **Ordering depended on the host.** `sorted(Path.rglob("*"))` collates
  case-sensitively on POSIX and case-folded on Windows, so a store holding
  `MEMORY.md` and `apple.md` reached the digest in a different order per
  platform. Now sorted on the relative POSIX path.
- **Line endings depended on the checkout.** `.gitattributes` marks `*.md` as
  `text` without pinning `eol`, so topics arrive CRLF on Windows and LF on
  macOS. Text is newline-normalized before hashing; files containing NUL are
  treated as binary and hashed verbatim, matching how git detects binary.
- **Desktop metadata moved the hash.** Opening the memory store in Finder makes
  macOS drop a `.DS_Store` there. It is gitignored, so the tree looks clean
  while `memory_version` silently moves. Now skipped, along with AppleDouble
  `._*` sidecars and Explorer's `Thumbs.db` / `desktop.ini` -- the list both
  installers already skip.
- **Contents were unframed.** Files were concatenated with nothing marking the
  boundaries, so distinct stores collided (`"ab"+"c" == "a"+"bc"`), empty files
  were invisible, and renames went undetected -- including a fact migrating
  between topics, which is exactly what `/dream` does. Each file now
  contributes a length-prefixed `(path, content)` record, with paths
  NFC-normalized so macOS (which reports decomposed filenames) does not split
  from Linux and Windows.

The emitted value is tagged `sha256-v2` so verdicts stamped by the previous
algorithm stay distinguishable; without the tag this change would itself read
as memory drift rather than an algorithm change. Nothing validates the prefix
(`signal-schema.json` types it as a plain string). New guards:
`unit-memory-hash-portability.py`.

### Fixed (calibration's rolling window and drift detection silently did nothing)

`.assert-iq/analysis/calibration.py` parsed `issued_at` into a naive datetime
and compared it against `datetime.utcnow()`. Where the timestamp carried an
offset the comparison raised `TypeError`, which the surrounding
`except (ValueError, TypeError): pass` swallowed -- so both failures were
invisible:

- `compute_brier_score` counted every verdict regardless of age, so
  `--window-days` filtering never applied;
- `drift_detection` appended nothing, leaving `windows` permanently empty, so
  the >0.15 Brier degradation alarm could never fire at all.

Both now route through `parse_issued_at()`, which pins parsed values to UTC and
treats offset-free timestamps as UTC -- which is how `verdict-recorder` writes
them. Unparseable timestamps are kept in the Brier window rather than dropped,
and excluded from drift buckets, since neither can be placed in or out of a
window. Covered by `unit-calibration-basic.py`.

### Fixed (the version-history "Unreleased" row was never promoted at release)

v2.1.0 published with the newest version-history row in `README.assert-iq.md`
still labelled **Unreleased**, while every version banner on the same page read
v2.1.0. `bump_doc_banners` deliberately leaves version-history rows alone -- it
must not rewrite historical entries -- and nothing else renamed the row, so it
was never going to update itself.

- `make-release.sh` gains `promote_unreleased_row`, run right after
  `bump_doc_banners`.
- `e2e-version-consistency.sh` check E2E-17c asserts the version-history table
  has no `Unreleased` row at the released version.


## [2.1.0] — 2026-08-27

**Windows is now a first-class, verified platform for both harnesses.** All four
supported variations (Windows/macOS x Copilot/Claude Code) are covered, with the
PowerShell suites run under **both** Windows PowerShell 5.1 and PowerShell 7 — a
green run on one says nothing about the other, and four 5.1-only defects were
hiding behind a passing 7 run.

Highlights:

- **Dreaming session hooks actually fire under Copilot.** They had never run on
  Windows: `$`-prefixed tokens were stripped before PowerShell parsed the command.
- **Uninstall leaves nothing behind.** Two classes of orphan fixed, plus a memory
  store that is now preserved on consolidated knowledge rather than mere activity.
- **`bootstrap.ps1 -Upgrade` applies the update.** It silently dropped it whenever
  the baseline came from a git tag.
- **New environment doctors** (`scripts/check-environment.{sh,ps1}`) and an
  **Environment requirements** section in the README.
- **Copilot reaches parity with Claude Code** on the specialist tier, including
  real `agent/runSubagent` delegation, generated from a single source of truth.
- **~16 new test files**, most notably behavioural coverage that executes the hooks
  instead of inspecting their shape.

Note for existing installs: if you have never run `/dream`, uninstall now discards
the un-consolidated session-log trail (it is `/dream`'s input, not its output). Any
single `/dream` that records a fact keeps the whole store. Removal is never silent.


### Added

- **Cross-harness agent sync.** `scripts/sync-agents.sh` / `scripts/sync-agents.ps1`
  render `.github/agents/specialists/*.agent.md` from `.claude/agents/specialists/*.md`,
  mapping tool names between the two schemas (`Read`->`codebase`, `Grep`/`Glob`->`search`,
  `Bash`->`runCommands`, ...). The Claude files are now the single source of truth for
  the specialist tier; the generated Copilot files carry a DO-NOT-EDIT banner.
  `--check` / `-Check` verifies freshness, `--print-map` / `-PrintMap` emits the table.
- **Copilot specialist tier + delegation (parity with Claude Code).** `.github/agents/`
  gains the 8 generated specialists, and `Assert-IQ.agent.md` gains the
  `agent/runSubagent` tool plus an `agents:` allowlist and an orchestration section,
  so Copilot can actually delegate rather than only routing to skills.
- **`e2e-agent-parity.sh` checks P5 and P6.** P5 fails when the generated Copilot
  specialists are stale; P6 fails when the bash and PowerShell tool maps diverge
  (otherwise the generated agents would differ depending on which OS ran the sync).
- **Test dependency preflight** (`unit-test-dependencies.sh`) now creates the git-ignored
  runtime sinks (`verdicts/archive/`, `dreaming/.snapshots/`,
  `business-metrics/reports/`) when they are absent, instead of letting 5 suites fail
  with cryptic "Archive directory missing" style errors. They are empty directories that
  git cannot carry, so a fresh clone or a CI checkout never has them; demanding an
  install first put the suite red on exactly the setups it protects. The installer's
  obligation to create them is asserted separately, against a real install, by case 41
  of `e2e-bootstrap.{sh,ps1}`.
- **Environment doctor.** `scripts/check-environment.sh` / `scripts/check-environment.ps1`
  report every requirement, what was found, and the exact fix -- host/shell version, git,
  a working Python 3, jq, symlink capability, shell line endings, and the shape of an
  existing `.claude/settings.json`. Documented as the first step in the README's new
  **Environment requirements** section. Blocking issues exit non-zero; warnings mark
  reduced functionality only.
- **`.gitattributes`** (the pack never had one). Pins `*.sh`/`*.py` to `eol=lf` and
  `*.ps1` to `eol=crlf` so a checkout is byte-correct regardless of `core.autocrlf`.
- **`unit-script-portability.py`** locks down both encoding rules: `.ps1` files must be
  ASCII-only or BOM-marked, and tracked `.sh`/`.py` must be LF in the index and covered
  by an `eol=lf` attribute.

### Changed (uninstall preserves memory on knowledge, not on activity)

- **Uninstall left `.assert-iq/memory/` behind on every workspace once the session
  hooks started firing.** The preserve rule triggered on three conditions, two of
  which are metadata rather than knowledge: any file under `logs/`, and `MEMORY.md`
  not saying `Last consolidated: never`. `logs/` is the waking-loop trail that
  `/dream` *consumes*, and the consolidation stamp records only that a dream ran,
  not that it found anything. Both conditions were unreachable while the Copilot
  hooks were broken, so fixing the hooks made every install -> chat -> uninstall
  leave a store behind whose `topics/` was empty and whose index read
  `_(no entries yet)_` under every heading -- an orphan tree holding none of the
  user's knowledge.

  The store is now preserved when it holds actual consolidated knowledge: a
  `topics/*.md` file, or real content in the `MEMORY.md` index (anything left after
  stripping the seed's comment block, headings, consolidation stamp and
  `_(no entries yet)_` placeholders). Deliberately broad -- a hand-written note
  counts as much as a `/dream` pointer, because an orphan directory costs far less
  than deleting someone's notes. When a store IS removed, any un-consolidated
  session logs going with it are named in the output rather than discarded
  silently.

  **Consequence worth knowing:** if you never run `/dream`, uninstall now discards
  the session-log trail. Those logs are one line per session and are `/dream`'s
  input, not its output; a single `/dream` that records anything at all makes the
  whole store sticky again.

- **`e2e-bootstrap.{sh,ps1}` case 36 asserted the old rule** -- it seeded only a
  session log and required the store to survive. It now seeds a real
  `topics/*.md` and asserts the store, the topic AND the un-consolidated logs all
  survive together. New case 42/43 covers the reported scenario directly: a store
  with a session log and a "dream ran" stamp but no facts is removed, the workspace
  is left with nothing but `.git`, and the discarded trail is reported.

### Fixed (Dreaming hooks never fired under Copilot -- found by manual testing)

- **Every Copilot session-event hook was dead, silently.** The rendered hook
  commands used PowerShell/shell variables, and something between the hook file and
  the interpreter substitutes every `$`-prefixed token with nothing, so the Windows
  command arrived as `& {  = if () {  } else { 'C:\...' }; &  }` and died with a
  `ParserError`. `SessionStart` and `Stop` never ran, so the session counter never
  advanced and `.assert-iq/memory/logs/` stayed empty. Nothing surfaced but two
  warnings in the chat pane -- and a hook that cannot start is indistinguishable
  from a hook with nothing to say.

  All four command strings in `session-events.template.json` are now `$`-free: the
  installer bakes in an absolute path, which is all these hooks ever needed, because
  `dream-utils.{ps1,sh}` already derive `AIQ_PACK_ROOT` from their own location. The
  vestigial `CLAUDE_PLUGIN_ROOT` override is gone from the Copilot file, where it
  never applied -- it is a Claude Code variable. The Claude templates are unchanged
  and still use it deliberately.

  The POSIX commands were fixed the same way even though only Windows was reported:
  the failure cannot be plain shell expansion (`$env:CLAUDE_PLUGIN_ROOT` vanished
  whole instead of leaving `:CLAUDE_PLUGIN_ROOT` behind), which means the substitution
  is happening over the raw string and would reach the single-quoted POSIX payloads
  too. They also no longer need `chmod +x`, since they invoke `bash <script>`.

- **The test that was supposed to catch this passed throughout.**
  `e2e-hook-execution.py` ran the Copilot command with `shell=True`, which on Windows
  is `cmd.exe` -- and `cmd.exe` does not touch `$`. It modelled a friendlier
  environment than the real one. It now strips every `$`-token before running the
  command and still asserts the observable outcome (counter incremented, dated log
  written), so the guard fails if a variable is reintroduced. `unit-hook-schema.py`
  adds the cheap static half: no command in the Copilot template may contain a `$`.
  Both were negative-tested by restoring the broken command -- the behavioural one
  reproduces the reported `At line:1 char:12` error exactly.

- **Corrected `.assert-iq/dreaming/README.md`**, which claimed
  `session-events.template.json` renders into `.claude/settings.json`. It renders to
  `session-events.json` and is registered through `chat.hookFilesLocations`;
  `.claude/settings.json` comes from the `claude-hooks.*` templates. The no-`$` rule
  is documented there for anyone editing the templates.

### Fixed (uninstall left orphaned directories behind)

- **`.assert-iq/business-metrics/` survived every uninstall, on both platforms.** The
  business-impact report sink arrived in v2.0 and was never added to either script's
  cleanup lists. Because it is created directly as an empty directory (not copied), it
  never enters the install manifest, so neither the manifest-driven removal nor the
  manifest-derived parent-directory sweep could reach it -- `reports/` kept
  `business-metrics/` non-empty, which in turn kept `.assert-iq/` alive.
- **`.assert-iq/verdicts/` additionally survived on Windows only.** `bootstrap.ps1`'s
  cleanup lists had drifted from `bootstrap.sh`'s and were missing `verdicts`, `oracles`,
  `analysis` and `tests/_qi/regression` entirely. The bash side reaped the verdict
  archive; the PowerShell side did not. The lists are now in parity.
- **Both scripts now treat runtime sinks the way they already treated the memory
  store**: removed when empty (install scaffolding), preserved with an explicit
  `Preserved your ...` line when they hold real content. The verdict archive is a
  regulatory audit trail whose purpose is reproducing a past release decision, so a
  blanket delete would have been a worse bug than the orphan it fixed -- an intermediate
  version of this fix did exactly that, and case 42 is what caught it.
- **Regression coverage:** `e2e-bootstrap.{sh,ps1}` case 40/41 asserts the workspace is
  empty apart from `.git` after uninstall -- deliberately generic, so the next runtime
  sink someone adds is caught automatically rather than shipping as litter -- and case
  41/42 asserts content-bearing sinks survive and are reported.

### Fixed (upgrade path on Windows -- found by the newly ported tests)

- **`bootstrap.ps1 -Upgrade` silently dropped the pack update whenever the baseline
  came from a git tag.** The PowerShell twin of the bash suite was missing five cases,
  so `-Upgrade` had **zero** Windows coverage. Porting them exposed a real defect in the
  tag-fallback path (used whenever an install predates the `.assert-iq/.base` cache, or
  the cache was cleared): the baseline was reconstructed by capturing `git show` into a
  PowerShell variable, which decodes to strings, splits on newlines and re-joins --
  losing the exact bytes. `git merge-file` is byte-oriented, so the reconstructed
  baseline never matched the installed file and every clean three-way merge became a
  whole-file conflict. The user's edits survived (safe direction), but the pack update
  was written to a `.assert-iq-new` sidecar and never applied -- an upgrade that
  reported success without upgrading. Two fixes: a new `Copy-GitBlobToFile` streams the
  blob to disk byte-exactly (what `git show > file` does in bash), and the baseline is
  normalized to the destination's line endings, since git stores LF while the Windows
  working tree is CRLF. macOS is unaffected -- LF throughout, which is why
  `bootstrap.sh` never needed either fix.

### Added (test coverage that was missing entirely)

- **Five bootstrap cases ported to `e2e-bootstrap.ps1`** (35 clean-slate memory seed,
  36 uninstall preserves memory, 37 upgrade merge + conflict + orphan, 38 upgrade base
  cache (tagless), 39 upgrade tag fallback). The two suites are now 43 vs 42 cases and
  the Windows installer's riskiest operation is covered. `Invoke-RunBoot` now keeps the
  bootstrap output (cases 35 and 37 assert on it), plus new helpers: `Invoke-MkSource`
  (tagged/untagged upgrade sources) and byte-preserving fixture edits -- editing with
  `Get-Content | Set-Content` rewrites the whole file and manufactures merge conflicts
  the bash suite never sees.
- **`e2e-bootstrap.ps1` case 40: `install.ps1 -Uninstall` round-trip.** Cases 22/23
  covered only install, reinstall and key preservation. The new case asserts the pack's
  wiring is removed while the user's other `settings.json` keys and their dreamed
  `.assert-iq/memory/` data survive. Negative-tested by sabotaging the uninstall.
- **`unit-generated-docs-current.py`** gates the generated `docs/html/` set against its
  markdown sources, the way check P5 gates the generated Copilot agents. That set had
  been stale since before v2.0.0 with nothing to catch it.

### Changed (Windows host policy)

- **PowerShell 7+ (`pwsh`) is now the documented Windows default; Windows PowerShell 5.1
  remains supported and tested.** Every Windows command in the docs, the installer
  guard messages, and `check-environment.ps1` leads with `pwsh`, with 5.1 named as the
  no-install fallback. This is a documentation/recommendation change, not a support drop:
  the full matrix passes on both hosts (`e2e-bootstrap.ps1` 43/43 and `e2e-dreaming.ps1`
  7/7 under each), so nothing was removed and no 5.1 workaround was reverted.

  5.1 stays a first-class host for a concrete reason: **the session-event handlers invoke
  `powershell`**, and on a typical Windows box that name resolves to 5.1 even when `pwsh`
  is installed. Requiring PowerShell 7 for the *installers* would not change which
  interpreter runs the *hooks* -- the component that fails silently when it breaks. The
  practical reason to prefer 7 is narrower: it can usually create the `.claude/skills`
  symlink where 5.1 falls back to a copy.

  Contributors must run the PowerShell suites under **both** hosts; the suites print
  which host they ran under. Every 5.1 defect fixed below was hidden behind a fully green
  PowerShell 7 run.

### Fixed (Windows PowerShell 5.1 -- found by executing the hooks, not inspecting them)

These four were invisible to every structural check in the suite. All of them are
5.1-only, so a fully green PowerShell 7 run said nothing about them, and 5.1 is the
only PowerShell guaranteed present on a Windows machine.

- **`bootstrap.ps1 -Mode trial` left the entire pack VISIBLE to git.** `Test-Tracked`
  probes each file with `git ls-files --error-unmatch`, which writes to stderr for every
  *untracked* file -- the normal case in trial mode. Under
  `$ErrorActionPreference='Stop'`, Windows PowerShell 5.1 promotes native stderr to a
  **terminating** error, and `2>$null` does not prevent it. So bootstrap aborted after
  copying files but *before* writing `.git/info/exclude`: trial mode did the opposite of
  what it promises. PowerShell 7 was unaffected via
  `$PSNativeCommandUseErrorActionPreference`, which 5.1 lacks. `git` is now shadowed by a
  function that runs git.exe with the preference relaxed, fixing all ~37 call sites at
  once while preserving `$LASTEXITCODE`.
- **Every JSON file PowerShell wrote was unreadable to the pack's Python tooling.**
  `Set-Content -Encoding UTF8` means UTF-8 **with a BOM** on 5.1 and **without** one on 7.
  Python's `json.load` rejects a BOM (`Expecting value: line 1 column 1`), so dream state,
  the verdict archive, the install manifest and `.claude/settings.json` written on a 5.1
  box broke `calibration.py`, `memory-sanity.py`, the verdict recorder and
  `dreaming_service.py`. `-Encoding utf8NoBOM` exists only in PowerShell 6+, so all 14
  write sites now go through a `Write-AiqUtf8` helper backed by
  `UTF8Encoding($false)`. Guarded by `unit-script-portability.py`.
- **The runtime Python readers had no encoding at all.** 18 `open()` calls in
  `calibration.py`, `memory-sanity.py`, `verdict-recorder.py` and `dreaming_service.py`
  used the locale default -- cp1252 on Windows -- which fails on a BOM *and* on any
  non-ASCII content. Reads now use `utf-8-sig` (tolerates a BOM from any producer),
  writes use `utf-8` with `newline="\n"`.
- **`install.sh` on Windows produced a Windows-broken install, silently.** It renders the
  POSIX Claude template (`shell="bash"`, `.sh` hook scripts) and bakes an MSYS pack root
  (`/c/Users/...`) that PowerShell cannot resolve -- so the Copilot `windows` override hit
  `if (-not (Test-Path $s)) { exit 0 }` and **exited successfully having done nothing**.
  It now refuses under MSYS/Cygwin and names `install.ps1`; `--allow-msys` /
  `AIQ_ALLOW_MSYS=1` overrides (the bash suites set it deliberately).
- **The E2E PowerShell harness could not run on 5.1 at all.**
  `ProcessStartInfo.ArgumentList` does not exist on .NET Framework, so `.Add()` threw
  "You cannot call a method on a null-valued expression" for every case. It now falls back
  to the quoted `.Arguments` string, and the suite prints which host it ran under, because
  a green run on one host proves nothing about the other.

### Added (behavioral hook coverage)

- **`e2e-hook-execution.py`** executes the command each harness would actually run on the
  current platform -- Copilot's `osx`/`linux`/`windows` override and Claude Code's
  matcher-group body with its declared `shell` -- and asserts the observable state change
  (`sessions_since_dream` reaches 5, a dated log appears, SessionStart emits the nudge).
  `CLAUDE_PLUGIN_ROOT` is deliberately unset so the baked-in fallback path is under test,
  which is the half that was broken for Copilot on Windows. One implementation covers all
  four supported variations: running it on Windows exercises Windows+Copilot and
  Windows+Claude Code, on macOS the two Mac variations.

### Fixed (Windows environment foundation)

- **`bootstrap.ps1` and `install.ps1` failed to PARSE under Windows PowerShell 5.1,
  installing nothing.** Windows PowerShell 5.1 -- the only PowerShell guaranteed present
  on a Windows box -- reads a BOM-less file as the system ANSI code page, not UTF-8
  (7+ reads UTF-8). `bootstrap.ps1` carried 43 em dashes and 9 box-drawing characters
  written on macOS; under 5.1 the em dash in `"... tracked by git -- using --skip-worktree"`
  became three cp1252 characters, the third a QUOTE, which terminated the string literal
  and produced `Unexpected token 'using' in expression or statement` plus cascading
  `Missing statement block` errors. The README advertised 5.1 support the whole time.
  All five affected `.ps1` files are now ASCII-only, and both installers plus both
  Dreaming hook scripts are verified end-to-end under 5.1 **and** 7.
- **`.claude/skills` silently degraded from a symlink to a copy.** Both installers passed
  the relative target `..\.github\skills` to `New-Item -ItemType SymbolicLink`. NTFS
  resolves a stored relative target against the link's own directory, but PowerShell
  validates `-Target` against the CURRENT WORKING DIRECTORY first -- and bootstrap is
  normally run from outside the target workspace, so validation failed and the `catch`
  fell back to a recursive copy even with Developer Mode enabled. The link is now created
  from inside its parent directory, which keeps the stored target relative (required: the
  pack-owned-link check compares that exact string, so an absolute target would make every
  re-install produce a sidecar).
- **`bootstrap.sh` under Git Bash looked like a hang.** MSYS process creation costs
  ~50-100 ms and a full install copies and hashes ~1000 files one child process at a
  time: measured 9+ minutes for a single install on Windows 11, silent for most of it.
  `bootstrap.sh` now refuses to run under MSYS/Cygwin and names the PowerShell command to
  use instead; `--allow-msys` (or `AIQ_ALLOW_MSYS=1`, which the e2e suite sets) overrides.
  WSL is unaffected. `e2e-bootstrap.sh` also warns up front when run under Git Bash.
- **`dreaming_service.py` was unimportable on Windows.** A module-scope `import fcntl`
  (POSIX-only) meant the optional background dreamer -- and the pack's own sandbox test --
  could not even load. It now probes `fcntl`/`msvcrt` and uses the platform's advisory
  lock, verified to give real mutual exclusion on Windows.
- **`e2e-dreaming.sh` reported four false failures on Windows.** It called bare `python3`
  in five places; the Microsoft Store stub made every state read return empty, which
  surfaced as bogus "gate fired at 3 sessions" errors. All Python now goes through the
  resolver. Suite: 3/7 -> 7/7.
- **`e2e-dreaming.ps1` claimed parity with the bash driver but covered 5 of its 7 cases.**
  Added the time-gate and write-sandbox cases (both negative-tested), and made
  `Resolve-Python` 5.1-safe -- with `$ErrorActionPreference='Stop'`, Windows PowerShell 5.1
  turns native-command stderr into a terminating error, so probing the Store `python3`
  stub aborted the whole suite. Now 7/7 under both hosts.
- **The E2E PowerShell harness hard-coded `pwsh`**, making it unrunnable on a stock Windows
  box. It now spawns child processes with the current host.
- **`install.sh` worked exactly once on any machine without `jq`.** The
  `.claude/settings.json` merge was jq-only, and the no-jq branch aborted as soon as the
  file existed ("jq not installed and .claude/settings.json already exists"). Stock macOS
  ships Python 3 but not jq, so every re-run of the documented, advertised-as-re-runnable
  Path A failed there. The merge now prefers Python (resolved by execution:
  `python3` → `python` → `py -3`) and falls back to jq; with neither it fails loudly and
  leaves the file byte-identical rather than partially written. Pinned by
  `unit-install-settings-merge.sh`.
- **`unit-hook-schema.py` could not see a broken renderer.** It checked that each installer
  *references* the Claude-shaped template, which stayed true while `bootstrap.ps1` never
  dot-sourced `render-events.ps1` -- so `Render-EventsTemplate` was undefined, the call
  threw, a `catch` swallowed it into a `missing-template` record, and no
  `.claude/settings.json` was written at all (5 of 34 `e2e-bootstrap.ps1` cases). The test
  now also asserts the render library is loaded in the same scope as the render call.

### Fixed (Dreaming + trial-mode install)

- **Trial-mode install leaked 4 files into git.** After `bootstrap --mode=trial`,
  `.assert-iq/agent-runs/.gitignore`, `agent-runs/index.json`,
  `business-metrics/.gitignore` and `business-metrics/baseline.json` showed up in
  `git status` even though all four WERE listed in `.git/info/exclude`. Cause: a
  `.gitignore` deeper in the tree outranks `.git/info/exclude`, so the negation
  patterns those two files used (`*` + `!index.json`, `*.json` + `!baseline.json`)
  silently RE-INCLUDED them. `git check-ignore -v` named the negation as the
  winning rule. Both files now use additive patterns only
  (`*.specialist-outputs.json`, `reports/`), which keeps the seed files trackable
  in committed mode and the generated artifacts ignored. New
  `unit-gitignore-hygiene.sh` fails on any negation in a pack-shipped
  `.gitignore`.

- **Dreaming never fired under Claude Code (any OS).** The installers copied the
  Copilot-shaped `session-events.json` verbatim into `.claude/settings.json`, but
  the two harnesses have incompatible hook schemas:
  - VS Code Copilot puts handlers directly in the event array and takes
    `osx`/`linux`/`windows` command overrides.
  - Claude Code requires a matcher-group wrapper with a nested `hooks` array, has
    no platform keys, and selects the interpreter with a `shell` field.

  Claude Code silently ignores a flat handler, so neither SessionStart (dream
  gate) nor Stop (session recorder) ever ran under Claude Code -- while the same
  file kept working under VS Code on macOS, which made it look like a platform
  problem rather than a schema problem. `.claude/settings.json` is now rendered
  from its own Claude-shaped templates
  (`claude-hooks.posix.template.json` / `claude-hooks.windows.template.json`);
  `session-events.json` is unchanged, so the working Copilot path is untouched.
  Verified end-to-end on Windows: the Stop hook bumped `sessions_since_dream`
  0 -> 1 and wrote the daily log; the SessionStart gate stayed quiet at 1 session
  and nudged at 5.

  The Windows template uses PowerShell handlers, so the bash/`python3`/`fcntl`
  path is never taken on Windows at all.

- **The command body must not re-invoke its own interpreter.** With
  `shell: "powershell"` the body is already run by PowerShell, so the original
  `powershell -NoProfile -Command "& {...}"` wrapper double-processed the quoting
  and died with a ParserError. Both Claude templates now carry native command
  bodies. Guarded by `unit-hook-schema.py`.

- **A missing interpreter silently disabled Dreaming.** `aiq_enabled()` ran a
  `python3` snippet and returned ITS exit status, so a missing or stubbed
  interpreter was indistinguishable from `dreaming.enabled: false`: the hook
  exited 0, printed `{"continue":true}` and wrote nothing. The gate is now pure
  `awk` (no interpreter at all), the remaining `python3` uses go through a
  `python3 -> python -> py -3` resolver, and a failure now leaves a breadcrumb in
  `.assert-iq/memory/logs/dreaming-errors.log` instead of failing quietly.
  `fcntl` (POSIX-only) degrades to no locking rather than crashing.

  Caught while testing: the first `awk` rewrite matched `enabled: false` at ANY
  depth inside the `dreaming:` block, and the shipped `config.yaml` has a NESTED
  `enabled: false` for the optional background dreamer -- that rule would have
  disabled Dreaming for every user. Only the first `enabled:` counts, matching
  the original python semantics. Pinned down by `unit-dreaming-gate.sh` (6 cases,
  all run with an empty interpreter PATH on purpose).

- **`e2e-dreaming.sh` embedded POSIX paths inside `python3 -c` strings.** Under
  MSYS/Git Bash, argv is translated to Windows paths but a string literal is not,
  so the harness's own state reads/writes silently no-op'd; the counter came back
  empty and cascaded into bogus "gate fired at 3 sessions" failures. Paths now go
  through argv. On Windows the suite went 3/7 -> 6/7; the remaining failure is
  `dreaming_service.py` importing POSIX-only `fcntl` (the OPTIONAL background
  dreamer, not the hook path).

- **`AIQ_CONFIG` is now overridable** (like `AIQ_MEMORY_DIR` already was) so the
  enable-gate can be tested against fixture configs rather than only the live one.

### Changed

- **Markdown / HTML documentation parity enforced.** Every user-facing doc ships
  twice (markdown + hand-authored HTML sister) and the two had drifted. New
  `unit-doc-parity.py` compares heading trees (text *and* depth) across all 7
  pairs; deliberate differences must be declared with a reason, and a declared
  exception that is no longer divergent also fails so waivers cannot rot.
  Fixed in the process:
  - `README.assert-iq.html` was missing the entire **Calibration &
    Reproducibility (v1.7.0+)** section, including "The Moat" — the pack's core
    commercial argument — and gained it plus a sidebar entry.
  - `README.assert-iq.md` was missing the **Multi-agent orchestration (v2.0)**
    section the HTML had.
  - Four Installation topics (Pinning to a tag, What bootstrap delivers, Trial vs
    Committed, Upgrading to a new release) sat at `<h4>` in HTML but `###` in
    markdown. `build-search-index.py` indexes h1–h3 only, so those sections were
    **invisible to the site search**; promoting them fixed both the divergence
    and the search gap.
  - `MCP.html` had dropped the `The 20 servers` parent section and promoted all 8
    server categories to `h2`.
  - `dreaming-readme.html` numbered its sections ("1. The two loops") while the
    markdown did not, so every title disagreed; it was also missing **Git
    visibility follows install mode**, and the markdown was missing the
    **Why Dreaming — and how it saves tokens** section (token-savings model).
  - `README.html` had drifted titles: `Tailor the pack to your codebase` while
    its own anchor still read `customize-and-wire-everything-in`.
  - Search index grew 103 → 111 entries as a direct result.

- **`jq` is no longer a dependency.** All 13 call sites moved to Python helpers in
  `.assert-iq/tests/_qi/automated/lib/aiq-test-lib.sh`. A regression guard in the
  preflight fails if `jq` is reintroduced. The suite now needs one interpreter, not two.
- **Python is resolved, not assumed.** Tests probe `python3` -> `python` -> `py -3` by
  EXECUTING each candidate. On Windows the Microsoft Store ships a `python3` stub that
  resolves on PATH but fails on invocation, and the python.org installer provides
  `python.exe` with no `python3.exe` at all — so a correctly installed machine could
  still fail every JSON assertion.
- **Specialist tool grants corrected.** `hotspot-analyzer` and `calibration-specialist`
  gained `Bash`/`runCommands`: the former derives churn from git history, the latter
  runs `.assert-iq/analysis/calibration.py`. Neither could do its job read-only.

### Fixed

- **macOS bash 3.2 compatibility regression.** The new tests used `mapfile` (bash 4.0+)
  and `local -n` (bash 4.3+), which hard-fail on the `/bin/bash` macOS still ships, and
  the preflight demanded bash >= 4. All replaced with 3.2-safe constructs; the floor is
  now documented as 3.2.
- **`Merge-MarkdownFile` was not idempotent (PowerShell only).** `Write-AtomicFile` uses
  `Set-Content`, which appends its own line terminator, so every bootstrap re-run grew
  `copilot-instructions.md` / `CLAUDE.md` / `AGENTS.md` by one CRLF (944 -> 946 -> 948
  bytes). `scripts/bootstrap.sh` writes with `printf` and was unaffected, which is why a
  macOS-only test run never surfaced it.
- **`scripts/generate-documentation-html.py` could not run on Windows.** Four bare
  `open()` calls used the locale default (cp1252) and died with
  `UnicodeDecodeError` on the first em-dash in the markdown; after that was
  fixed it crashed again printing its own ✅/→ progress glyphs, *after* having
  already written output files, leaving `docs/html/` half-regenerated. Now pins
  `encoding='utf-8'` on every open, forces UTF-8 stdout, and pins the output
  newline so regenerating on Windows does not rewrite every file as CRLF.

- **`e2e-version-consistency.sh`** no longer mistakes a `## [Unreleased]` heading for a
  release when comparing `VERSION` to the changelog.

## [2.0.2] — 2026-08-12

### Fixed
- **`/assert-iq-tailor` skill gaps.** The tailor skill predated the Oracle layer, Decision Confidence Calibration, and Business Metrics config sections (v1.6.0–v2.0), so a fresh tailoring pass would silently skip `oracle.*`, `verdicts.*`, `dreaming_provenance.*`, `regression_testing.*`, `calibration.*`, `memory_sanity.*`, `business_metrics.*`, and `governance.escalation_owner`/`compliance` — leaving real placeholders and shipped sample ROI data in place with no signal to the user. Phase 2 (Align) now asks for these judgement-call values; Phase 3 (config.yaml) now has explicit tailoring bullets for each; Phase 5 corrected "five" → "six" instruction files and added `qi-oracle.instructions.md`; Phase 6 now explicitly names the newer skill families (Oracle, Business Impact, Memory) in its gap-check loop.

## [2.0.1] — 2026-08-11

### Fixed
- **Critical Dreaming hook wiring regression.** Commit 1d16050 on 2026-08-08 broke `.vscode/settings.json` `chat.hookFilesLocations`, routing to `.claude/settings.json`. VS Code Copilot's hook loader silently failed when parsing Claude-specific `permissions` key. Dreaming logging stopped from 2026-08-08 through 2026-08-11 (4-day gap). Root cause: file format incompatibility. Solution: restored correct wiring to `./.assert-iq/dreaming/session-events.json` (clean `{hooks:{...}}` format); .claude/settings.json explicitly set to false to prevent parsing errors. Dreaming recording resumed 2026-08-11; all E2E tests pass.
- **Documentation integrity audit (v2.0 accuracy).** Comprehensive audit of README.html, README.assert-iq.html, and supporting pages revealed stale v1.7.0 references, missing v2.0 features (Multi-Agent Orchestration, Oracle Layer, Business Impact Dashboards, Decision Confidence Calibration), and incorrect skill counts (26/27/29 vs. actual 30). All skill registry tables, sidebar nav, feature cards, and version history updated to reflect v2.0.0 release. Generated new oracles-readme.html quick-start guide. Search index rebuilt: 86 → 103 entries with Oracle coverage (26 hits).

### Added
- **Memory consolidation pass** via `/dream now`. Consolidated this session's major work (v2.0 release, bug fixes, documentation overhaul) into long-term memory store (`.assert-iq/memory/`). Created 2 new topic files: `v2-0-features.md`, `dreaming-critical-bug.md`. Updated architecture.md and dreaming-and-upgrade.md with v2.0 context and Dreaming incident details. Memory index updated with 18 consolidated pointers, 28 lines (well under 200-line cap).

### Verified
- ✅ All E2E Dreaming tests pass (7/7): recorder, gate logic, time-gating, kill-switch, write-sandbox
- ✅ Hook wiring validated: session-events.json reading, .claude/settings.json parsing error prevented
- ✅ Session recording active: 3 sessions captured in 2026-08-12.md (UTC log)
- ✅ Memory protection: 4-layer safeguard confirmed (gitignore, bootstrap, upgrade, uninstall)
- ✅ No version conflicts in documentation

### Documentation
- Added memory protection guide: 4-layer safeguard, best practices for protecting custom files
- Created topics/memory-protection-guide.md with detailed protection mechanisms and scenarios

## [2.0.0] — 2026-08-11

_Backfilled. The v2.0.0 release (commit `0f02b88`) shipped without a changelog
entry, so the file jumped 1.7.0-alpha1 → 2.0.1 and the headline feature of the
major version was undocumented here._

### Added

- **Multi-Agent Orchestration.** The Claude Code lead agent
  (`.claude/agents/assert-iq.md`) became a Lead Orchestrator that delegates to
  8 isolated specialist subagents in `.claude/agents/specialists/` rather than
  analyzing directly:
  - Parallel batch (independent): `risk-scorer`, `coverage-analyst`,
    `flake-adjudicator`, `hotspot-analyzer`
  - Serial tier (depends on earlier findings): `oracle-grader`,
    `calibration-specialist`, `memory-curator`, `traceability-auditor`
  - Each specialist returns structured JSON only; the lead synthesizes a single
    narrative plus a Recommendation / Next Steps / Owners / Timeline close.
  - Audit trail written to `.assert-iq/agent-runs/`.
- **Commercial Instrumentation.** New `/measure-qi-impact` skill converts QI
  verdicts plus baseline metrics into VP-ready HTML dashboards: escape
  reduction %, triage hours reclaimed, release-cycle acceleration, and total
  economic ROI. Configured via `business_metrics` in `.assert-iq/config.yaml`,
  with pre-QI figures in `.assert-iq/business-metrics/baseline.json` and reports
  written to `.assert-iq/business-metrics/reports/` (git-ignored).

### Compatibility

- v2.0.0 is a strict superset of v1.7.0 — no breaking changes.
- **Copilot parity gap (known, unresolved at release).** The specialist tier and
  orchestration model were added to `.claude/agents/` only. `.github/agents/`
  has no `specialists/` directory, so VS Code Copilot continued to use v1.x
  single-agent skill routing. This was not recorded at the time; it is now
  asserted by `.assert-iq/tests/_qi/automated/e2e-agent-parity.sh`.

## [1.7.0-alpha1] — 2026-08-11

### Added (Phase 1: Verdict Infrastructure + Memory Versioning)

- **Decision Confidence Calibration Foundation.** Every PR risk assessment and release confidence verdict is now recorded with full layer scores, assumptions, memory version, and timestamp in `.assert-iq/verdicts/archive/YYYY/MM/verdicts-DD.jsonl`. One-line summaries appended to `.assert-iq/verdicts/VERDICTS.md` for human audit trail.

- **Verdict Schema Extension.** Signal schema (`.assert-iq/signal-schema.json`) updated with optional `verdict` object containing all calibration metadata:
  - `verdict_id` — UUID for global uniqueness
  - `verdict_band` — green/amber/red/ungraded decision
  - `verdict_score` — 0.0–1.0 numeric confidence
  - `layer_scores` — per-layer STRONG/WEAK/UNGRADED state + score
  - `layer_weights` — numeric weights per layer (sum=1.0)
  - `memory_version` — SHA256 hash of memory state at time of verdict (enables reproducibility)
  - `oracle_verdicts_considered` — IDs of oracle verdicts that fed this decision
  - `assumptions` — explicit list of assumptions baked into verdict
  - `linked_escape` — populated when escape discovered (for calibration feedback)

- **Memory Versioning & Provenance Tracking.** Before `/dream` modifies memory:
  - SHA256 snapshot of `.assert-iq/memory/` taken and stored at `.assert-iq/dreaming/.snapshots/mem-<timestamp>.tar.gz`
  - Dream cycle logged in `.assert-iq/dreaming/provenance.json` (append-only audit trail)
  - Every verdict records `memory_version_before` — enables reproducibility contract:
    1. Restore memory snapshot: `tar xzf .snapshots/mem-<version>.tar.gz -C .assert-iq`
    2. Re-run assessment: `/risk-assess-pr --pr-id=<pr> --memory-version=<version>`
    3. Expected: Identical verdict (same band, score, layer states)

- **Calibration Analysis Engine.** New library `.assert-iq/analysis/calibration.py` computes:
  - **Brier Score** (per verdict band + aggregate) — mean((predicted_confidence - actual_outcome)²)
  - **Confusion Matrix** — predicted band vs. actual outcome (escape or not); precision/recall per band
  - **Per-Layer Signal Fidelity** — of verdicts with Change=WEAK, what fraction had actual escapes? (predictiveness of each layer)
  - **Drift Detection** — Brier score across rolling 30-day windows; alerts on degradation threshold
  - **JSON Report Output** — structured calibration metrics for dashboards

- **Memory Sanity Checker.** New library `.assert-iq/analysis/memory-sanity.py` detects poisoning:
  - **Cycle Detection** — topics A→B→C→A flagged as manual editing confusion
  - **Fact Staleness** — facts >180 days without update alerted
  - **Contradiction Detection** — conflicting statements across topics (e.g., "Service X critical" vs "low priority")
  - **Granularity Issues** — copy-pasted transcripts vs. synthesized facts; suggests pruning
  - **Semantic Drift** — optional LLM-based topic drift detection (requires anthropic SDK)

- **Verdict Audit Trail.** New script `.assert-iq/analysis/audit-verdict.sh` produces reproducibility records:
  - Given `verdict_id`, outputs full audit record with layer scores, memory version, instruction file versions
  - Shows how to reproduce the decision step-by-step
  - Essential for regulatory compliance (SOX, ISO 27001, FedRAMP)

- **Regression Testing Framework.** Golden corpus infrastructure:
  - `.assert-iq/tests/_qi/regression/golden-corpus.jsonl` — user-populated template with 3+ representative PRs
  - `.assert-iq/tests/_qi/regression/evaluate-dream-regression.sh` (placeholder for Phase 2)
  - Re-evaluate corpus before each dream; block auto-fire if >5% verdict divergence

- **Unit Tests.** New test suite:
  - `.assert-iq/tests/_qi/automated/unit-verdict-schema.sh` — 5 tests for verdict schema validation ✅ 5/5 PASS
  - `.assert-iq/tests/_qi/automated/unit-calibration-basic.py` — tests for Brier score, confusion matrix, layer fidelity (Phase 2)
  - All tests in automated test framework

- **Configuration Updates.** New blocks in `.assert-iq/config.yaml`:
  - `verdicts:` — enable/disable, track_in_git (for regulated clients), retention_days
  - `dreaming_provenance:` — snapshot_retention, snapshot_path
  - `regression_testing:` — golden_corpus_path, block_dream_on_regression (fail-safe mode)
  - `calibration:` — window_days, drift_alarm_threshold, min_verdicts_for_stats
  - `memory_sanity:` — cycle_detection, staleness_threshold_days, semantic_drift_detection, max_issues

- **Governance Documentation.** New section in `.assert-iq/governance.md`:
  - **Section 4: Audit Trail & Reproducibility** — defines requirements for regulated clients (SOX, ISO 27001, FedRAMP)
  - Verdict recording immutability contract
  - Memory versioning reproducibility instructions
  - Quarterly calibration report requirement

- **Bootstrap Cleanup Enhancements.** `scripts/bootstrap.sh` updated:
  - Added `.assert-iq/verdicts`, `.assert-iq/analysis`, `.assert-iq/tests/_qi/regression` to `tree_roots` array
  - Added same paths to `empty_dirs` array for explicit removal
  - Handles both workspace and user-scope installations
  - ✅ Verified: Bootstrap syntax valid, cleanup paths correct

### Regression Testing
- ✅ Oracle layer intact (no damage to v1.6.1 features)
- ✅ Memory store intact
- ✅ All 29 skills present
- ✅ Dreaming base infrastructure unchanged
- **Result:** ZERO regressions detected

### Known Limitations (Phase 1 Alpha)
- Verdict recording logic not yet integrated into `/risk-assess-pr` or `/release-confidence` skills (Phase 2)
- Calibration reporting command `/calibration-report` not yet created (Phase 2)
- Regression testing script not yet functional (Phase 2)
- HTML sisters for updated docs not yet generated (Phase 2)
- Escape linkage in `/analyze-escaped-defect` not yet wired (Phase 2)

### Next Steps (Phase 2 Beta)
- Integrate verdict recording into risk assessment and release confidence skills
- Create `/calibration-report` skill for longitudinal accuracy analysis
- Implement functional regression test workflow
- Generate HTML documentation sisters; update search index
- Wire escape linkage and Brier score adjustment reporting

## [1.6.1] — 2026-08-11

### Fixed
- **Bootstrap uninstall cleanup.** Oracle directories (`.assert-iq/oracles/{outcomes,rubrics,schemas}/`) were not removed during uninstall due to missing entries in cleanup arrays. Added oracle directory to `tree_roots` and `empty_dirs` in `scripts/bootstrap.sh` for both workspace and user-scope installations. Verified clean removal in test workflow.

### Added
- **Oracle grading routing across 15 core skills.** Comprehensive integration of oracle layer into generation, review, healing, and routing workflows:
  - **Generation:** `/generate-automated-unit-test`, `/generate-bug-report`, `/generate-test-plan`, `/generate-automated-api-test`, `/generate-automated-ui-test`, `/generate-manual-test-case` now include post-artifact oracle grading guidance with specific rubric IDs.
  - **Review & Analysis:** `/code-review`, `/review-test-quality`, `/analyze-flaky-test`, `/analyze-escaped-defect` now surface oracle as complementary quality signal with maturity tier behavior.
  - **Healing:** `/agentic-heal` now includes post-heal oracle verification to detect quality regressions (assertion clarity, independence, determinism, focus).
  - **Routing & Gates:** `/generate-tests-from-ac`, `/risk-assess-pr`, `/new-pull-request` now surface oracle verdicts in workflow and pre-flight checks.
  - **Diagnostics:** `/debug-ui-tests` now includes oracle brittleness verification post-fix.
  - All additions reference v1.6.0+ oracle layer, include maturity tier gating (early/mid/higher), and specify rubric IDs for recommended grading runs.

### Documentation
- Oracle integration guide added across all 15 affected skills showing rubric ID, expected verdict types, and per-tier behavior.

## [1.6.0] — 2026-08-11

### Added
- **Oracle Layer — rubric-based independent quality verification.** New skills:
  - `/define-quality-rubric` — guided interview for authoring versioned quality rubrics (acceptance contracts with dimensions, levels, passing criteria)
  - `/grade-with-rubric` — independent artifact grading in isolated grader agent context (PASS/CONDITIONAL/FAIL verdicts with evidence)
- **Grader agent** (`.claude/agents/grader.md`) — isolated evaluation context with no access to generator reasoning; produces evidence-driven verdicts with per-dimension scoring
- **Oracle registry** (`.assert-iq/oracles/`) — schemas, sample rubrics (unit test, integration test, bug report, plan), verdict storage with full lineage (append-only history)
- **Oracle governance** (`.github/instructions/qi-oracle.instructions.md`) — rubric authorship rules, grading standards, maturity gating, immutability contract
- **Oracle integration** — `/check-merge` and `/release-confidence` now consume oracle verdicts in Outcome layer with maturity-tier weighting (early: 0%, mid: 20%, higher: 50%)
- **Documentation** — `ORACLE_QUICK_START.md` (5-step workflow), oracle sections in `README.md` and `README.assert-iq.md`, oracle grading examples
- **Config updates** — `.assert-iq/config.yaml` now includes `oracle:` block (grader model, defaults by artifact type, verdict_sink, maturity_gating)
- **Skill count:** 27 → 29 total (added 2 oracle skills)

### Positioning
- **Rubric authorship** (not test generation) is the defensible differentiator
- **Independent grading** — grader has zero access to how artifacts were produced
- **Immutable, versioned specs** — rubrics are treated as acceptance contracts, not templates
- **Evidence-driven verdicts** — every verdict cites specific evidence (line numbers, patterns, reasoning)

## [1.5.8] — 2026-08-11

### Fixed
- **Critical documentation integrity failures.** The landing page (README.md) claimed v1.5.7; the full documentation (README.assert-iq.md) header said v1.3.0 and footer said v1.2.0. The version history table ended at v1.2.0 (no entries for 1.3.0–1.5.7). The skill registry listed only 23 skills while prose claimed 26, and 4 critical skills were missing: `/dream` (the flagship differentiator), `/eval-optimizer`, `/assert-iq-bootstrap`, and `/assert-iq-tailor`. The inventory count vs. reality was 23 listed vs. 27 actual. Hindsight Hooks was marked as retired in the Dreaming guide but still referenced as active features in version history. **All signals now reconcile:** version history updated through v1.5.7; skill registry expanded to all 27 skills (5 new rows: Learn + 1, Cross-cutting + 1, new Setup & Meta section + 2); prose skill count corrected to 27; all version banners consistent (v1.5.7). Documentation now exhibits the trustworthiness the pack claims to provide.

## [1.5.7] — 2026-08-08

### Added
- **High-level "Why Dreaming — and how it saves tokens" section** in
  `dreaming-readme.html`. The dreaming guide previously jumped straight into
  operator mechanics (the two loops, files, config); it now opens with a
  plain-English explanation of *what* dreaming is, *why* it's in Assert.IQ, and
  *how* it saves tokens — including a worked token-economics model and a
  matching sidebar nav link. Aimed at readers who don't need what's under the
  hood.

### Fixed
- **Stale hook reference in `README.assert-iq.md`.** The layout notes still said
  `chat.hookFilesLocations` pointed at `./.assert-iq/dreaming/session-events.json`;
  since v1.5.5 it points at `.claude/settings.json` (read natively by both VS Code
  Copilot and Claude Code). Updated to match.

### Changed
- Rebuilt the docs search index (`assets/search-index.js`) to include the new
  dreaming section.

## [1.5.6] — 2026-08-08

### Fixed
- **Uninstall after an upgrade left files behind.** When `--upgrade` overwrote a
  pack-owned file that changed between versions, it created a
  `.assert-iq.pre-install` backup of the old copy. Uninstall then *restored* that
  backup (treating the pack file as if it were your pre-existing file), leaving
  the changed files plus a `.assert-iq.uninstall-saved` sidecar behind — so
  `.assert-iq/` was never fully removed. Upgrade no longer backs up pack-owned
  files (the three-way merge already preserves your edits during the upgrade
  itself), so uninstall removes them cleanly. Ported to `bootstrap.ps1`.
- **Stopped shipping a compiled `.pyc`.** The optional dreaming service's
  `__pycache__/*.pyc` build artifact was committed and installed. It's now
  git-ignored and removed, and the install copy routines skip `*.pyc` /
  `__pycache__/`.

Note: the Dreaming memory store (`.assert-iq/memory/`) is still *intentionally*
preserved on uninstall when it holds real consolidated content (your dreams); a
pristine never-dreamed seed is removed for a clean tree.

## [1.5.5] — 2026-08-07

### Fixed
- **Dreaming now records in VS Code Copilot, not just Claude Code.** The pack
  previously pointed VS Code's `chat.hookFilesLocations` at a custom
  `.assert-iq/dreaming/session-events.json` path and *disabled* the default
  `.claude/settings.json` location. Per the VS Code agent-hooks docs, VS Code
  reads `.claude/settings.json` natively (same Claude hook format), so the pack
  now wires **both** harnesses to that one file — Claude Code reads it directly;
  VS Code loads it from its default location. Its baked
  `${CLAUDE_PLUGIN_ROOT:-<workspace>}` fallback resolves the pack root under
  Copilot, which doesn't set that env var. This is why session logs never
  appeared in a Copilot-only workflow.
- **Off-by-one fallback pack root.** When `AIQ_PACK_ROOT` is unset,
  `dream-utils.{sh,ps1}` computed the pack root three levels up from the lib dir
  (landing on `.assert-iq/`) instead of four (the repo root), which would write
  to a stray `.assert-iq/.assert-iq/memory/` path. Fixed to four levels. (Masked
  in normal use because the hook always exports `AIQ_PACK_ROOT`.)
- **Fragile enabled-check (bash).** With no `dreaming:` block in `config.yaml`,
  `aiq_enabled` scanned the whole file and matched the first unrelated
  `enabled:` line. It now defaults to enabled when the block is absent, matching
  the PowerShell side.

Existing installs: VS Code settings are merged additively (your keys win), so an
upgrade won't rewrite an existing `.vscode/settings.json` — set
`"chat.hookFilesLocations": { ".claude/settings.json": true }` manually (and
reload the window).

## [1.5.4] — 2026-08-07

### Changed
- **`MEMORY.md` is now git-ignored.** The pack-as-workspace memory index is no
  longer committed, so maintainers can run `/dream` freely without their
  working memory ever shipping to installers. The memory store now ships only
  `README.md` and the empty-dir `.gitkeep`s (`topics/*.md`, `logs/`,
  `.dream/state.json`, and now `MEMORY.md` are all local-only). Both installers
  (`install.sh` / `install.ps1`) seed a clean `MEMORY.md` index when a clone
  doesn't have one, so a fresh Path-A install still gets an index; `bootstrap`
  already generated one inline.

## [1.5.3] — 2026-08-06

### Fixed
- **Malformed shebangs in the Dreaming scripts.** Every shell/python script
  under `.assert-iq/dreaming/` (and the e2e driver) shipped with an escaped
  shebang — `#\!/bin/bash` instead of `#!/bin/bash` — an artifact of how the
  files were generated. The waking loop still ran because the hook template
  invokes the scripts via `bash -c … "$S"` (bash re-execs on `ENOEXEC` and
  line 1 is a comment), but a direct `./script.sh` invocation relied on that
  fallback. Shebangs are now byte-correct so the scripts run standalone. Also
  fixed the same escape in a `[ ! -t 0 ]` stdin test and in the `<!--` HTML
  comments of `MEMORY.md` and the `/dream` skill (which previously rendered as
  visible text instead of a comment).

## [1.5.2] — 2026-08-06

### Fixed
- **Trial-mode upgrades no longer leak files into git.** On `--upgrade`,
  files the previous install hid via `.git/info/exclude` that aren't touched
  in the current run — a conflict-kept original whose only new manifest entry
  is its `.assert-iq-new` sidecar, and orphaned files from a retired feature
  (e.g. the old `hooks/` tree) — dropped out of the regenerated exclude block
  and surfaced in `git status`. The exclude writer now unions the previous
  manifest's workspace paths so everything that was hidden stays hidden.

### Changed
- **Upgrades now install newly-added surfaces.** Previously `--upgrade` only
  refreshed surfaces already present in the recorded manifest, so upgrading a
  pre-Dreaming install did not install the Dreaming machinery or seed the
  memory store. New surfaces absent from an older manifest now default to the
  scope where the pack itself lives (`.assert-iq`), so upgrading picks up
  Dreaming, the memory store, and session-event wiring.

## [1.5.1] — 2026-08-06

### Added
- **Install-time base cache for durable upgrades.** Every install now
  snapshots each pack-owned file's pristine content under `.assert-iq/.base/`
  (git-ignored, removed on uninstall). On a later `--upgrade` this cache is the
  preferred three-way merge baseline, so upgrades preserve user edits **even
  when the source repo has no matching version tag or no git history at all**
  (offline installs, release zips, shallow clones). Git-tag reconstruction is
  now the fallback, and a successful tag reconstruction re-seeds the cache so
  the next upgrade never needs the tag again. The three markdown-allowlist
  files keep their dedicated marker-block merge. Ported to both `bootstrap.sh`
  and `bootstrap.ps1`.
- Backfilled release tags `v1.2.0`, `v1.3.0`, `v1.4.0` on their release commits
  so pre-1.5 installs can reconstruct a baseline and get line-level merges on
  their first upgrade (previously these versions had no tag, forcing a
  whole-file keep/overwrite choice).
- E2E cases 38 (tagless upgrade via base cache) and 39 (cache-less older
  install falling back to tag reconstruction).

### Fixed
- The base-cache lookup could return a non-zero status when the cache was
  absent, which under `set -e` aborted the entire upgrade after the banner —
  breaking exactly the cache-less (retroactive) path. `base_lookup` now always
  returns success.

## [1.5.0] — 2026-08-06

### Added
- **`bootstrap --upgrade` engine (three-way merge).** A new upgrade path that
  refreshes an existing install in place while preserving your edits.
  Reconstructs the install-time baseline from the pack's git history
  (`git show v<installed-version>:<path>`) and runs a `git merge-file`
  three-way merge: non-overlapping pack + user edits both land automatically,
  overlapping edits fall back to a `.assert-iq-new` sidecar (your file is
  never clobbered). Mode is pinned to the recorded install (never flips
  trial↔committed), the refreshed surface set is derived from the manifest,
  and files the new pack no longer ships are surfaced as orphans (prompt-each
  interactively; report-only under `--yes`). The install manifest now records
  a per-file `sha` so unedited files can be refreshed outright. Ported to both
  `bootstrap.sh` and `bootstrap.ps1`.
- E2E coverage for the new behavior in `tests/_qi/automated/e2e-bootstrap.sh`
  (clean-slate seed / no-logs / no-conflict, uninstall-preserves-memory, and a
  full upgrade merge + conflict + orphan case).

### Changed
- **Every install/upgrade starts the Dreaming memory on a clean slate.** The
  pack no longer ships or copies its own accumulated dream data. Installers
  now *seed* a fresh memory store (empty `topics/`, `logs/`, a clean
  `MEMORY.md`, and `state.json` at `sessions_since_dream: 0`) instead of
  copying `topics/*.md`, daily `logs/`, or a populated `MEMORY.md`. On
  upgrade the memory store is never touched (it is your data).
- Uninstall now preserves a memory store that holds real consolidated
  content, but removes a pristine never-dreamed seed so the uninstall leaves
  a clean working tree.

### Fixed
- Fresh installs no longer report a bogus merge conflict on
  `.assert-iq/dreaming/session-events.json`. The rendered events file was
  being copied twice (once by the `.assert-iq` tree walk, once by the
  dreaming handler) and then re-rendered; both tree walks now exclude it.
- `.gitignore` hardened so the pack repo can never re-commit its own dream
  activity (`topics/*`, `logs/*` except `.gitkeep`, `.dream/state.json`).

## [1.4.0] — 2026-08-04

### Added
- **Dreaming — markdown memory consolidation.** A new `.assert-iq/memory/`
  store (three-tier: `MEMORY.md` index ≤200 lines, `topics/*.md`, daily
  `logs/`) that the agent consolidates via the new `/dream` skill
  (`.github/skills/dream/SKILL.md`). The four-phase pass (Orient → Gather →
  Consolidate → Prune & Index) resolves contradictions, temporalizes dates,
  prunes stale entries, and dedups — sandboxed to write only inside the
  memory store. A lightweight waking-loop recorder (`dream-record-session`)
  and a dual-gate nudge (`dream-gate`, default ≥24h AND ≥5 sessions) live
  under `.assert-iq/dreaming/scripts/`.
- **Optional background dreamer** (`.assert-iq/dreaming/service/dreaming_service.py`)
  for teams that want "dream while you sleep" via cron. Off by default and
  inert unless `anthropic` is installed and `ANTHROPIC_API_KEY` is set; the
  core `/dream` skill has no dependency on it.
- Maturity-gated dreaming (early: manual `/dream`; mid: gate nudge; higher:
  may auto-fire / optional background service), a `dreaming:` block in
  `config.yaml`, governance sandbox rules, and a startup memory-index pointer
  in `qi-foundation.instructions.md`.
- `tests/_qi/automated/e2e-dreaming.{sh,ps1}` covering the recorder, gate,
  kill-switch, and write-sandbox.

### Changed
- **Retired Hindsight Hooks entirely.** Removed the top-level `hooks/` tree,
  `hooks.template.json`, the `skill-improve-*` / `track-telemetry` scripts,
  and the per-tool-call `PostToolUse` hook — the main token/memory cost this
  release addresses. Session-event wiring now renders from
  `.assert-iq/dreaming/session-events.template.json` into the
  `.claude/settings.json` `hooks` key (`SessionStart` + `Stop` only).
- Installers (`install.sh` / `install.ps1`), bootstrap (`bootstrap.sh` /
  `bootstrap.ps1`, new `--dreaming` flag with `--hooks` alias), `.gitignore`,
  `.vscode/settings.json`, and all docs (`.md` + sister `.html` + search
  index) rebranded from Hindsight Hooks to Dreaming.

### Removed
- The retrospective self-patching feature and its runtime state
  (`dismissed-lessons.json`, `edit-frequency.json`, per-session scratch).
  Cross-session learning now lives in the versioned `.assert-iq/memory/` store.

## [1.3.0] — 2026-06-09

### Added
- `assert-iq-tailor` skill (`/assert-iq-tailor`) — a guided, evidence-driven
  customization pass that takes a freshly **placed** pack (from
  `/assert-iq-bootstrap`) and **tailors** it to the host codebase. It
  discovers the stack once (languages, test frameworks, CI system,
  tracker, VCS host, API contracts, topology, sensitive paths,
  traceability idiom), presents a Stack Profile at a human-review gate,
  then edits the configurable surfaces in dependency order — keystone
  `config.yaml` first, then `governance.md` + `maturity-profile.md`, the
  five instruction files, a config-driven (light) skills pass, and
  `mcp.json` last. Compliance regimes are **ask-only** (never inferred);
  deep skill-body rewrites are opt-in and gated to `mid`/`higher`
  maturity. Every edited file is snapshotted to
  `<file>.assert-iq.pre-tailor` so the pass is reversible and idempotent.

### Changed
- `assert-iq-bootstrap` skill now closes with a handoff to
  `/assert-iq-tailor` (placement → tailoring) and the surfaces table
  reflects the new count.
- Routing tables in both Copilot agents (`.github/agents/`) and both
  Claude subagents (`.claude/agents/`) gain the `/assert-iq-tailor` row.
- Skill count is now 26 in `.github/skills/`. Note: the published count
  had drifted (narrative docs read 24, `MANIFEST.md` read 23); both are
  reconciled to the true directory count here.
- `bootstrap.sh` / `bootstrap.ps1` now treat `*.assert-iq.pre-tailor`
  snapshots as managed tool artifacts: the glob is added to the always-on
  `.git/info/exclude` block (so tailor snapshots never leak into git), and
  `--uninstall` sweeps any leftover `*.assert-iq.pre-tailor` files under
  `.assert-iq/`, `.github/instructions/`, and `.vscode/` so a full
  uninstall leaves no tailor litter behind. The uninstall confirmation
  prompt lists this step.
- HTML doc snapshots (`README.html`, `README.assert-iq.html`) refreshed:
  skill count → 26, version → v1.3.0, and the install/customize guidance
  now leads with the one-command `/assert-iq-tailor` flow (with a fixed
  callout that was previously nested inside a table) plus a Setup section
  in the skill registry.

## [1.2.0] — 2026-06-06

### Changed
- Restructured the always-on instruction stack to remove duplication
  across `.github/copilot-instructions.md`, `CLAUDE.md`, and `AGENTS.md`.
  Core principles, Maturity awareness, Governance, and Output standards
  now live exclusively in `.github/instructions/qi-foundation.instructions.md`
  (auto-loaded by Copilot via `applyTo: "**"`; @-referenced by
  `CLAUDE.md`). The trio files were rewritten as thin tool-specific
  pointers. `AGENTS.md` was kept self-contained because Codex CLI /
  Cursor / Aider do not reliably load `.github/instructions/`.
  Per-turn savings: Copilot path ~370 tokens, Claude path ~410 tokens.
  Zero behavior change — every rule that loaded before still loads,
  just from a single home.
- Compressed the workspace-topology section in
  `qi-foundation.instructions.md` from ~480 tokens to ~80 tokens. Now a
  pointer to the new lazy-loaded reference doc (see Added). Monorepo
  users (the default) no longer carry split-repo fetch / UNGRADED prose
  on every prompt.
- Trimmed the three heaviest skill `description:` blocks: `code-review`
  (1,147 → 520 chars), `eval-optimizer` (1,023 → 584 chars),
  `generate-hotspot-map` (435 → 292 chars). Skill bodies untouched.
  Aggregate skill-routing block dropped from 5,191 → 3,982 chars
  (~300 tokens off every turn that doesn't invoke a skill).
- Updated the seven cross-repo skills (`risk-assess-pr`, `check-merge`,
  `release-confidence`, `code-review`, `check-test-coverage`,
  `generate-traceability-matrix`, `analyze-escaped-defect`) plus
  `generate-hotspot-map` to point to `.assert-iq/workspace-topology.md`
  for the full contract instead of `qi-foundation § Workspace topology`.
- README.md / README.html / MANIFEST.md updated to reference the new
  topology contract location.

### Added
- New `.assert-iq/workspace-topology.md` reference doc carrying the
  full prod / tests fetch fallback chain (MCP → local path → manual
  paste) and the UNGRADED contract (`reason: "companion_repo_unset"` /
  `"companion_repo_unreachable"` per signal-schema
  `partial_signal_mode: true`). The filename does **not** end in
  `.instructions.md`, so it is **not** auto-loaded — skills only pull
  it when `workspace.role != monorepo`.
- New 1.2.0 row in the version-history tables of `README.assert-iq.md`
  and `README.assert-iq.html` (kept in lockstep per HTML/MD parity rule).

## [1.1.11] — 2026-06-05

### Fixed
- Added missing template placeholders (`ci_provider`, `linters`, `review_source`, `test_id_format`, `regression_area_path`, `bug_reporter`, `five_whys`, `targeted_test_command`) to `.assert-iq/config.yaml` so they are immediately visible to users configuring the pack out of the box without the agent needing to infer them.

## [1.1.10] — 2026-06-04

### Fixed
- Fixed an accidental HTML structure malformation in `README.html` introduced during the previous documentation injections, which broke the rendering of both comparison tables on that page.

## [1.1.9] — 2026-06-04

### Added
- Added an explicit "Presets vs Modes" distinction block to documentation to clarify that presets control placement and modes control Git visibility.

## [1.1.8] — 2026-06-04

### Added
- Added a "Compare the Presets" table to all documentation files to explicitly disambiguate `--preset=pod`, `--preset=solo`, and `--preset=portable` regarding where instructions and skills land permanently.

## [1.1.7] — 2026-06-04

### Fixed
- Restored missing `--preset=solo|pod` clarification block in `README.md` and `README.html` that had only been present in the verbose `README.assert-iq` documentation.

## [1.1.6] — 2026-06-04

### Added
- Added missing documentation for `/generate-hotspot-map` skill in skill registries.

## [1.1.5] — 2026-06-04

### Changed
- Updated documentation HTML styling to exactly match the Assert.IQ presentation deck color scheme (dark background `#18191a` + warm orange `#e25232` + secondary teal `#1e8077`).

## [1.1.4] — 2026-06-04

### Changed
- Fixed hooks configuration and telemetry logic to correctly fall back to workspace-relative artifacts directories (`.github/skills` and `.claude/skills`) rather than exclusively tracking user-global `~/.agents/skills`.


## [1.1.3] — 2026-06-04

### Fixed
- Fixed CSS grid overflow issue causing `Path A / Path B` comparison cards to slightly overflow offscreen.


## [1.1.2] — 2026-06-04

### Changed
- Pointed GitHub Pages landing redirect to `README.html` instead of `README.assert-iq.html`.


## [1.1.1] — 2026-06-04

Patch release. Hides Hindsight Hooks runtime artifacts from git so
workspaces that install the pack don't see hook state files appear as
untracked changes.

### Fixed

- `hooks/state/.dedup-<hash>` markers (atomic locks created by
  `si_dedup_or_exit` to suppress double-fires) and `hooks/state/.last-janitor`
  no longer surface in `git status` after install. Per-directory
  `.gitignore` files now ship inside `hooks/state/`, `hooks/logs/`, and
  `hooks/sessions/` at the pack source. `copy_tree()` in
  `scripts/bootstrap.{sh,ps1}` already copies dotfiles, so the ignore
  rules propagate verbatim into every workspace install — no mutation of
  the workspace `.gitignore` required (consistent with the design rule
  that bootstrap never touches the user's `.gitignore`).
- Untracked the previously-committed runtime seeds
  `hooks/logs/skill-improve.log` and `hooks/state/.last-janitor`. The
  structural seeds `hooks/state/dismissed-lessons.json` and
  `hooks/state/edit-frequency.json` remain tracked.

### Verified

- `tests/_qi/automated/e2e-hooks.sh`: 15/15 PASS.
- `tests/_qi/automated/e2e-bootstrap.sh`: 23/23 PASS.

## [1.1.0] — 2026-06-04

Hindsight Hooks become scope-aware and double-fire-safe. Power users can
now install hooks once at the user level (`~/.agents/hooks/`) and have
them fire across every VS Code workspace; the existing per-workspace
install path is unchanged and remains the default.

### Added

- **`--hooks=user` / `-Hooks user` install mode** in
  `scripts/bootstrap.{sh,ps1}`. Copies hook scripts, lib, config, state,
  and logs to `$HOME/.agents/hooks/`, creates `sessions/`, renders
  `hooks.json` so the wrapper resolves `__PACK_ROOT__` to the user-global
  pack root, and prints the VS Code USER `settings.json` block needed to
  register the hook file across all workspaces. Manifest entries scoped
  `user`, with full uninstall support via `--uninstall --user`.
- **`si_dedup_or_exit` / `Invoke-SiDedupOrExit`** helpers in the shared
  hook lib. Suppress double-fires of the same `(session_id, event)`
  pair within `SKILL_IMPROVE_DEDUP_WINDOW_SECONDS` (default 5; set to 0
  to disable). Atomic claim via `set -o noclobber` (bash) /
  `FileMode.CreateNew` (PowerShell). Wired into SessionStart and Stop
  only — PostToolUse legitimately fires once per tool call.
- **Hooks E2E suite** (`tests/_qi/automated/e2e-hooks.sh`) — 15 cases
  covering workspace + user install layouts, SessionStart routing,
  PostToolUse telemetry + detect, Stop log entry,
  `config.enabled=false` no-op, `SKILL_IMPROVE_DISABLED=1` no-op,
  double-fire dedup, dedup-window-disabled override, per-event dedup
  independence, marker creation under `state/`, workspace/user install
  isolation, and user uninstall. Workspace and `$HOME` are
  mktemp-isolated.

### Changed

- Hook scripts resolve `SKILL_IMPROVE_ROOT` from the environment (set by
  the `hooks.json` wrapper based on install scope) instead of hardcoding
  `$HOME/.agents/hooks`. Default falls back to `$HOME/.agents/hooks` for
  back-compat with existing installs.
- `hooks/hooks.template.json` wrappers now `export SKILL_IMPROVE_ROOT`
  before invoking the script so workspace installs route to
  `<workspace>/hooks/` and user installs route to `~/.agents/hooks/`
  deterministically.
- Five hardcoded `~/.agents/hooks/config/skill-improve.config.json`
  lookups (in `skill-improve-session-start.sh`,
  `skill-improve-session-end.sh`, `lib/correction-signatures.sh`)
  replaced with env-var fallbacks.
- Janitor sweep now prunes stale `.dedup-*` markers older than 1 hour
  in addition to its existing session and log retention passes.
- `VERSION` bumped to `1.1.0`.

### Verified

- `tests/_qi/automated/e2e-hooks.sh`: 15/15 PASS on macOS bash.
- `tests/_qi/automated/e2e-bootstrap.sh`: 23/23 PASS (no regressions).

## [1.0.0] — 2026-06-04

First stable release. The pack is now considered API-stable: bootstrap CLI
flags, manifest schema, skill names, and workspace surface layout will not
change in incompatible ways without a major-version bump.

### Added

- **E2E regression suite** (`tests/_qi/automated/e2e-bootstrap.sh`) — 23 cases
  covering pod / solo / portable presets, committed / trial / ask modes,
  skills-scope workspace / user / both, idempotent reinstall, conflict +
  backup + restore round-trip, dry-run, and invalid-arg rejection. Workspace
  and `$HOME` are mktemp-isolated so the suite is safe to run on a developer
  machine.
- `assert-iq-bootstrap` skill — `/assert-iq-bootstrap` slash command for
  installing the pack into an arbitrary repository.
- `generate-hotspot-map` skill — churn × complexity × defect-density audit
  that produces a Hotspot Risk Index registry for test prioritization.
- HTML snapshots of the README family (`README.html`, `README.assert-iq.html`,
  `claude-readme.html`, `vscode-readme.html`, `hooks-readme.html`, `MCP.html`)
  for environments that don't render Markdown natively.
- Solo-preset callout and "HTML files are rendered snapshots" note in
  `README.assert-iq.md`.

### Changed

- **Bootstrap (bash + PowerShell, parity-preserving):**
  - JSON merge no-op short-circuit consolidated into a single helper
    (`write_or_skip_if_unchanged` / `Write-OrSkipIfUnchanged`); previously
    duplicated at four call sites.
  - Manifest action vocabulary centralized; `manifest_add` /
    `Add-ManifestEntry` reject unknown actions at call time instead of
    silently writing typos that downstream predicates would never match.
  - Uninstall gains a manifest-derived ancestor-dir sweep as a safety net
    so future surface additions don't have to update the hardcoded prune
    lists. PowerShell version sorts deepest-first by path-segment depth
    (not string length) for correctness on uneven path widths.
- `mk_pack_copy()` in the e2e driver now wraps the tar pipe in a
  `set -o pipefail` subshell so silent tar failures surface immediately.
- `VERSION` bumped to `1.0.0`.

### Verified

- 23/23 PASS on macOS bash. PowerShell e2e on Windows is the deferred
  follow-up.

## [0.9.0] — 2026-06-03

### Added

- `VERSION` file as the sole source of truth for the pack version
  (replaces `.claude-plugin/*.json`).
- Two install paths:
  - **Path A (pack-as-workspace):** `install.sh` / `install.ps1` at pack root.
  - **Path B (codebase bootstrap):** `scripts/bootstrap.sh` / `.ps1` invoked
    via `/assert-iq-bootstrap`.
- Both paths support `--uninstall` (`-Uninstall`) with `--yes` / `--user` /
  `--dry-run`. Bootstrap snapshots pre-existing user files to
  `<file>.assert-iq.pre-install` for byte-for-byte restore on uninstall.
- Four new workspace surfaces: `.github/skills/`, `.github/agents/`,
  `.claude/agents/`, and `.claude/skills` (symlink, copy fallback on Windows
  without Developer Mode) — twelve total workspace-loaded surfaces.
- Shared `hooks/scripts/lib/render-hooks.{sh,ps1}` library for
  `hooks.json` rendering.
- Workspace topology + Five Whys discipline.

### Changed

- Skill count 23 → 24 (adds `assert-iq-bootstrap`).
- `--yes` / `-Yes` accepted as no-op on installers for parity with bootstrap.

### Verified

- Full uninstall round-trip on bash + pwsh (Path A and Path B): 0 leftover
  files, 0 exclude residue.

## [0.8.0] and earlier

See git history (`git log v0.8.0`). Releases prior to 1.0.0 are pre-stable.

[2.1.3]: https://github.com/fromjariuswithsparq/assert-iq-agent-pack/compare/v2.1.2...v2.1.3
[2.1.2]: https://github.com/fromjariuswithsparq/assert-iq-agent-pack/compare/v2.1.1...v2.1.2
[2.1.1]: https://github.com/fromjariuswithsparq/assert-iq-agent-pack/compare/v2.1.0...v2.1.1
[2.1.0]: https://github.com/fromjariuswithsparq/assert-iq-agent-pack/compare/v2.0.2...v2.1.0
[1.1.1]: https://github.com/fromjariuswithsparq/assert-iq-agent-pack/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/fromjariuswithsparq/assert-iq-agent-pack/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/fromjariuswithsparq/assert-iq-agent-pack/compare/v0.9.0...v1.0.0
[0.9.0]: https://github.com/fromjariuswithsparq/assert-iq-agent-pack/compare/v0.8.0...v0.9.0