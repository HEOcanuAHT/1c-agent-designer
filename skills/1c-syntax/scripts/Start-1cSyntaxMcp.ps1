<#
.SYNOPSIS
  stdio MCP entry: bsl-ctx serve if DB exists, else stub with DB_MISSING.

  Logs go to stderr only. stdout is JSON-RPC.
  Do not set BSL_CTX_TARGET_VERSION: one shared MCP serves many projects.
  Agents filter by CompatibilityMode vs hit.since.
#>
[CmdletBinding()]
param(
  [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Common-Syntax.ps1")
Set-BslCtxUtf8Env
Install-SyntaxMcpShim

$cfg = $null
$ver = $null
if ($ProjectRoot -and $ProjectRoot -notmatch '\$\{' -and (Test-Path -LiteralPath $ProjectRoot)) {
  try { $cfg = Read-SyntaxProjectCfg $ProjectRoot } catch { }
  $ver = Get-SyntaxPlatformVersion $cfg
}

$db = Find-SyntaxDb $ver
$uvx = Find-UvxExe
$stub = Join-Path $PSScriptRoot "..\mcp\stub_server.py"

if ($db -and (Test-Path -LiteralPath $db) -and $uvx) {
  Write-SyntaxLog ("bsl-syntax: serve db={0} (no process target_version; agent filters by since)" -f $db)
  $spec = Get-BslCtxSpec
  & $uvx --from $spec bsl-ctx serve --db $db
  exit $LASTEXITCODE
}

Write-SyntaxLog "bsl-syntax: DB missing or uvx missing, starting stub"
$py = Find-SyntaxPython
if (-not $py) {
  Write-SyntaxLog "ERROR: python not found for stub MCP. Install uv + Python 3.12 and run /1c-syntax-index."
  exit 1
}
$stubArgs = @($stub)
if ($ProjectRoot) { $stubArgs += @("--project-root", $ProjectRoot) }
if ($ver) { $stubArgs += @("--platform", $ver) }
& $py @stubArgs
exit $LASTEXITCODE
