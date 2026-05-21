# install.ps1 — wire the Assert.IQ agent pack into a repo for dual-target use.
# Idempotent: safe to re-run.
#
# What it does:
#   1. Syncs hooks\hooks.json -> .claude\settings.json (hooks key),
#      preserving any other keys you already have in .claude\settings.json.
#   2. Creates .claude\skills as a symlink to ..\.github\skills so Claude
#      Code discovers the same skills Copilot does. Falls back to copy when
#      symlink creation requires Developer Mode and that mode is off.
#
# Copilot needs no extra wiring — it reads .github\* natively.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root         = Split-Path -Parent $PSCommandPath
$hooksTpl     = Join-Path $root 'hooks\hooks.template.json'
$hooksSrc     = Join-Path $root 'hooks\hooks.json'
$settingsDst  = Join-Path $root '.claude\settings.json'
$skillsDst    = Join-Path $root '.claude\skills'
$skillsSrcRel = '..\.github\skills'
$skillsSrcAbs = Join-Path $root '.github\skills'

function Say($msg) { Write-Host $msg }
function Fail($msg) { Write-Error "install.ps1: $msg"; exit 1 }

if (-not (Test-Path $hooksTpl)) { Fail "missing $hooksTpl" }

New-Item -ItemType Directory -Force -Path (Join-Path $root '.claude\agents') | Out-Null

