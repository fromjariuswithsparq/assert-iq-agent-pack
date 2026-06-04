# Shared helper: render hooks.template.json with __PACK_ROOT__ substituted
# for an absolute path. Dot-sourced by install.ps1 and scripts/bootstrap.ps1
# so the substitution logic stays in one place.
#
# Usage:
#   . "$PSScriptRoot\..\..\hooks\scripts\lib\render-hooks.ps1"
#   Render-HooksTemplate -Template <path> -Out <path> -PackRoot <path>

# Render <Template> -> <Out>, replacing __PACK_ROOT__ with <PackRoot>.
# Uses literal [string]::Replace (NOT -replace) so backslashes and `$`
# characters in Windows paths (admin shares like C:\admin$, UNC share$, etc.)
# are not interpreted as regex backreferences. __PACK_ROOT__ appears inside
# JSON string values in the template, so both `\` and `"` must be JSON-escaped.
function Render-HooksTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Template,
        [Parameter(Mandatory)] [string] $Out,
        [Parameter(Mandatory)] [string] $PackRoot
    )
    if (-not (Test-Path -LiteralPath $Template)) {
        throw "render-hooks: template not found: $Template"
    }
    $escaped = $PackRoot.Replace('\', '\\').Replace('"', '\"')
    $rendered = (Get-Content -LiteralPath $Template -Raw).Replace('__PACK_ROOT__', $escaped)
    Set-Content -LiteralPath $Out -Value $rendered -Encoding UTF8 -NoNewline
}
