# PostToolUse hook: run `dotnet format` on edited C# files in the MDA solution.
# Fires in the background; logs to %USERPROFILE%\.agents\hooks\logs\.

$ErrorActionPreference = 'SilentlyContinue'

function Send-Continue {
    Write-Output '{"continue":true}'
}

try {
    if ([Console]::IsInputRedirected -eq $false) { Send-Continue; exit 0 }
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Send-Continue; exit 0 }

    $data = $raw | ConvertFrom-Json -ErrorAction Stop
    $tool = $data.tool_name; if (-not $tool) { $tool = $data.toolName }
    $ti = $data.tool_input;  if (-not $ti)   { $ti   = $data.toolArgs }
    $file = $null
    if ($ti) { $file = $ti.filePath; if (-not $file) { $file = $ti.file_path }; if (-not $file) { $file = $ti.path } }

    $allowed = @('replace_string_in_file','multi_replace_string_in_file','create_file','edit_notebook_file')
    if ($allowed -notcontains $tool) { Send-Continue; exit 0 }
    if (-not $file) { Send-Continue; exit 0 }

    # Find the MDA repo on this machine. Adjust env var MDA_REPO if non-default.
    $repo = $env:MDA_REPO
    if (-not $repo) { $repo = Join-Path $env:USERPROFILE 'MDA' }
    $srcPrefix = (Join-Path $repo 'src') + [IO.Path]::DirectorySeparatorChar
    $fileNorm = $file -replace '/', [IO.Path]::DirectorySeparatorChar

    if (-not $fileNorm.StartsWith($srcPrefix, [StringComparison]::OrdinalIgnoreCase)) { Send-Continue; exit 0 }
    if ($fileNorm -notmatch '\.cs$') { Send-Continue; exit 0 }
    if ($fileNorm -match '\\(obj|bin)\\' -or $fileNorm -match '\.(g|[Dd]esigner)\.cs$') { Send-Continue; exit 0 }

    $sln = Join-Path $srcPrefix 'UPS.GPMS.PanDAS.Client.sln'
    $logDir = Join-Path $env:USERPROFILE '.agents\hooks\logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $log = Join-Path $logDir 'dotnet-format.log'

    $cmd = "Add-Content -Path '$log' -Value ('---- ' + (Get-Date).ToUniversalTime().ToString('o') + ' format: $fileNorm'); " +
           "& dotnet format '$sln' --include '$fileNorm' --no-restore --verbosity quiet *>> '$log'; " +
           "Add-Content -Path '$log' -Value ('---- exit=' + `$LASTEXITCODE)"
    Start-Process -FilePath 'powershell' -ArgumentList '-NoProfile','-WindowStyle','Hidden','-Command',$cmd -WindowStyle Hidden | Out-Null
} catch {}

Send-Continue
