# PostToolUse hook: lint edited .xaml for interactive elements missing AutomationId.
# Findings logged and surfaced to the agent via `systemMessage`.

$ErrorActionPreference = 'SilentlyContinue'

$findings = ''
function Send-Result {
    param([string]$msg)
    if ($msg) {
        $payload = @{ continue = $true; systemMessage = $msg } | ConvertTo-Json -Compress
        Write-Output $payload
    } else {
        Write-Output '{"continue":true}'
    }
}

try {
    if ([Console]::IsInputRedirected -eq $false) { Send-Result ''; exit 0 }
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Send-Result ''; exit 0 }

    $data = $raw | ConvertFrom-Json -ErrorAction Stop
    $tool = $data.tool_name; if (-not $tool) { $tool = $data.toolName }
    $ti = $data.tool_input;  if (-not $ti)   { $ti   = $data.toolArgs }
    $file = $null
    if ($ti) { $file = $ti.filePath; if (-not $file) { $file = $ti.file_path }; if (-not $file) { $file = $ti.path } }

    $allowed = @('replace_string_in_file','multi_replace_string_in_file','create_file','edit_notebook_file')
    if ($allowed -notcontains $tool) { Send-Result ''; exit 0 }
    if (-not $file) { Send-Result ''; exit 0 }

    $repo = $env:MDA_REPO
    if (-not $repo) { $repo = Join-Path $env:USERPROFILE 'MDA' }
    $srcPrefix = (Join-Path $repo 'src') + [IO.Path]::DirectorySeparatorChar
    $fileNorm = $file -replace '/', [IO.Path]::DirectorySeparatorChar

    if (-not $fileNorm.StartsWith($srcPrefix, [StringComparison]::OrdinalIgnoreCase)) { Send-Result ''; exit 0 }
    if ($fileNorm -notmatch '\.xaml$') { Send-Result ''; exit 0 }
    if ($fileNorm -match '\\(obj|bin)\\') { Send-Result ''; exit 0 }
    if (-not (Test-Path $fileNorm)) { Send-Result ''; exit 0 }

    $interactive = @('Button','ImageButton','Entry','Editor','SearchBar','Picker','DatePicker',
                     'TimePicker','CheckBox','Switch','Stepper','Slider','RadioButton',
                     'RefreshView','ListView','CollectionView','CarouselView','TabbedPage','SwipeView')
    $text = Get-Content -Raw -Path $fileNorm
    $issues = New-Object System.Collections.Generic.List[string]
    $regex = [regex]'<(?:[A-Za-z_][\w.]*:)?([A-Za-z_]\w*)\b([^>]*?)/?>'
    foreach ($m in $regex.Matches($text)) {
        $tag = $m.Groups[1].Value
        $attrs = $m.Groups[2].Value
        if ($interactive -notcontains $tag) { continue }
        if ($attrs -match '\bAutomationId\s*=') { continue }
        $line = ($text.Substring(0, $m.Index) -split "`n").Length
        $issues.Add("  L${line}: <$tag> missing AutomationId")
    }
    if ($issues.Count -gt 0) {
        $fname = Split-Path -Leaf $fileNorm
        $findings = "AutomationId lint - ${fname}:`n" + ($issues -join "`n")
        $logDir = Join-Path $env:USERPROFILE '.agents\hooks\logs'
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $log = Join-Path $logDir 'automationid-lint.log'
        Add-Content -Path $log -Value ("---- " + (Get-Date).ToUniversalTime().ToString('o') + " $fileNorm")
        Add-Content -Path $log -Value $findings
    }
} catch {}

Send-Result $findings
