<#
.SYNOPSIS
sync-agents.ps1 -- render Copilot specialist agents from the Claude sources.

.DESCRIPTION
Windows-native twin of scripts/sync-agents.sh. The pack ships .sh/.ps1 pairs
because macOS boxes may lack PowerShell and Windows boxes may lack bash; both
implementations MUST produce byte-identical output (LF line endings), which is
asserted by check P6 in
.assert-iq/tests/_qi/automated/e2e-agent-parity.sh.

See the header of scripts/sync-agents.sh for the full rationale and for why the
lead/planner agents are deliberately NOT generated.

.PARAMETER PrintMap
Emit the tool map, one Claude=Copilot pair per line, sorted. Consumed by check
P6 so the bash and PowerShell tables cannot silently drift apart.

.PARAMETER Check
Verify the generated files are current instead of writing them. Exits 1 if any
generated file is missing, stale, or orphaned.
#>
param([switch]$Check, [switch]$PrintMap)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root      = (Resolve-Path (Join-Path $ScriptDir '..')).Path
$SrcDir    = Join-Path $Root '.claude\agents\specialists'
$DstDir    = Join-Path $Root '.github\agents\specialists'

if (-not (Test-Path -LiteralPath $SrcDir)) { throw "sync-agents: missing source dir: $SrcDir" }
New-Item -ItemType Directory -Force -Path $DstDir | Out-Null

# Claude Code tool -> VS Code Copilot tool. Keep in lockstep with the map_tool()
# table in sync-agents.sh; P6 fails if the two implementations diverge.
$ToolMap = [ordered]@{
    'Read'      = 'codebase'
    'Grep'      = 'search'
    'Glob'      = 'search'
    'Bash'      = 'runCommands'
    'Edit'      = 'editFiles'
    'Write'     = 'editFiles'
    'WebFetch'  = 'fetch'
    'WebSearch' = 'fetch'
    'Agent'     = 'agent/runSubagent'
}

if ($PrintMap) {
    $ToolMap.Keys | ForEach-Object { "$_=" + $ToolMap[$_] } | Sort-Object
    exit 0
}

function Get-Frontmatter {
    param([string[]]$Lines)
    if ($Lines.Count -eq 0 -or $Lines[0].Trim() -ne '---') { return @() }
    $out = @()
    for ($i = 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -eq '---') { break }
        $out += $Lines[$i]
    }
    return $out
}

function Get-Body {
    param([string[]]$Lines)
    $seen = 0
    $out = @()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -eq '---' -and $seen -lt 2) { $seen++; continue }
        if ($seen -eq 2) { $out += $Lines[$i] }
    }
    return $out
}

function Get-Field {
    param([string[]]$Fm, [string]$Key)
    foreach ($l in $Fm) {
        if ($l.StartsWith("${Key}:")) { return $l.Substring($Key.Length + 1).TrimStart() }
    }
    return ''
}

function Render-One {
    param([string]$SrcPath)
    # Read with LF normalization so CRLF sources cannot leak \r into output.
    $raw   = [System.IO.File]::ReadAllText($SrcPath) -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = $raw -split "`n"
    $fm    = Get-Frontmatter -Lines $lines
    $name  = Get-Field -Fm $fm -Key 'name'
    $desc  = Get-Field -Fm $fm -Key 'description'
    $tools = Get-Field -Fm $fm -Key 'tools'

    if (-not $name) { throw "sync-agents: $SrcPath : no name: field" }
    if (-not $desc) { throw "sync-agents: $SrcPath : no description: field" }

    foreach ($ch in @('[', ']', "'", '"', ',')) { $tools = $tools.Replace($ch, ' ') }

    $mappedList = New-Object System.Collections.Generic.List[string]
    foreach ($t in ($tools -split '\s+')) {
        if (-not $t) { continue }
        if (-not $ToolMap.Contains($t)) {
            Write-Warning "sync-agents: $name : no Copilot equivalent for tool '$t' (dropped)"
            continue
        }
        $m = $ToolMap[$t]
        if (-not $mappedList.Contains($m)) { $mappedList.Add($m) }
    }
    if ($mappedList.Count -eq 0) { throw "sync-agents: $name : mapped to an empty tool list" }
    $toolsOut = ($mappedList | ForEach-Object { "'$_'" }) -join ', '

    $srcName = Split-Path -Leaf $SrcPath
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("---`n")
    [void]$sb.Append("name: $name`n")
    [void]$sb.Append("description: $desc`n")
    [void]$sb.Append("tools: [$toolsOut]`n")
    [void]$sb.Append("---`n")
    [void]$sb.Append("`n")
    [void]$sb.Append("<!-- ------------------------------------------------------------------`n")
    [void]$sb.Append("     GENERATED FILE - DO NOT EDIT.`n")
    [void]$sb.Append("     Rendered from .claude/agents/specialists/$srcName`n")
    [void]$sb.Append("     by scripts/sync-agents.sh (tool names mapped Claude -> Copilot).`n")
    [void]$sb.Append("     To change this agent, edit the Claude source and re-run:`n")
    [void]$sb.Append("       bash scripts/sync-agents.sh`n")
    [void]$sb.Append("     Staleness is enforced by check P5 in`n")
    [void]$sb.Append("     .assert-iq/tests/_qi/automated/e2e-agent-parity.sh`n")
    [void]$sb.Append("     ------------------------------------------------------------------ -->`n")
    [void]$sb.Append((Get-Body -Lines $lines) -join "`n")
    # Match the shell version, which compares with $(cat) semantics: exactly one
    # trailing newline.
    return ($sb.ToString().TrimEnd("`n") + "`n")
}

$stale = @()
$count = 0

foreach ($src in (Get-ChildItem -LiteralPath $SrcDir -Filter '*.md' -File | Sort-Object Name)) {
    $count++
    $dst = Join-Path $DstDir ($src.BaseName + '.agent.md')
    $rendered = Render-One -SrcPath $src.FullName
    $rel = $dst.Substring($Root.Length + 1).Replace('\', '/')

    if ($Check) {
        if (-not (Test-Path -LiteralPath $dst)) {
            $stale += "  MISSING  $rel"
        } else {
            $existing = ([System.IO.File]::ReadAllText($dst) -replace "`r`n", "`n")
            if ($existing.TrimEnd("`n") -ne $rendered.TrimEnd("`n")) { $stale += "  STALE    $rel" }
        }
    } else {
        [System.IO.File]::WriteAllText($dst, $rendered, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "  rendered $rel"
    }
}

foreach ($dst in (Get-ChildItem -LiteralPath $DstDir -Filter '*.agent.md' -File -ErrorAction SilentlyContinue)) {
    $base = $dst.BaseName -replace '\.agent$', ''
    if (-not (Test-Path -LiteralPath (Join-Path $SrcDir "$base.md"))) {
        $rel = $dst.FullName.Substring($Root.Length + 1).Replace('\', '/')
        if ($Check) { $stale += "  ORPHAN   $rel (no .claude source)" }
        else { Remove-Item -LiteralPath $dst.FullName -Force; Write-Host "  removed  $rel (source deleted)" }
    }
}

if ($Check) {
    if ($stale.Count -eq 0) {
        Write-Host "sync-agents: $count generated Copilot specialist(s) are current"
        exit 0
    }
    Write-Host "sync-agents: generated Copilot agents are OUT OF DATE:"
    $stale | ForEach-Object { Write-Host $_ }
    Write-Host ""
    Write-Host "Fix with:  pwsh -File scripts/sync-agents.ps1"
    exit 1
}

Write-Host "sync-agents: $count specialist(s) synced -> .github/agents/specialists"
exit 0
