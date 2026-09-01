<#
.SYNOPSIS
  Stable MCP entry at %LOCALAPPDATA%\1c-agent-designer\mcp-serve.ps1

  Cursor plugin mcp.json cannot use ./ or %PLUGIN_ROOT% (not injected).
  Logs to stderr. stdout is JSON-RPC.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONLEGACYWINDOWSSTDIO = "0"
$env:NO_COLOR = "1"
try { chcp 65001 | Out-Null } catch { }

function Write-McpLog([string]$Message) {
  [Console]::Error.WriteLine($Message)
}

function Find-UvxExe {
  foreach ($name in @("uvx", "uv")) {
    $cmd = Get-Command $name -EA SilentlyContinue
    if ($cmd -and $cmd.Source -and ($cmd.Source -notmatch 'WindowsApps\\')) {
      if ($name -eq "uvx") { return $cmd.Source }
      $sibling = Join-Path (Split-Path -Parent $cmd.Source) "uvx.exe"
      if (Test-Path -LiteralPath $sibling) { return $sibling }
    }
  }
  foreach ($c in @(
      (Join-Path $env:USERPROFILE ".local\bin\uvx.exe"),
      (Join-Path $env:USERPROFILE ".cargo\bin\uvx.exe"),
      (Join-Path $env:LOCALAPPDATA "Programs\uv\uvx.exe")
    )) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  return $null
}

function Find-Python {
  foreach ($name in @("python", "python3")) {
    $cmd = Get-Command $name -EA SilentlyContinue
    if ($cmd -and $cmd.Source -and ($cmd.Source -notmatch 'WindowsApps\\python')) {
      return $cmd.Source
    }
  }
  foreach ($c in @(
      "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
      "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
    )) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  return $null
}

function Find-Db {
  $dir = Join-Path $env:LOCALAPPDATA "bsl-ctx"
  if ($env:BSL_CTX_DATA_DIR) { $dir = [string]$env:BSL_CTX_DATA_DIR.Trim() }
  if (-not (Test-Path -LiteralPath $dir)) { return $null }
  $found = @(Get-ChildItem -LiteralPath $dir -Filter "bsl-context-*.sqlite" -File -EA SilentlyContinue |
    Sort-Object Name -Descending)
  if ($found.Count -ge 1) { return $found[0].FullName }
  return $null
}

$db = Find-Db
$uvx = Find-UvxExe
$spec = "bsl-ctx==1.4.0"

if ($db -and $uvx) {
  Write-McpLog ("bsl-syntax: serve db={0}" -f $db)
  & $uvx --from $spec bsl-ctx serve --db $db
  exit $LASTEXITCODE
}

Write-McpLog "bsl-syntax: DB or uvx missing, stub"
$py = Find-Python
$stub = Join-Path $PSScriptRoot "stub_server.py"
if (-not $py -or -not (Test-Path -LiteralPath $stub)) {
  Write-McpLog "ERROR: install uv + Python 3.12 and run /1c-syntax-index"
  exit 1
}
& $py $stub
exit $LASTEXITCODE
