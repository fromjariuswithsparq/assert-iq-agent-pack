# PostToolUse hook: when a UnitTests file is edited, run `dotnet test` for the
# project in the background. Output goes to %USERPROFILE%\.agents\hooks\logs\.

$ErrorActionPreference = 'SilentlyContinue'

function Send-Continue { Write-Output '{"continue":true}' }

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

    $repo = $env:MDA_REPO
    if (-not $repo) { $repo = Join-Path $env:USERPROFILE 'MDA' }
    $unitTestsDir = Join-Path (Join-Path $repo 'src') 'UPS.GPMS.PanDAS.Client.UnitTests'
    $fileNorm = $file -replace '/', [IO.Path]::DirectorySeparatorChar

    if (-not $fileNorm.StartsWith($unitTestsDir + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { Send-Continue; exit 0 }
    if ($fileNorm -notmatch '\.cs$') { Send-Continue; exit 0 }
    if ($fileNorm -match '\\(obj|bin)\\') { Send-Continue; exit 0 }

    $logDir = Join-Path $env:USERPROFILE '.agents\hooks\logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $log  = Join-Path $logDir 'affected-tests.log'
    $lock = Join-Path $logDir 'affected-tests.lock'

    # Best-effort coalescing — skip if another run is in flight.
    if (Test-Path $lock) {
        $age = (Get-Date) - (Get-Item $lock).LastWriteTime
        if ($age.TotalMinutes -lt 15) { Send-Continue; exit 0 }
    }
    Set-Content -Path $lock -Value $PID

    $class = [IO.Path]::GetFileNameWithoutExtension($fileNorm)
    $filter = ''
    if ($class -match 'Tests?$') { $filter = "--filter FullyQualifiedName~.$class." }

    $cmd = "Add-Content -Path '$log' -Value ('---- ' + (Get-Date).ToUniversalTime().ToString('o') + ' trigger: $fileNorm'); " +
           "Add-Content -Path '$log' -Value ('---- filter: $filter'); " +
           "& dotnet test '$unitTestsDir' --nologo --verbosity minimal $filter *>> '$log'; " +
           "Add-Content -Path '$log' -Value ('---- exit=' + `$LASTEXITCODE); " +
           "Remove-Item -Force '$lock'"
    Start-Process -FilePath 'powershell' -ArgumentList '-NoProfile','-WindowStyle','Hidden','-Command',$cmd -WindowStyle Hidden | Out-Null
} catch {}

Send-Continue
