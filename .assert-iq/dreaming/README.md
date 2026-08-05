# Dreaming — memory consolidation for Assert.IQ

> **Dreaming** replaces the retired Hindsight Hooks feature. Instead of
> patching skills in place on every self-correction, Assert.IQ now keeps a
> curated, versioned **markdown memory store** and consolidates it on a
> schedule — a second-derivative process where *memory improves memory*.

If you just want it to work, do nothing. A lightweight recorder runs at
session end; when enough has accumulated you'll be nudged to run `/dream`.

## The two loops

```
WAKING LOOP (per session, online)
  session ends → dream-record-session appends a dated note to
                 .assert-iq/memory/logs/ and bumps the session counter

DREAMING LOOP (on demand via /dream, or optional cron)
  Phase 1 Orient → Phase 2 Gather → Phase 3 Consolidate → Phase 4 Prune & Index
  → rewritten .assert-iq/memory/ (reviewable git diff) + a dream report
```

## What's in this folder

| Path | What it does |
|------|--------------|
| `scripts/dream-record-session.{sh,ps1}` | Waking loop. Increments the session counter, appends one dated log line. |
| `scripts/dream-gate.{sh,ps1}` | Session-start dual-gate check. Nudges `/dream` when both gates are met. |
| `scripts/lib/dream-utils.{sh,ps1}` | Shared helpers (state path, lock, config gate values). |
| `scripts/lib/render-events.{sh,ps1}` | Renders `session-events.template.json` at install time. |
| `session-events.template.json` | Committed source-of-truth for session-event wiring. Rendered by the installer into `.claude/settings.json`. |
| `service/dreaming_service.py` | **Optional** background dreamer (cron / post-session). Off by default; requires the `anthropic` SDK + `ANTHROPIC_API_KEY`. |

The memory store itself lives at `.assert-iq/memory/` (see its README).

## Configuration

All knobs live under `dreaming:` in `.assert-iq/config.yaml`:

- `enabled` — master switch (env kill-switch: `AIQ_DREAMING_DISABLED=1`).
- `index_max_lines` — `MEMORY.md` cap (default 200).
- `gate.min_hours_between_dreams` / `gate.min_sessions_between_dreams` —
  the dual gate (default 24h AND 5 sessions). Env overrides:
  `AIQ_DREAM_MIN_HOURS`, `AIQ_DREAM_MIN_SESSIONS`.
- `background_service` — opt-in cron dreamer (see below).

## Maturity gating

Mirrors Agentic Healing:

- **early** — manual `/dream` only; review every diff.
- **mid** — the gate nudge surfaces at session start; still user-run.
- **higher** — may auto-fire on the next session start when the gate is met,
  and may enable the optional background service.

## Safety (non-negotiable)

1. **Write sandbox** — the dream pass may write ONLY inside
   `.assert-iq/memory/`. Source, config, and instruction files are read-only.
2. **Rules are immutable** — `.github/instructions/*` are never modified by
   dreaming.
3. **Lock** — one dream at a time per project (`.dream/state.lock`).
4. **Human review** — every dream is a git-diffable change; skim the diff and
   hand-edit freely.

## Git visibility follows install mode

- **Committed install** — the memory store is tracked in git; every dream
  cycle is a reviewable diff (the audit interface).
- **Trial install** — the whole `.assert-iq/memory/` store is kept local-only
  via `.git/info/exclude`; git never sees it, and dreams update it
  autonomously. Run `scripts/bootstrap.sh --graduate` to expose it to git
  later. (Pack-as-workspace installs via `install.sh` track it, like committed.)

## Optional background dreamer

`service/dreaming_service.py` is the turnkey "dream while you sleep" path. It
is **never** required — the `/dream` skill is the default engine and has no
dependency on it. To enable:

1. Set `dreaming.background_service.enabled: true` in `config.yaml`
   (only honored at `higher` tier).
2. `pip install anthropic` and export `ANTHROPIC_API_KEY`.
3. Wire a trigger:

   ```bash
   # Nightly at 02:00
   0 2 * * * /usr/bin/python3 \
     /path/to/repo/.assert-iq/dreaming/service/dreaming_service.py /path/to/repo

   # Manual, after a big refactor
   python3 .assert-iq/dreaming/service/dreaming_service.py . --force
   ```

Without the env key the service exits without doing anything, so the pack
stays dependency-free by default.

## Sanity check

```bash
python3 -c "import json; print(list(json.load(open('.claude/settings.json'))['hooks'].keys()))"
# Expected: ['SessionStart', 'Stop']   (no PostToolUse)
```
