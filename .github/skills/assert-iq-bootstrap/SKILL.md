# /assert-iq-bootstrap

Bootstrap an Assert.IQ plugin install into a workspace. Walks the user
through choosing — per workspace-loaded surface — whether each goes to
the workspace, the user-global slot (where supported), or is skipped.
Then invokes the appropriate script with explicit flags. Cross-platform
(bash on macOS/Linux, PowerShell on Windows).

## When to use

- User just installed the Assert.IQ pack as a plugin and the agent
  found `.assert-iq/maturity-profile.md` is missing from both the
  workspace and `~/.assert-iq/`.
- User explicitly typed `/assert-iq-bootstrap`.
- User opened the pack in a new repo and asked anything that requires
  maturity-tier or governance context.

## What it copies

Five workspace-loaded surfaces that the plugin install delivers to disk
but does **not** wire into the tool automatically:

| Surface | What it is |
|---|---|
| `.assert-iq/` | Per-client config: `config.yaml`, `governance.md`, `maturity-profile.md`, `signal-schema.json` |
| `.github/instructions/*.instructions.md` | Five QI rule sheets that load via `applyTo` globs |
| `CLAUDE.md` | Always-on QI guidance for Claude Code |
| `.github/copilot-instructions.md` | Always-on QI guidance for Copilot |
| `AGENTS.md` | Generic agent-spec pointer (Codex, Cursor, Aider) |

## How to run it (the chat flow)

1. **Greet and explain**. "I'll set up the Assert.IQ pack in this
   workspace. Five things to place — I'll ask where each should go.
   Want a quick preset, or per-surface control?"

2. **Offer presets first** (option A):
   - **`pod`** (default): everything in the workspace. Best when the
     pack is being tailored per-client and the repo is the source of
     truth.
   - **`solo`**: `.assert-iq/` in the workspace (per-client governance),
     everything else user-global. Best for a contractor rotating across
     many client repos who wants the same QI brain everywhere.

3. **If preset is chosen**, confirm and skip to step 6. Otherwise, walk
   through each surface and ask `workspace` / `user-global` / `skip`.
   For `--copilot=user` or `--agents=user`, explain there's no native
   user-global slot and treat as `skip` (the agent automatically
   degrades).

4. **Detect OS** via the environment:
   - In VS Code / chat terminal: prefer `$IsWindows` (PowerShell) or
     `uname` (bash).
   - Pick the script: `scripts/bootstrap.ps1` on Windows,
     `scripts/bootstrap.sh` elsewhere.

5. **Resolve the source dir**. Prefer `$CLAUDE_PLUGIN_ROOT` if set
   (plugin install). Fall back to the pack root if running from a
   drop-in checkout. The script handles this automatically when
   `--source` is omitted.

6. **Invoke the script** with explicit flags (do NOT rely on
   interactive prompts in the script — flags are the contract):

   ```bash
   # macOS / Linux
   bash "${CLAUDE_PLUGIN_ROOT:-.}/scripts/bootstrap.sh" \
     --preset=solo \
     --workspace="$PWD"
   ```

   ```powershell
   # Windows
   pwsh -NoProfile -File "$env:CLAUDE_PLUGIN_ROOT\scripts\bootstrap.ps1" `
     -Preset solo `
     -Workspace (Get-Location).Path
   ```

   Or with per-surface flags overriding the preset:

   ```bash
   bash scripts/bootstrap.sh \
     --preset=pod \
     --instructions=user \
     --claude=skip
   ```

7. **Show the summary table the script prints** verbatim. It tells the
   user what was copied, what was skipped (already present), what was
   skipped by user choice, and what was skipped because no user-global
   slot exists.

8. **Tell the user to reload the editor window** (VS Code: `⇧⌘P` →
   "Reload Window"; Claude Code: restart the session). Instruction
   files only get picked up after a reload.

## Flags reference

| Flag | Values | Default |
|---|---|---|
| `--preset` / `-Preset` | `solo`, `pod` | (none — falls back to `pod` if no per-surface flags given) |
| `--assert-iq` / `-AssertIq` | `workspace`, `user`, `skip` | preset default |
| `--instructions` / `-Instructions` | `workspace`, `user`, `skip` | preset default |
| `--claude` / `-Claude` | `workspace`, `user`, `skip` | preset default |
| `--copilot` / `-Copilot` | `workspace`, `user` (→skip+warn), `skip` | preset default |
| `--agents` / `-Agents` | `workspace`, `user` (→skip+warn), `skip` | preset default |
| `--workspace` / `-Workspace` | path | `$PWD` |
| `--source` / `-Source` | path | `$CLAUDE_PLUGIN_ROOT` if set, else script's parent dir |

## Behavior contract

- **Always skip-if-exists.** v1 does not overwrite. If a file already
  lives at the destination, the script reports `skipped (already
  present)` and leaves it alone.
- **Atomic per surface.** A failure on one surface does not abort the
  others.
- **Idempotent.** Re-running with the same flags is safe; the second
  run will report all surfaces as already-present.
- **No prompts inside the script.** All decisions come from flags. The
  chat is the prompt surface.

## Things you do NOT do

- Do not invoke this skill silently. Always explain to the user what's
  about to happen and confirm preset or per-surface choices first.
- Do not pass `--force` (it doesn't exist in v1 by design).
- Do not edit the copied files after the script runs. The user
  customizes them to their client/codebase.
- Do not run this against a workspace that already has `.assert-iq/`
  fully populated unless the user explicitly asked for a re-bootstrap
  (in which case the skip-if-exists behavior will be reported, and
  they'll need to delete the conflicting files manually).
