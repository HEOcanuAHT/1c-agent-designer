<#
.SYNOPSIS
  Agent CLI for the service file IB (.1c/ib-ext): ensure / status.

.DESCRIPTION
  Wraps Ensure-ServiceIb from Common-ServiceIb.ps1. Call only via -File
  (Cursor expands $variables in powershell -Command).

  Default ensure path matches EPF: save .cf from the project IB / XML import
  fallback, no config apply. -AllowApply is opt-in (query-validate stamp).
#>
[CmdletBinding()]
param(
  [ValidateSet("ensure", "status")]
  [string]$Action = "ensure",

  [string]$ProjectRoot = (Get-Location).Path,

  [switch]$Force,
  [switch]$RefreshServiceIb,
  [switch]$AllowApply
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "Common-ServiceIb.ps1")

$doForce = [bool]($Force -or $RefreshServiceIb)
$sw = [Diagnostics.Stopwatch]::StartNew()

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfgPath = Join-Path $ProjectRoot ".1c\project.json"
if (-not (Test-Path -LiteralPath $cfgPath)) {
  throw "Missing $cfgPath - copy .1c/project.json.example -> .1c/project.json."
}
$Cfg = Merge-Config (Read-JsonFile $cfgPath) (Read-JsonFile (Join-Path $ProjectRoot ".1c\project.local.json"))

if (-not (Test-ServiceIbEnabled $Cfg)) {
  throw "Service IB disabled (ext.serviceIb.enabled=false). Enable it in project.json."
}

$srcAbs = Resolve-UnderRoot $ProjectRoot (Get-SrcRel $Cfg)
$paths = Get-ServiceIbPaths $Cfg $ProjectRoot
$stamp = "{0}|apply={1}" -f (Get-ConfigImportStamp $srcAbs), ([bool]$AllowApply)
$alreadyReady = (-not $doForce) -and (Test-ServiceIbCurrent $paths $stamp)

Write-Host ("1c-service-ib action={0} force={1} allowApply={2}" -f $Action, $doForce, ([bool]$AllowApply))

if ($Action -eq "status") {
  $sw.Stop()
  $elapsedSec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  if ($alreadyReady) {
    Write-Host "SERVICE_IB=ready stamp=$stamp path=$($paths.DbAbs)"
  } else {
    Write-Host "SERVICE_IB=stale stamp=$stamp path=$($paths.DbAbs)"
    Write-Host "HINT=run: powershell -NoProfile -File ...\Invoke-1cServiceIb.ps1 -Action ensure -ProjectRoot `"$ProjectRoot`""
  }
  Write-Host ("ELAPSED_SEC={0}" -f $elapsedSec)
  Write-Host "OK action=status"
  $result = [ordered]@{
    status = "ok"
    action = "status"
    ready  = [bool]$alreadyReady
    apply  = [bool]$AllowApply
    path   = $paths.DbAbs
    sec    = $elapsedSec
  }
  Write-Host ("RESULT=" + ($result | ConvertTo-Json -Compress))
  [Console]::Out.Flush()
  exit 0
}

$ctx = Get-ServiceIbCfg $Cfg $ProjectRoot $srcAbs `
  -ForceRefresh:$doForce `
  -AllowApply:$AllowApply
if (-not $ctx.Paths) {
  throw "Service IB skipped (ext.serviceIb.enabled=false). Enable it in project.json."
}
$paths = $ctx.Paths

$sw.Stop()
$elapsedSec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
$rebuilt = -not $alreadyReady
Write-Host ("ELAPSED_SEC={0}" -f $elapsedSec)
Write-Host "OK action=ensure"
$result = [ordered]@{
  status  = "ok"
  action  = "ensure"
  apply   = [bool]$AllowApply
  rebuilt = [bool]$rebuilt
  path    = $paths.DbAbs
  sec     = $elapsedSec
}
Write-Host ("RESULT=" + ($result | ConvertTo-Json -Compress))
[Console]::Out.Flush()
if ([Console]::Error) { [Console]::Error.Flush() }
exit 0
