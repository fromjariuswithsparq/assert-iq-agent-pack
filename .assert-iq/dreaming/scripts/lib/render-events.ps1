# Shared helper: render session-events.template.json with __PACK_ROOT__
# substituted for an absolute path. Dot-sourced by install.ps1 and bootstrap.ps1.

function Render-EventsTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Template,
        [Parameter(Mandatory)] [string] $Out,
        [Parameter(Mandatory)] [string] $PackRoot
    )
    if (-not (Test-Path -LiteralPath $Template)) {
        throw "render-events: template not found: $Template"
    }
    $escaped = $PackRoot.Replace('\', '\\').Replace('"', '\"')
    $rendered = (Get-Content -LiteralPath $Template -Raw).Replace('__PACK_ROOT__', $escaped)
    Set-Content -LiteralPath $Out -Value $rendered -Encoding UTF8 -NoNewline
}
