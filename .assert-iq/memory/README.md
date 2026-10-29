# `.assert-iq/memory/` — Dreaming memory store

Long-term, human-inspectable agent memory for this workspace. Maintained by
the `/dream` consolidation pass (see `.assert-iq/dreaming/`).

## Layout

| Path | Tier | Written by | Loaded at startup | Dreamed? |
|------|------|-----------|-------------------|----------|
| `.github/instructions/*` | Rules | Human | Always (Copilot/Claude) | Never — immutable |
| `MEMORY.md` | Long-term index | Agent + `/dream` | Index only (≤200 lines) | Yes |
| `topics/*.md` | Long-term detail | Agent + `/dream` | On demand | Yes |
| `logs/YYYY/MM/*.md` | Short-term stream | Waking recorder | No | Yes (raw input) |
| `.dream/state.json` | Dream state | Recorder + `/dream` | No | No |

### What git sees

| Path | In git | Why |
|------|--------|-----|
| `MEMORY.md`, `topics/*.md` | Yes, in a committed install | The *results* of dreaming. Synthesized team knowledge, worth reviewing and worth `git revert`. |
| `logs/`, `.dream/` | **Never, in any mode** | The *inputs*. One daily note per session is your own chat activity, and `.dream/state.json` is a per-machine counter. A teammate pulling either gets noise and merge conflicts. Enforced by `.gitignore` in this directory plus `.git/info/exclude`, in committed installs and after `--graduate` alike. |

## Conventions

- **Absolute dates only.** Never "yesterday" / "last week".
- **One fact per bullet.** Note provenance where it matters
  (`decided 2026-03-15`, `observed across 3 sessions`).
- **Facts, decisions, preferences** — not transcript excerpts.
- `MEMORY.md` is an **index**, not a dump. One-line pointers to topic files;
  the 200-line cap bounds startup context cost.

## Safety

- The `/dream` pass may write **only** inside `.assert-iq/memory/`.
- Instruction/rule files are immutable — dreaming never edits them.
- **Git visibility follows your install mode — except for the runtime.**
  Committed installs track `MEMORY.md` and `topics/` (every dream cycle is a
  reviewable diff, and `git revert` is your undo). Trial installs keep the
  whole store local-only via `.git/info/exclude`; `bootstrap.sh --graduate`
  exposes the dreamed results later. `logs/` and `.dream/` are local-only in
  **every** mode and `--graduate` does not expose them — see *What git sees*
  above.