# ---- 0. render hooks.json from template ----------------------------------
# Substitute __PACK_ROOT__ with this absolute pack path. VS Code Copilot
# does not propagate any env var that carries the workspace path to hook
# commands, so the fallback path must be baked in at install time. Claude
# Code's CLAUDE_PLUGIN_ROOT still takes precedence at runtime. Backslashes
# in $root are doubled because the template embeds the path inside a
# PowerShell single-quoted string passed via -Command "& { ... }".
$packRootEscaped = $root.Replace('\','\\')
(Get-Content $hooksTpl -Raw) -replace '__PACK_ROOT__', $packRootEscaped |
    Set-Content -Path $hooksSrc -Encoding UTF8
Say "[ok] rendered hooks\hooks.json (pack root: $root)"

# ---- 1. sync hooks block -------------------------------------------------
$newHooks = Get-Content $hooksSrc -Raw | ConvertFrom-Json
if (Test-Path $settingsDst) {
    $existing = Get-Content $settingsDst -Raw | ConvertFrom-Json
    if ($null -eq $existing) { $existing = [pscustomobject]@{} }
    $existing | Add-Member -NotePropertyName hooks -NotePropertyValue $newHooks.hooks -Force
    $existing | ConvertTo-Json -Depth 50 | Set-Content -Path $settingsDst -Encoding UTF8
} else {
    $newHooks | ConvertTo-Json -Depth 50 | Set-Content -Path $settingsDst -Encoding UTF8
}
Say "[ok] synced hooks -> .claude\settings.json"

# ---- 2. wire skills ------------------------------------------------------
if (Test-Path $skillsDst) {
    Remove-Item -Recurse -Force $skillsDst
}
try {
    New-Item -ItemType SymbolicLink -Path $skillsDst -Target $skillsSrcRel -ErrorAction Stop | Out-Null
    Say "[ok] linked .claude\skills -> $skillsSrcRel"
} catch {
    Copy-Item -Recurse -Force $skillsSrcAbs $skillsDst
    Say "[ok] copied .github\skills -> .claude\skills (symlink unsupported; re-run install.ps1 after skill changes)"
}

# ---- 3. QI Signal Aggregator MCP server (optional) ----------------------
# As of v0.2.0 the aggregator is a single static Go binary distributed via
# GitHub Releases. No Python or Go toolchain required.
#   - Set QI_INSTALL_AGGREGATOR=0 to skip.
#   - Set QI_AGGREGATOR_VERSION=vX.Y.Z to pin (default: latest release).
$aggregatorDir = Join-Path $root 'mcp\qi-signal-aggregator'
$installAggregator = if ($env:QI_INSTALL_AGGREGATOR) { $env:QI_INSTALL_AGGREGATOR } else { '1' }
if ($installAggregator -eq '1' -and (Test-Path $aggregatorDir)) {
    $binName = 'qi-signal-aggregator.exe'
    $installDir = if ($env:QI_AGGREGATOR_BIN_DIR) { $env:QI_AGGREGATOR_BIN_DIR } `
                  else { Join-Path $env:LOCALAPPDATA 'qi-signal-aggregator\bin' }
    $version = if ($env:QI_AGGREGATOR_VERSION) { $env:QI_AGGREGATOR_VERSION } else { 'latest' }
    $repo    = if ($env:QI_AGGREGATOR_REPO)    { $env:QI_AGGREGATOR_REPO }    else { 'assert-iq/qi-signal-aggregator' }

    # Windows is amd64-only in the v0.1 release matrix.
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { '' }
    if (-not $arch) {
        Say "[skip] qi-signal-aggregator: unsupported Windows architecture"
    } else {
        $asset = "${binName}_windows_${arch}.zip" -replace '\.exe',''
        # goreleaser conventionally names assets WITHOUT the .exe in the
        # archive name, e.g. qi-signal-aggregator_windows_amd64.zip
        $asset = "qi-signal-aggregator_windows_${arch}.zip"
        $urlBase = if ($version -eq 'latest') {
            "https://github.com/$repo/releases/latest/download"
        } else {
            "https://github.com/$repo/releases/download/$version"
        }
        $url    = "$urlBase/$asset"
        $sumUrl = "$urlBase/checksums.txt"

        $tmp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "qisa-$([guid]::NewGuid())")
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $url    -OutFile (Join-Path $tmp $asset) -ErrorAction Stop
            Invoke-WebRequest -UseBasicParsing -Uri $sumUrl -OutFile (Join-Path $tmp 'checksums.txt') -ErrorAction Stop

            $line = Get-Content (Join-Path $tmp 'checksums.txt') | Where-Object { $_ -match "  $asset$" } | Select-Object -First 1
            if ($line) {
                $expected = ($line -split '\s+')[0]
                $actual = (Get-FileHash -Algorithm SHA256 (Join-Path $tmp $asset)).Hash.ToLower()
                if ($expected.ToLower() -ne $actual) {
                    throw "SHA256 mismatch on $asset (expected $expected, got $actual)"
                }
            } else {
                Say "[warn] qi-signal-aggregator: no checksum found for $asset (continuing)"
            }

            New-Item -ItemType Directory -Force -Path $installDir | Out-Null
            Expand-Archive -Force -Path (Join-Path $tmp $asset) -DestinationPath $tmp
            Move-Item -Force -Path (Join-Path $tmp $binName) -Destination (Join-Path $installDir $binName)

            Say "[ok] installed $binName ($version, windows/$arch) -> $installDir"
            if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $installDir })) {
                Say "     NOTE: $installDir is not in `$env:PATH. Add it via System Properties or:"
                Say "     [Environment]::SetEnvironmentVariable('PATH', `$env:PATH + ';$installDir', 'User')"
            }
            Say "[ok] client snippets at: $aggregatorDir\clients\"
            Say "     - VS Code / Copilot : copy clients\vscode-mcp.json -> .vscode\mcp.json"
            Say "     - Claude Code       : copy clients\claude-code.json -> .mcp.json (workspace) or ~\.claude.json"
            Say "     - Codex CLI         : copy clients\codex-cli.toml block -> ~\.codex\config.toml"
            Say "     Try it: $binName --config $aggregatorDir\samples\config.yaml demo"
        } catch {
            Say "[skip] qi-signal-aggregator: download failed ($($_.Exception.Message))"
            Say "       Build from source: cd $aggregatorDir; go build -o $installDir\$binName .\cmd\qi-signal-aggregator"
        } finally {
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }
}

Say ""
Say "Pack installed."
Say "  Copilot reads .github\copilot-instructions.md, .github\instructions\*, .github\agents\*, .github\skills\*"
Say "  Claude  reads CLAUDE.md, .claude\agents\*, .claude\skills\*, .claude\settings.json (hooks)"
Say "  MCP     qi-signal-aggregator (if installed): see $aggregatorDir\README.md"
