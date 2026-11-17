# Shared helpers for the Assert.IQ Dreaming waking loop (PowerShell side).
# Dot-sourced by dream-record-session.ps1 and dream-gate.ps1; not run directly.

if (-not $env:AIQ_PACK_ROOT) {
    # .../.assert-iq/dreaming/scripts/lib -> repo root is four levels up.
    $env:AIQ_PACK_ROOT = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
}
$script:AiqPackRoot   = $env:AIQ_PACK_ROOT
$script:AiqMemoryDir  = if ($env:AIQ_MEMORY_DIR) { $env:AIQ_MEMORY_DIR } else { Join-Path $script:AiqPackRoot '.assert-iq\memory' }
$script:AiqDreamState = Join-Path $script:AiqMemoryDir '.dream\state.json'
$script:AiqConfig     = Join-Path $script:AiqPackRoot '.assert-iq\config.yaml'

New-Item -ItemType Directory -Force -Path (Join-Path $script:AiqMemoryDir '.dream') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $script:AiqMemoryDir 'logs') | Out-Null

# --- hook output protocol --------------------------------------------------
# Claude Code consumes hook stdout as JSON: {"continue":true} to proceed, plus
# an optional "systemMessage" it surfaces to the user. VS Code Copilot's
# session-events consumer accepts the same shape.
#
# Kiro does NOT. Its bundled hook contract is:
#   exit 0  -- success; stdout FORWARDED for SessionStart/UserPromptSubmit/PreToolUse
#   exit 2  -- block the action; stderr forwarded
#   other   -- silent failure, no block
# ...and the only JSON it parses is a PreToolUse permissionDecision (plus a
# Stop-hook {"decision":"block"}). So on Kiro the Claude-shaped envelope is not
# understood as a protocol -- it is forwarded VERBATIM, and the user sees
# `{"continue":true}` pasted into their chat at the start of every session.
#
# AIQ_HOOK_OUTPUT selects the protocol:
#   unset | "claude"  -> JSON envelope (default; Claude Code + Copilot)
#   "plain"           -> the nudge text alone, and NOTHING when there is no
#                        nudge, so a quiet session start stays quiet.
# The default is deliberately the old behaviour: adding a third harness must
# not change what the first two receive.
# Keep in step with aiq_emit_* in dream-utils.sh.
function Aiq-HookOutputMode {
    if ($env:AIQ_HOOK_OUTPUT) { return $env:AIQ_HOOK_OUTPUT } else { return 'claude' }
}

function Aiq-EmitContinue {
    if ((Aiq-HookOutputMode) -eq 'plain') { return }
    '{"continue":true}'
}

# Emit a user-visible nudge in whichever protocol this harness speaks.
function Aiq-EmitNudge {
    param([string]$Message)
    if (-not $Message) { return }
    if ((Aiq-HookOutputMode) -eq 'plain') { $Message; return }
    @{ continue = $true; systemMessage = $Message } | ConvertTo-Json -Compress
}

function Aiq-Enabled {
    if ($env:AIQ_DREAMING_DISABLED -eq '1') { return $false }
    try {
        $txt = Get-Content -LiteralPath $script:AiqConfig -Raw -ErrorAction Stop
        if ($txt -match '(?ms)^dreaming:\s*$(.*?)(^\S|\Z)') {
            $block = $Matches[1]
            if ($block -match '(?m)^\s+enabled:\s*(true|false)') { return ($Matches[1] -ne 'false') }
        }
    } catch { }
    return $true
}

function Aiq-GateMinHours {
    if ($env:AIQ_DREAM_MIN_HOURS) { return [int]$env:AIQ_DREAM_MIN_HOURS }
    try {
        $m = Select-String -LiteralPath $script:AiqConfig -Pattern 'min_hours_between_dreams:\s*(\d+)' | Select-Object -First 1
        if ($m) { return [int]$m.Matches[0].Groups[1].Value }
    } catch { }
    return 24
}
function Aiq-GateMinSessions {
    if ($env:AIQ_DREAM_MIN_SESSIONS) { return [int]$env:AIQ_DREAM_MIN_SESSIONS }
    try {
        $m = Select-String -LiteralPath $script:AiqConfig -Pattern 'min_sessions_between_dreams:\s*(\d+)' | Select-Object -First 1
        if ($m) { return [int]$m.Matches[0].Groups[1].Value }
    } catch { }
    return 5
}

# Run a scriptblock while holding the cross-process dreaming state mutex.
function Aiq-WithStateLock {
    param([scriptblock]$Body)
    $mutex = New-Object System.Threading.Mutex($false, 'Global\AssertIQDreamingState')
    [void]$mutex.WaitOne()
    try { & $Body } finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
}

function Aiq-ReadStdin { [Console]::In.ReadToEnd() }

function Aiq-JsonField {
    param([string]$Raw, [string[]]$Names)
    try {
        $o = $Raw | ConvertFrom-Json -ErrorAction Stop
        foreach ($n in $Names) { if ($o.$n) { return [string]$o.$n } }
    } catch { }
    return ''
}
