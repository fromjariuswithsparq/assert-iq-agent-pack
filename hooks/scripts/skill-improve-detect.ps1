# PostToolUse hook (Windows): append a compact record of each tool call.
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'lib\json-utils.ps1')

try {
    if (-not (Test-SiEnabled)) { Send-SiContinue; exit 0 }
    if ([Console]::IsInputRedirected -eq $false) { Send-SiContinue; exit 0 }

    $raw = Read-SiStdin
    if (-not $raw) { Send-SiContinue; exit 0 }

    $d = $raw | ConvertFrom-Json -ErrorAction Stop
    $sid = Get-SiSessionId -Raw $raw
    $sdir = Get-SiSessionDir -SessionId $sid

    $tool = $d.tool_name; if (-not $tool) { $tool = $d.toolName }
    $ti = $d.tool_input;  if (-not $ti)   { $ti   = $d.toolArgs }
    $tr = $d.tool_response; if (-not $tr) { $tr = $d.toolResponse }

    $file = ''
    if ($ti) {
        $file = $ti.filePath
        if (-not $file) { $file = $ti.file_path }
        if (-not $file) { $file = $ti.path }
        if (-not $file -and $ti.replacements -and $ti.replacements.Count -gt 0) {
            $file = $ti.replacements[0].filePath
            if (-not $file) { $file = $ti.replacements[0].file_path }
        }
    }

    $err = $false
    if ($tr) {
        if ($tr -is [string]) {
            if ($tr -match '(?i)error|failed') { $err = $true }
        } else {
            if ($tr.error -or $tr.isError -or $tr.is_error) { $err = $true }
            $msg = $tr.message; if (-not $msg) { $msg = $tr.content }
            if ($msg -is [string] -and $msg.Length -lt 400 -and $msg -match '(?i)error|failed') { $err = $true }
        }
    }

    $rec = @{
        ts    = (Get-Date).ToUniversalTime().ToString('o')
        tool  = $tool
        file  = $file
        error = $err
    }
    # Customization invocation flag: parity with detect.sh.
    if ($tool -eq 'read_file' -and $file) {
        try {
            $loadedPath = Join-Path $sdir 'loaded-customizations.json'
            if (Test-Path $loadedPath) {
                $loaded = Get-Content -Raw $loadedPath | ConvertFrom-Json
                $loadedEntries = @()
                if ($loaded.customization_files) { $loadedEntries = @($loaded.customization_files) }
                elseif ($loaded.skill_files)     { $loadedEntries = @($loaded.skill_files) }
                $loadedPaths = @()
                foreach ($entry in $loadedEntries) {
                    if ($entry -is [string]) { $loadedPaths += $entry }
                    elseif ($entry.path)     { $loadedPaths += $entry.path }
                }
                if ($loadedPaths -contains $file) { $rec.customization_invoked = $true }
            }
        } catch {}
    }
    # VS Code: replace_string_in_file / multi_replace_string_in_file; Claude Code: Edit / MultiEdit
    if ($tool -in @('replace_string_in_file','multi_replace_string_in_file','Edit','MultiEdit')) {
        $snippet = $ti.newString; if (-not $snippet) { $snippet = $ti.new_string }
        if ($snippet) {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$snippet"))
            $rec.new_snippet_hash = [BitConverter]::ToInt64($bytes, 0).ToString()
        }
    }
    $line = ($rec | ConvertTo-Json -Compress -Depth 5)
    Add-Content -Path (Join-Path $sdir 'tool-log.jsonl') -Value $line -Encoding UTF8
} catch {}

Send-SiContinue
