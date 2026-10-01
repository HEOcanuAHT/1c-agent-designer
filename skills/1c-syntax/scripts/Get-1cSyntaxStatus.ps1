<#
.SYNOPSIS
  Status of bsl-ctx syntax DB for this project (JSON).
#>
[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "Common-Syntax.ps1")
Install-SyntaxMcpShim

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfg = Read-SyntaxProjectCfg $ProjectRoot
$ver = Get-SyntaxPlatformVersion $cfg
$uvx = Find-UvxExe
$binDir = $null
$hbk = $false
try {
  if ($cfg) { $binDir = Resolve-SyntaxBinDir $cfg }
} catch { }
if ($binDir) { $hbk = Test-SyntaxHbk $binDir }
$db = Find-SyntaxDb $ver
$compat = $null
if ($cfg) { $compat = Get-SyntaxCompatTarget $ProjectRoot $cfg }

$report = [ordered]@{
  projectRoot       = $ProjectRoot
  platformVersion   = $ver
  binDir            = $binDir
  hbkOk             = [bool]$hbk
  uvx               = $uvx
  dataDir           = Get-SyntaxDataDir
  db                = $db
  dbOk              = [bool]($db -and (Test-Path -LiteralPath $db))
  compatTarget      = $compat
  bslCtxSpec        = Get-BslCtxSpec
  ready             = $false
  missing           = @()
  hint              = $null
}

if (-not $ver) { $report.missing += "platformVersion" }
if (-not $hbk) { $report.missing += "shcntx_ru.hbk" }
if (-not $uvx) { $report.missing += "uvx" }
if (-not $report.dbOk) { $report.missing += "syntax-db" }

$report.ready = ($report.missing.Count -eq 0)
if (-not $report.dbOk) {
  $report.hint = "Run /1c-syntax-index (Build-1cSyntaxDb.ps1 -ProjectRoot workspace [-Rebuild])"
}

$report | ConvertTo-Json -Depth 5
if ($report.ready) { exit 0 } else { exit 1 }
