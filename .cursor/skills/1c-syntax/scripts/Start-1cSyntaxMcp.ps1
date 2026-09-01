<#
.SYNOPSIS
  stdio MCP entry: bsl-ctx serve if DB exists, else stub with DB_MISSING.

  Logs go to stderr only. stdout is JSON-RPC.
#>
[CmdletBinding()]
param(
  [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Common-Syntax.ps1")
Set-BslCtxUtf8Env

function Test-UsablePath([string]$P) {
  if (-not $P) { return $false }
  if ($P -match '\$\{') { return $false }
  return (Test-Path -LiteralPath $P)
}

if (-not (Test-UsablePath $ProjectRoot)) {
  foreach ($c in @($env:CURSOR_PROJECT_DIR, $env:WORKSPACE_FOLDER, (Get-Location).Path)) {
    if (Test-UsablePath $c) { $ProjectRoot = [string]$c; break }
  }
}
try {
  $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
} catch {
  Write-SyntaxLog "WARN: ProjectRoot not resolved, using cwd"
}

$cfg = $null
try { $cfg = Read-SyntaxProjectCfg $ProjectRoot } catch { }
$ver = Get-SyntaxPlatformVersion $cfg
$compat = $null
if ($cfg) { $compat = Get-SyntaxCompatTarget $ProjectRoot $cfg }
$db = Find-SyntaxDb $ver
$uvx = Find-UvxExe
$stub = Join-Path $PSScriptRoot "..\mcp\stub_server.py"

if ($compat) { $env:BSL_CTX_TARGET_VERSION = $compat }
elseif ($ver) { $env:BSL_CTX_TARGET_VERSION = $ver }

if ($db -and (Test-Path -LiteralPath $db) -and $uvx) {
  Write-SyntaxLog ("bsl-syntax: serve db={0} target={1}" -f $db, $env:BSL_CTX_TARGET_VERSION)
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
$stubArgs = @($stub, "--project-root", $ProjectRoot)
if ($ver) { $stubArgs += @("--platform", $ver) }
if ($compat) { $stubArgs += @("--compat", $compat) }
& $py @stubArgs
exit $LASTEXITCODE
