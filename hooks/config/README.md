# Hindsight Hooks — Guide

> **Hindsight Hooks** — hooks that fire at turn-end and look back at the just-completed turn for signs the agent corrected itself, then offer to update the SKILL.md / instructions.md file that *should have* prevented the mistake.
>
> Formal technique name: **Retrospective Skill Refinement**.

This hook watches your Copilot chat sessions for signs that the agent **corrected itself** — and at the end of the session, it offers to update the SKILL.md / instructions.md file that *should have* prevented the mistake.

If you just want it to work, do nothing. The defaults are sensible. Read this when you want to tune behavior or troubleshoot.

---

## 1. The big picture (read this first)

```
┌────────────────┐   ┌──────────────┐   ┌──────────────┐   ┌─────────────┐
│ SessionStart   │ → │ PostToolUse  │ → │     Stop     │ → │   You       │
│ (once)         │   │ (every tool) │   │ (session end)│   │ (yes / no)  │
└────────────────┘   └──────────────┘   └──────────────┘   └─────────────┘
       │                    │                  │                  │
       ▼                    ▼                  ▼                  ▼
 snapshots which       logs every          scans transcript +   if you say yes,
 skill files exist     tool the agent      tool log for signs   the apply script
 in your configured    used into           the agent had to     edits the SKILL.md
 roots                 tool-log.jsonl      correct itself       in your working tree
```

If the agent never corrected itself, **nothing happens** — you won't even notice the hook ran.

If it did, you'll get a numbered list before the session closes:

```
I detected 2 corrections this session. Proposed updates:
  [1] ~/MDA/.github/instructions/services.instructions.md — Add note about disposing X
  [2] ~/.agents/skills/debug-ui-tests/SKILL.md — Fix outdated AutomationId tip
Apply which? [all / 1,2 / none / diff N]
```

You decide. No git commits. No PRs. Just direct edits with a provenance comment so you can find them later.

---

## 2. The files in this folder

| File | What it does |
|---|---|
| `skill-improve.config.json` | The only thing you'll edit. See section 3. |

State and session data live in sibling folders, **not here**:

