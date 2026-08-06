<#
.SYNOPSIS
  Validate 1C query text via COM on service IB (.1c/ib-ext).

.DESCRIPTION
  V83.COMConnector — QuerySchema + Query.FindParameters.
  No ENTERPRISE / HTTP / extension. Needs applied main config on .1c/ib-ext
  (Get-ServiceIbCfg -AllowApply).

.PARAMETER Action
  validate — check query (default)
  ensure   — prepare service IB (import + apply)
  stop     — no-op (back-compat; no HTTP listener)
  health   — COM connect smoke test
#>
[CmdletBinding()]
param(
  [ValidateSet("validate", "ensure", "stop", "health")]
  [string]$Action = "validate",

  [string]$ProjectRoot = (Get-Location).Path,
  [string]$QueryText = "",
  [string]$QueryFile = "",
  [switch]$RefreshServiceIb
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CommonPath = Join-Path $ScriptDir "..\..\1c-external-epf\scripts\Common-ServiceIb.ps1"
. (Resolve-Path -LiteralPath $CommonPath).Path

function Get-QvStatePaths([string]$ProjectRoot) {
  $dir = Join-Path $ProjectRoot ".1c"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  return @{
    Dir = $dir
    Log = Join-Path $dir "qv-validate.log"
  }
}

function Ensure-LogLine([string]$Log, [string]$Line) {
  Add-Content -LiteralPath $Log -Value $Line -Encoding UTF8
}

function Resolve-QueryText([string]$QueryText, [string]$QueryFile) {
  if ($QueryFile) {
    if (-not (Test-Path -LiteralPath $QueryFile)) { throw "QueryFile not found: $QueryFile" }
    return (Get-Content -LiteralPath $QueryFile -Raw -Encoding UTF8)
  }
  if ($QueryText) { return $QueryText }
  throw "Provide -QueryText or -QueryFile"
}

function Get-ComErrorMessage([Exception]$Ex) {
  $cur = $Ex
  $parts = New-Object System.Collections.Generic.List[string]
  while ($null -ne $cur) {
    if ($cur.Message -and -not $parts.Contains($cur.Message)) { $parts.Add($cur.Message) }
    $cur = $cur.InnerException
  }
  $joined = ($parts -join " | ")
  # Prefer platform {(line,col)} fragment when present
  if ($joined -match '(\{\([0-9]+,\s*[0-9]+\)\}:[^|]+)') {
    return $Matches[1].Trim()
  }
  return $joined
}

function Connect-ServiceIbCom($Paths) {
  $connector = New-Object -ComObject "V83.COMConnector"
  $connStr = "File=`"$($Paths.DbAbs)`";"
  Write-Host "COM_CONNECT $connStr"
  return $connector.Connect($connStr)
}

function Test-QueryViaCom($Connection, [string]$Text) {
  $bfInvoke = [System.Reflection.BindingFlags]::InvokeMethod
  $bfSet = [System.Reflection.BindingFlags]::SetProperty
  try {
    $schema = [System.__ComObject].InvokeMember("NewObject", $bfInvoke, $null, $Connection, @("QuerySchema"))
    [void][System.__ComObject].InvokeMember("SetQueryText", $bfInvoke, $null, $schema, @($Text))
    $null = [System.__ComObject].InvokeMember("GetQueryText", $bfInvoke, $null, $schema, $null)
  } catch {
    return @{ valid = $false; error = (Get-ComErrorMessage $_.Exception) }
  }
  try {
    $q = [System.__ComObject].InvokeMember("NewObject", $bfInvoke, $null, $Connection, @("Query"))
    [void][System.__ComObject].InvokeMember("Text", $bfSet, $null, $q, @($Text))
    $null = [System.__ComObject].InvokeMember("FindParameters", $bfInvoke, $null, $q, $null)
  } catch {
    return @{ valid = $false; error = (Get-ComErrorMessage $_.Exception) }
  }
  return @{ valid = $true; error = "" }
}

# --- main ---

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfgPath = Join-Path $ProjectRoot ".1c\project.json"
$localPath = Join-Path $ProjectRoot ".1c\project.local.json"
$cfg = Merge-Config (Read-JsonFile $cfgPath) (Read-JsonFile $localPath)
if ($null -eq $cfg) { throw "Missing .1c/project.json under $ProjectRoot" }

$state = Get-QvStatePaths $ProjectRoot
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Ensure-LogLine $state.Log "`n=== $ts action=$Action engine=Com ==="

if ($Action -eq "stop") {
  Write-Host "OK action=stop (no-op; COM has no HTTP listener)"
  exit 0
}

$srcRel = Get-SrcRel $cfg
$srcAbs = Resolve-UnderRoot $ProjectRoot $srcRel

# Applied main config on service IB (metadata for QuerySchema)
$ctx = Get-ServiceIbCfg $cfg $ProjectRoot $srcAbs `
  -ForceRefresh:$RefreshServiceIb `
  -AllowApply

if (-not $ctx.Paths) {
  throw "Service IB disabled (ext.serviceIb.enabled=false). Enable it for query validate."
}

if ($Action -eq "ensure") {
  Write-Host "OK action=ensure engine=Com db=$($ctx.Paths.DbAbs)"
  exit 0
}

if ($Action -eq "health") {
  $c = Connect-ServiceIbCom $ctx.Paths
  $null = $c
  Write-Host "OK action=health engine=Com"
  exit 0
}

$text = Resolve-QueryText $QueryText $QueryFile
$conn = Connect-ServiceIbCom $ctx.Paths
$result = Test-QueryViaCom $conn $text
$conn = $null
[GC]::Collect()
[GC]::WaitForPendingFinalizers()

if ($result.valid) {
  Write-Host "VALID=true"
  Write-Host "OK action=validate engine=Com"
  exit 0
}
Write-Host "VALID=false"
Write-Host "ERROR=$($result.error)"
Write-Host "FAIL action=validate engine=Com"
exit 1
