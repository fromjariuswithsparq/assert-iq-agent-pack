<#
.SYNOPSIS
sync-kiro.ps1 -- render the Kiro harness surfaces from their existing sources.

.DESCRIPTION
Windows-native twin of scripts/sync-kiro.sh. The pack ships .sh/.ps1 pairs
because macOS boxes may lack PowerShell and Windows boxes may lack bash; both
implementations MUST produce byte-identical output (LF line endings), which is
asserted by checks P7 and P8 in
.assert-iq/tests/_qi/automated/e2e-agent-parity.sh.

Generates:
  .github/instructions/*.instructions.md  ->  .kiro/steering/<base>.md
  .claude/agents/specialists/*.md         ->  .kiro/agents/<base>.md

See the header of scripts/sync-kiro.sh for the full rationale: why steering is
generated rather than pointed at with Kiro's "#[[file:...]]" reference, and why
the lead/planner agents are deliberately NOT generated.

Schema contract: .assert-iq/kiro-harness.md. Every schema fact was verified
against a real Kiro 1.0.337 install, not against kiro.dev docs -- which are
wrong about the agent file format (they say JSON; the binary requires .md with
YAML frontmatter).

.PARAMETER PrintMap
Emit the tool map, one Claude=Kiro pair per line, sorted. Consumed by check P8
so the bash and PowerShell tables cannot silently drift apart.

.PARAMETER Check
Verify the generated files are current instead of writing them. Exits 1 if any
generated file is missing, stale, or orphaned.
#>
param([switch]$Check, [switch]$PrintMap)

$ErrorActionPreference = 'Stop'

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root        = (Resolve-Path (Join-Path $ScriptDir '..')).Path
$InstrDir    = Join-Path $Root '.github\instructions'
$SpecSrcDir  = Join-Path $Root '.claude\agents\specialists'
$SteeringDir = Join-Path $Root '.kiro\steering'
$AgentsDir   = Join-Path $Root '.kiro\agents'

# Hand-authored files in the generated directories. Never written, never
# treated as orphans. Keep in step with $HAND_AUTHORED_* in sync-kiro.sh.
$HandAuthoredSteering = @('00-assert-iq.md')
$HandAuthoredAgents   = @('assert-iq.md', 'assert-iq-plan.md')

# Claude Code tool -> Kiro tool TAG. Keep in lockstep with the TOOL_MAP table
# in sync-kiro.sh; P8 fails if the two implementations diverge.
#
# Tags, not tool names: Kiro's own agent-authoring guidance says to use tags
# exclusively because they survive tool renames. Read/Grep/Glob all collapse to
# 'read' (Kiro's read tag covers file_search and grep_search), which is why the
# renderer dedupes while preserving order.
$ToolMap = [ordered]@{
    'Read'      = 'read'
    'Grep'      = 'read'
    'Glob'      = 'read'
    'Bash'      = 'shell'
    'Edit'      = 'write'
    'Write'     = 'write'
    'WebFetch'  = 'web'
    'WebSearch' = 'web'
    'Agent'     = 'subagent'
}

if ($PrintMap) {
    $ToolMap.Keys | ForEach-Object { "$_=" + $ToolMap[$_] } | Sort-Object
    exit 0
}

# Resources every generated Kiro agent must declare.
#
# THIS IS NOT OPTIONAL. Kiro custom agents do NOT inherit steering or skills
# the way the default agent does -- they load only what `resources` names. A
# specialist without these two globs runs with no QI rulebook at all, and
# because Kiro DROPS INVALID RESOURCE ENTRIES SILENTLY, a typo here is
# invisible at runtime. unit-kiro-schema.py fails the build if either glob is
# missing from a generated agent.
$AgentResources = @(
    '  - "file://.kiro/steering/**/*.md"'
    '  - "skill://.kiro/skills/**/SKILL.md"'
)