| Folder | Contents |
|---|---|
| `../state/dismissed-lessons.json` | Fingerprints of lessons you rejected (so they don't ask again) |
| `../state/edit-frequency.json` | How often each customization has been edited (for "hot skill" quarantine) |
| `../state/correction-recurrence.json` | Per-fingerprint count of applied patches — drives the recurrence quarantine when the same correction recurs after two applied patches in 30 days |
| `../state/needs-rewrite.json` | Targets that have been auto-patched twice and **still** misfired the same signal — quarantined from any further automated patches until a human rewrites them |
| `../state/.state.lock` | Lock file used by the bash side (`fcntl.flock`) to serialize state writes. PowerShell uses a named system mutex `Global\HindsightHooksState` for the same purpose |
| `../sessions/<session-id>/` | Per-session scratch: loaded customizations, tool log, **invoked-customizations.json** (the subset actually read this session, prioritized during attribution), candidate edits, decisions |
| `../logs/skill-improve.log` | Diagnostic log. First place to look when something feels off. |

---

## 3. Editing `skill-improve.config.json`

The config has **five** top-level sections. Walking through each:

### 3.1 `enabled`

```json
"enabled": true
```

Master switch. Set to `false` to turn the whole feature off without removing the hook.

You can also disable it **just for one terminal session** without editing this file:

```bash
export SKILL_IMPROVE_DISABLED=1      # macOS / Linux
$env:SKILL_IMPROVE_DISABLED = '1'    # Windows PowerShell
```

### 3.2 `customization_roots`

```json
"customization_roots": [
  "~/.agents/skills",
  "~/MDA/.github/skills",
  "~/MDA/.github/instructions",
  "~/MDAMockService/.github",
  "~/Library/Application Support/Code/User/prompts"
]
```

Folders the hook scans at session start to find candidate customization files (skills, instructions, prompts, agents).

**Add a folder** if you start using another repo with its own `.github/skills/` or `.github/instructions/`:

```json
"customization_roots": [
  "~/.agents/skills",
  "~/MDA/.github/skills",
  "~/MDA/.github/instructions",
  "~/MDAMockService/.github",
  "~/MyNewProject/.github/instructions",     // ← add a line like this
  "~/Library/Application Support/Code/User/prompts"
]
```

`~` is your home directory. Use forward slashes even on Windows — the scripts handle conversion.

> Legacy key `skill_roots` is still accepted for backward compatibility but `customization_roots` takes precedence.

### 3.3 `customization_file_patterns`

```json
"customization_file_patterns": [
  "SKILL.md",
  "*.instructions.md",
  "*.prompt.md",
  "copilot-instructions.md",
  "AGENTS.md"
]
```

Filename patterns the hook treats as customization artifacts (skills, instructions, prompts, agents). You almost never need to change this.

> Legacy key `skill_file_patterns` is still accepted for backward compatibility.

### 3.4 `correction_signatures`

This is the brain — how the hook decides the agent corrected itself.

**Text signals** (`assistant_text_regex`) — case-insensitive regexes applied to assistant messages in the transcript. As of the weighted-trigger upgrade, each entry is a `{pattern, weight}` object where `weight` is `"strong"` (clear self-correction phrases like *"I was wrong"*, *"my mistake"*) or `"weak"` (softer hedges like *"actually"*, *"turns out"*).

To add a new phrase, append an object. Regex syntax — remember to **double-escape backslashes** in JSON:

```json
{ "pattern": "\\bnever mind\\b",     "weight": "strong" }
{ "pattern": "\\bsecond thought\\b", "weight": "weak"   }
```

A correction is only acted on when the **sum of hit weights** across the transcript and tool log meets `trigger.min_score`. This filters out lone soft hedges and avoids firing on phrases that just happen to look like corrections.

**Trigger** (`trigger`):

```json
"trigger": {
  "min_score": 2,
  "weights": { "strong": 2, "weak": 1, "behavioral": 2 }
}
```

| Key | Default | Meaning |
|---|---|---|
| `min_score` | `2` | A session must accumulate at least this much weighted hit-score before the agent is asked to draft candidate edits. With the defaults, that means *one strong text hit*, *two weak hits*, or *one behavioral hit* (edit→re-read / self-rewrite). |
| `weights.strong` | `2` | Score added per strong text hit. |
| `weights.weak` | `1` | Score added per weak text hit. |
| `weights.behavioral` | `2` | Score added per behavioral hit. Behavioral hits are downgraded to `weak` automatically if there are `>=2` intervening tool calls on different files between the edit and the re-read (the agent was clearly doing other work, not self-correcting). |

**Behavioral signals** (`tool_patterns`):

| Key | Default | Meaning |
|---|---|---|
| `reread_window_turns` | `3` | If the agent re-reads the same file within 3 tool calls after editing it, that's a sign of "I had to verify after writing." |
| `self_edit_window_turns` | `2` | If the agent edits its own freshly written output within 2 calls, that's a "rewrite of my mistake" signal. |

Raise these numbers to catch more signals (more noise). Lower them to catch only obvious cases.

### 3.5 `thresholds`

```json
"thresholds": {
  "diff_max_lines":          10,
  "min_confidence":     "medium",
  "hot_skill_window_days":    7,
  "hot_skill_edit_limit":     3
}
```

| Key | Default | What it means |
|---|---|---|
| `diff_max_lines` | `10` | Any proposed edit larger than this is **rejected**. Big changes need a human to author, not the agent. |
| `min_confidence` | `"medium"` | Skip proposals tagged `low`. Set to `"low"` to see everything, `"high"` to see only slam-dunks. |
| `hot_skill_window_days` | `7` | How far back to look for the hot-skill check. |
| `hot_skill_edit_limit` | `3` | If a skill has been edited this many times in the window, **quarantine** it — the hook stops proposing more edits and warns you that the skill probably needs a rewrite, not patches. |

**Rule of thumb:** if you find the hook is too chatty, raise `min_confidence` to `"high"` first. If it's too quiet, lower it to `"low"`.

### 3.6 `behavior`

```json
"behavior": {
  "edit_scope": "direct",
  "silent_on_zero_corrections": true,
  "provenance_comment_format": "<!-- self-improve: session {session_id}, {date} -->"
}
```

| Key | Default | What it means |
|---|---|---|
| `edit_scope` | `"direct"` | Edit files in your working tree, no git ops. (`stage` and `branch-commit` are reserved but **not yet implemented** — leave it on `direct` for now.) |
| `silent_on_zero_corrections` | `true` | When the agent had a clean session, say nothing. Set to `false` if you want a confirmation like *"no corrections detected this session"* every time the hook runs. |
| `provenance_comment_format` | (see config) | The comment appended to every edited file. `{session_id}` and `{date}` get substituted. Useful for `grep -r "self-improve"` to find every edit the hook has ever made. |

### 3.7 `retention` (housekeeping)

```json
"retention": {
  "keep_silent_sessions":          false,
  "keep_correction_sessions_days":    30,
  "edit_frequency_keep_days":         14,
  "log_max_lines":                  5000,
  "janitor_min_interval_hours":       24
}
```

The janitor runs at the end of every session to keep things from ballooning over time.

| Key | Default | What it means |
|---|---|---|
| `keep_silent_sessions` | `false` | If the agent had a clean session (no corrections), delete its session folder immediately. Receipts for clean sessions are noise — keeping them off saves the vast majority of disk usage. Set to `true` if you want every session preserved. |
| `keep_correction_sessions_days` | `30` | How long to keep session folders that **did** produce corrections (audit trail). Older ones are deleted on the next janitor sweep. |
| `edit_frequency_keep_days` | `14` | Drop entries from `edit-frequency.json` older than this. Hot-skill check only looks back `hot_skill_window_days` (default 7), so two weeks of buffer is plenty. |
| `log_max_lines` | `5000` | Cap on `logs/skill-improve.log`. Older lines are dropped on rotation. |
| `janitor_min_interval_hours` | `24` | The cheap part of the janitor (deleting *this* session's silent folder) runs every session. The expensive sweeps (log rotation, edit-frequency trim, old session-dir cleanup) run **at most once per this many hours** — gated by a marker file at `../state/.last-janitor`. Lower it to sweep more aggressively, raise it to sweep less. |

**Rule of thumb:** the defaults keep total disk usage flat in steady state — somewhere under ~5 MB long-term. If you want to keep more audit trail, raise `keep_correction_sessions_days`. If you want to keep nothing, set both `keep_silent_sessions: false` and `keep_correction_sessions_days: 0`.

To force a full janitor sweep right now, delete the marker:

```bash
rm ~/.agents/hooks/state/.last-janitor
```

The next session will trigger a full sweep instead of waiting for the interval.

### 3.8 Environment-variable overrides

A few knobs are exposed via env vars for quick one-off tuning without editing the config:

| Variable | Effect |
|---|---|
| `SKILL_IMPROVE_DISABLED=1` | Disable the whole feature for the current shell. |
| `SKILL_IMPROVE_TRIGGER_ANY=1` | Restore the legacy "fire on any single hit" behavior; bypasses `trigger.min_score` entirely. Useful when debugging signal detection. |
| `SKILL_IMPROVE_MIN_SCORE=<int>` | Override `correction_signatures.trigger.min_score` for the current shell. Lower it to surface more hits during tuning, raise it to suppress noisy sessions without editing the config. Ignored when `SKILL_IMPROVE_TRIGGER_ANY=1` is set. |
| `SKILL_IMPROVE_INSIGHTS_DISABLED=1` | Suppress the proactive-insight pipeline (see §3.9) for the current shell. Corrections still fire normally. Useful when you want the legacy correction-only behavior. |

---

### 3.9 `proactive_insights`

The correction pipeline (§3.4) catches signals from the model's **own error trail** — "scratch that", "actually", retry-after-error, etc. It misses a different class: when the model **proactively flags a latent flaw in the user's workflow or code** without ever making (or correcting) a mistake. Phrases like *"consider --logger trx because tail -120 discards stack traces"* or *"this would be safer with a try/finally"*. There is no self-error to anchor on — just an outward-facing observation.

Phase 6 adds a parallel detector and its own weighted gate. Insights run independently of corrections: a session can fire on insights only, corrections only, or both.

```json
"proactive_insights": {
  "enabled": true,
  "require_file_reference": true,
  "max_per_session": 3,
  "proactive_insight_regex": [
    { "pattern": "\\bconsider\\b",                                "weight": "strong" },
    { "pattern": "\\bwould be (safer|better|cleaner|wiser)\\b",   "weight": "strong" },
    { "pattern": "\\bsuggest(ed|ion)?\\b",                        "weight": "strong" },
    { "pattern": "\\bsilently (discard|swallow|drop|ignore)\\b",  "weight": "strong" },
    { "pattern": "\\b(might|may) want to\\b",                     "weight": "weak"   }
  ],
  "trigger": { "min_score": 3, "weights": { "strong": 2, "weak": 1 } }
}
```

| Key | Default | What it means |
|---|---|---|
| `enabled` | `true` | Master switch for the insight pipeline. Disabling here keeps corrections running normally. |
| `require_file_reference` | `true` | Only count a hit when the same assistant turn also mentions a path-like token (e.g. `run-tests.sh`, `~/.agents/skills/foo`). Strongly reduces false positives on conversational asides like *"might want to revisit this later"*. The detected token is attached to each hit as `file_ref` so the agent can use it to pick a target. |
| `max_per_session` | `3` | Hard cap on insight drafts per session. Insights can be high-volume in long sessions — this prevents the user-facing task block from becoming a wall of suggestions. |
| `proactive_insight_regex` | (see config) | Same weighted-regex shape as `correction_signatures.assistant_text_regex`. Tune carefully — false positives here are **more annoying than missed ones** since each surfaces as a proposed edit. |
| `trigger.min_score` | `3` | Default is one step higher than the correction gate so insights need stronger evidence to fire. Lower to `2` if you want more drafts. |
| `trigger.weights` | `{strong:2, weak:1}` | Per-weight contribution. Same semantics as the correction gate. |

#### How insight drafts differ from corrections

Insight drafts have a `kind` field that determines the routing:

- **`kind: "extend"`** — the observation maps cleanly onto an existing customization file (a skill, instruction, prompt, or agent already loaded this session). These flow through the **same** reflect gates as corrections (diff cap, hot-skill quarantine, dismissed-lessons, recurrence) and **can be auto-applied** after user confirmation. They are surfaced in the user-facing list with `I` prefix ids (`[I1]`, `[I2]`) and written with a distinguished provenance comment: `<!-- self-improve (insight): session ..., DATE -->`.
- **`kind: "create"`** — the observation describes a recurring concern that does **not** fit any existing customization. The agent proposes a brand-new file under `~/.agents/skills/<slug>/SKILL.md` or a new `.instructions.md`. These are **always** routed to `needs_human` regardless of the rest of the gates — creating a new top-level skill is a human-authoring decision, not a one-line patch.

The fingerprint includes `kind`, so an insight `extend` patch and a correction patch targeting the same file and the same QI layer remain in **separate dismissed-lessons namespaces**.

#### Apply selection syntax

When the user is presented with the task block they can mix correction and insight ids:

```text
Apply which? all
Apply which? 1,2,I1
Apply which? I1
Apply which? diff I2     # dry-run print of insight #2 without applying
```

`all` accepts every validated `extend` insight as well as every validated correction. `none` rejects them all (and their fingerprints get added to `dismissed-lessons.json` so the same suggestion won't re-surface).

---

## 4. The flow, step by step

When something does fire, here's exactly what happens:

1. **Session starts.** `skill-improve-session-start.sh` scans your `customization_roots` and writes a snapshot to `sessions/<id>/loaded-customizations.json`. ~Instant.
2. **You chat.** Every tool call the agent makes (read_file, edit, etc.) gets appended to `sessions/<id>/tool-log.jsonl` by `skill-improve-detect.sh`. ~1 ms each.
3. **Session ends.** `skill-improve-session-end.sh` scans the transcript + tool log. If it finds no signals → silent exit. If it finds signals → it writes `sessions/<id>/signals.json` and tells the agent: *"Draft minimal candidate edits, then ask the user."*
4. **Agent drafts proposals** into `sessions/<id>/candidate-edits.json` and runs `skill-improve-reflect.sh`, which applies the policy gates (`diff_max_lines`, `min_confidence`, `hot_skill_*`, dismissed-lessons) and writes `candidate-edits.validated.json`.
5. **Agent asks you** with the numbered list. You reply `all`, `1,3`, `none`, or `diff 2` to inspect.
6. **Agent runs `skill-improve-apply.sh`** with your selection. The script:
   - Writes accepted edits directly to the target file, appending the provenance comment.
   - Records rejected edits' fingerprints in `dismissed-lessons.json` so they never get re-proposed.
   - Bumps `edit-frequency.json` for accepted edits.
   - Saves a full audit trail to `sessions/<id>/decisions.json`.
7. **Janitor runs** at the very end (on both silent and correction paths). See section 3.7 — it prunes silent-session folders immediately and, at most once per day, rotates the log, trims `edit-frequency.json`, and deletes old correction-session folders.

---

## 5. Troubleshooting

| Symptom | Where to look |
|---|---|
| Hook seems to do nothing | `../logs/skill-improve.log` — check for recent `SessionStart`, `Stop` entries |
| Proposal you expected didn't show up | `sessions/<id>/candidate-edits.validated.json` — look at the `skipped` array for the reason (likely `confidence_below_medium`, `diff_exceeds_cap`, `previously_dismissed`, or `hot_skill_quarantine`) |
| Same lesson keeps being proposed | Check `../state/dismissed-lessons.json` — the fingerprint should appear there after you reject it |
| Want to "un-dismiss" a lesson | Remove its fingerprint from `../state/dismissed-lessons.json` |
| Skill is in quarantine ("hot") | Either wait for the rolling window to clear, or trim old entries out of `../state/edit-frequency.json` |
| Need to see every edit the hook has ever made | `grep -rn "self-improve: session" ~/MDA ~/.agents/skills ~/Library/Application\ Support/Code/User/prompts` |
| Disk usage growing | Confirm `retention.keep_silent_sessions` is `false`. Force a sweep with `rm ~/.agents/hooks/state/.last-janitor` then start any chat — the next Stop hook will run the full janitor. |
| Want to keep a specific session forever | Move it out of `../sessions/` (e.g., to `../sessions-archive/`). The janitor only sweeps direct children of `sessions/`. |

---

## 6. Undoing an edit

Every edit leaves a provenance comment like:

```html
<!-- self-improve: session apply-1778984054, 2026-05-16 -->
```

To find and revert:

```bash
grep -rn "self-improve: session apply-1778984054" ~/MDA ~/.agents/skills
# then manually remove the added lines + comment, or
cat ~/.agents/hooks/sessions/apply-1778984054/decisions.json
# decisions.json contains the exact before/after for every applied edit
```

---

## 7. Sanity-check: is everything wired correctly?

From `~/.agents/hooks/`:

```bash
# Validates JSON files parse cleanly.
python3 -c "import json; \
  [json.load(open(f)) for f in [ \
    'hooks.json', \
    'config/skill-improve.config.json', \
    'state/dismissed-lessons.json', \
    'state/edit-frequency.json' \
  ]]; print('OK')"

# Confirms the three hook events are wired.
python3 -c "import json; print(list(json.load(open('hooks.json'))['hooks'].keys()))"
# Expected: ['SessionStart', 'PostToolUse', 'Stop']
```

If both print cleanly, you're good. Start a chat — the hook will take care of itself.