if (-not (Test-Path -LiteralPath $InstrDir))   { throw "sync-kiro: missing source dir: $InstrDir" }
if (-not (Test-Path -LiteralPath $SpecSrcDir)) { throw "sync-kiro: missing source dir: $SpecSrcDir" }

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

function Remove-Quotes {
    param([string]$S)
    if ($S.Length -ge 2) {
        if (($S[0] -eq '"' -and $S[-1] -eq '"') -or ($S[0] -eq "'" -and $S[-1] -eq "'")) {
            return $S.Substring(1, $S.Length - 2)
        }
    }
    return $S
}

function Expand-ApplyTo {
    <#
      Turn a Copilot `applyTo` value into an ordered list of Kiro
      fileMatchPattern entries.

      Split on TOP-LEVEL commas only: a comma inside {...} belongs to a brace
      group, not to the applyTo list. Splitting naively shreds
      qi-traceability's single 22-extension group into `**/*.{cs`, `xaml`, ...

      Brace expansion happens here because Kiro's own brace support in
      fileMatchPattern is UNVERIFIED (kiro-harness.md section 8). If Kiro does
      not expand braces, the traceability instruction would match nothing and
      traceability enforcement would be silently dead on every Kiro workspace.
      Expanding costs nothing and removes the bet.
    #>
    param([string]$Apply, [string]$Src)

    $segs = New-Object System.Collections.Generic.List[string]
    $depth = 0
    $seg = ''
    foreach ($c in $Apply.ToCharArray()) {
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') { $depth-- }
        if ($c -eq ',' -and $depth -eq 0) { $segs.Add($seg); $seg = '' }
        else { $seg += $c }
    }
    $segs.Add($seg)

    $out = New-Object System.Collections.Generic.List[string]
    foreach ($raw in $segs) {
        $pat = $raw.Trim()
        if (-not $pat) { continue }
        $ob = $pat.IndexOf('{')
        $cb = $pat.IndexOf('}')
        if ($ob -lt 0 -or $cb -lt 0) { $out.Add($pat); continue }
        $pre   = $pat.Substring(0, $ob)
        $inner = $pat.Substring($ob + 1, $cb - $ob - 1)
        $post  = $pat.Substring($cb + 1)
        if ($post.Contains('{')) {
            throw "sync-kiro: ${Src}: more than one brace group in `"$pat`" (unsupported)"
        }
        foreach ($alt in ($inner -split ',')) {
            $a = $alt.Trim()
            if ($a) { $out.Add("$pre$a$post") }
        }
    }
    return $out
}

function Render-Steering {
    param([string]$SrcPath)
    # Read with LF normalization so CRLF sources cannot leak \r into output.
    $raw   = [System.IO.File]::ReadAllText($SrcPath) -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = $raw -split "`n"
    $fm    = Get-Frontmatter -Lines $lines
    $apply = Remove-Quotes (Get-Field -Fm $fm -Key 'applyTo')
    $desc  = Remove-Quotes (Get-Field -Fm $fm -Key 'description')

    if (-not $apply) { throw "sync-kiro: $SrcPath : no applyTo: field" }

    $srcName = Split-Path -Leaf $SrcPath
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("---`n")
    if ($apply -eq '**') {
        # applyTo "**" is Copilot's always-on. Kiro's equivalent is inclusion:
        # always -- which is ALSO the default when inclusion is absent, but
        # state it explicitly so the intent survives a reader who does not
        # know that.
        [void]$sb.Append("inclusion: always`n")
    } else {
        $patterns = Expand-ApplyTo -Apply $apply -Src $srcName
        if ($patterns.Count -eq 0) { throw "sync-kiro: ${srcName}: applyTo '$apply' expanded to nothing" }
        [void]$sb.Append("inclusion: fileMatch`n")
        # Always emit an ARRAY even for a single pattern, so the shape never
        # varies across the six generated files.
        [void]$sb.Append("fileMatchPattern:`n")
        foreach ($p in $patterns) { [void]$sb.Append("  - `"$p`"`n") }
    }
    if ($desc) { [void]$sb.Append("description: `"$desc`"`n") }
    [void]$sb.Append("---`n")
    [void]$sb.Append("`n")
    [void]$sb.Append("<!-- ------------------------------------------------------------------`n")
    [void]$sb.Append("     GENERATED FILE - DO NOT EDIT.`n")
    [void]$sb.Append("     Rendered from .github/instructions/$srcName`n")
    [void]$sb.Append("     by scripts/sync-kiro.sh (applyTo -> inclusion/fileMatchPattern).`n")
    [void]$sb.Append("     To change this steering file, edit the instruction source and`n")
    [void]$sb.Append("     re-run:`n")
    [void]$sb.Append("       bash scripts/sync-kiro.sh`n")
    [void]$sb.Append("     Staleness is enforced by check P7 in`n")
    [void]$sb.Append("     .assert-iq/tests/_qi/automated/e2e-agent-parity.sh`n")
    [void]$sb.Append("     Contract: .assert-iq/kiro-harness.md`n")
    [void]$sb.Append("     ------------------------------------------------------------------ -->`n")
    [void]$sb.Append((Get-Body -Lines $lines) -join "`n")
    return ($sb.ToString().TrimEnd("`n") + "`n")
}

function Render-Agent {
    param([string]$SrcPath)
    $raw   = [System.IO.File]::ReadAllText($SrcPath) -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = $raw -split "`n"
    $fm    = Get-Frontmatter -Lines $lines
    $name  = Get-Field -Fm $fm -Key 'name'
    $desc  = Get-Field -Fm $fm -Key 'description'
    $tools = Get-Field -Fm $fm -Key 'tools'

    if (-not $name) { throw "sync-kiro: $SrcPath : no name: field" }
    if (-not $desc) { throw "sync-kiro: $SrcPath : no description: field" }

    foreach ($ch in @('[', ']', "'", '"', ',')) { $tools = $tools.Replace($ch, ' ') }

    $mappedList = New-Object System.Collections.Generic.List[string]
    foreach ($t in ($tools -split '\s+')) {
        if (-not $t) { continue }
        if (-not $ToolMap.Contains($t)) {
            Write-Warning "sync-kiro: $name : no Kiro tag for tool '$t' (dropped)"
            continue
        }
        $m = $ToolMap[$t]
        if (-not $mappedList.Contains($m)) { $mappedList.Add($m) }
    }
    if ($mappedList.Count -eq 0) { throw "sync-kiro: $name : mapped to an empty tool list" }
    $toolsOut = ($mappedList | ForEach-Object { "`"$_`"" }) -join ', '

    $srcName = Split-Path -Leaf $SrcPath
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("---`n")
    [void]$sb.Append("name: $name`n")
    [void]$sb.Append("description: $desc`n")
    [void]$sb.Append("tools: [$toolsOut]`n")
    # "sub-agent" is what makes this delegable from the lead. Without it the
    # file is a standalone custom agent the orchestrator cannot spawn.
    [void]$sb.Append("dispatchKind: sub-agent`n")
    [void]$sb.Append("resources:`n")
    foreach ($r in $AgentResources) { [void]$sb.Append("$r`n") }
    [void]$sb.Append("---`n")
    [void]$sb.Append("`n")
    [void]$sb.Append("<!-- ------------------------------------------------------------------`n")
    [void]$sb.Append("     GENERATED FILE - DO NOT EDIT.`n")
    [void]$sb.Append("     Rendered from .claude/agents/specialists/$srcName`n")
    [void]$sb.Append("     by scripts/sync-kiro.sh (tool names mapped Claude -> Kiro tags).`n")
    [void]$sb.Append("     To change this agent, edit the Claude source and re-run:`n")
    [void]$sb.Append("       bash scripts/sync-kiro.sh`n")
    [void]$sb.Append("     Staleness is enforced by check P7 in`n")
    [void]$sb.Append("     .assert-iq/tests/_qi/automated/e2e-agent-parity.sh`n")
    [void]$sb.Append("     Contract: .assert-iq/kiro-harness.md`n")
    [void]$sb.Append("     ------------------------------------------------------------------ -->`n")
    [void]$sb.Append((Get-Body -Lines $lines) -join "`n")
    return ($sb.ToString().TrimEnd("`n") + "`n")
}

if (-not $Check) {
    New-Item -ItemType Directory -Force -Path $SteeringDir | Out-Null
    New-Item -ItemType Directory -Force -Path $AgentsDir   | Out-Null
}

$stale = @()
$count = 0

function Publish-Rendered {
    param([string]$Rendered, [string]$Dst)
    $script:count++
    $rel = $Dst.Substring($Root.Length + 1).Replace('\', '/')
    if ($Check) {
        if (-not (Test-Path -LiteralPath $Dst)) {
            $script:stale += "  MISSING  $rel"
        } else {
            $existing = ([System.IO.File]::ReadAllText($Dst) -replace "`r`n", "`n")
            if ($existing.TrimEnd("`n") -ne $Rendered.TrimEnd("`n")) { $script:stale += "  STALE    $rel" }
        }
    } else {
        [System.IO.File]::WriteAllText($Dst, $Rendered, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "  rendered $rel"
    }
}

foreach ($src in (Get-ChildItem -LiteralPath $InstrDir -Filter '*.instructions.md' -File | Sort-Object Name)) {
    $base = $src.Name -replace '\.instructions\.md$', ''
    Publish-Rendered -Rendered (Render-Steering -SrcPath $src.FullName) -Dst (Join-Path $SteeringDir "$base.md")
}

foreach ($src in (Get-ChildItem -LiteralPath $SpecSrcDir -Filter '*.md' -File | Sort-Object Name)) {
    Publish-Rendered -Rendered (Render-Agent -SrcPath $src.FullName) -Dst (Join-Path $AgentsDir $src.Name)
}

# Generated outputs with no corresponding source must not linger. Hand-authored
# files in the same directories are skipped -- they have no source by design.
foreach ($dst in (Get-ChildItem -LiteralPath $SteeringDir -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
    if ($HandAuthoredSteering -contains $dst.Name) { continue }
    if (-not (Test-Path -LiteralPath (Join-Path $InstrDir ($dst.BaseName + '.instructions.md')))) {
        $rel = $dst.FullName.Substring($Root.Length + 1).Replace('\', '/')
        if ($Check) { $stale += "  ORPHAN   $rel (no instruction source)" }
        else { Remove-Item -LiteralPath $dst.FullName -Force; Write-Host "  removed  $rel (source deleted)" }
    }
}

foreach ($dst in (Get-ChildItem -LiteralPath $AgentsDir -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
    if ($HandAuthoredAgents -contains $dst.Name) { continue }
    if (-not (Test-Path -LiteralPath (Join-Path $SpecSrcDir $dst.Name))) {
        $rel = $dst.FullName.Substring($Root.Length + 1).Replace('\', '/')
        if ($Check) { $stale += "  ORPHAN   $rel (no .claude specialist source)" }
        else { Remove-Item -LiteralPath $dst.FullName -Force; Write-Host "  removed  $rel (source deleted)" }
    }
}

if ($Check) {
    if ($stale.Count -eq 0) {
        Write-Host "sync-kiro: $count generated Kiro file(s) are current"
        exit 0
    }
    Write-Host "sync-kiro: generated Kiro files are OUT OF DATE:"
    $stale | ForEach-Object { Write-Host $_ }
    Write-Host ""
    Write-Host "Fix with:  pwsh -File scripts/sync-kiro.ps1"
    exit 1
}

Write-Host "sync-kiro: $count file(s) synced -> .kiro/steering/, .kiro/agents/"
exit 0
