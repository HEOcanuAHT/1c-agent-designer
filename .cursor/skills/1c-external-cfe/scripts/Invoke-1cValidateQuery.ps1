<#
.SYNOPSIS
  Validate 1C query text via COM on service IB (.1c/ib-ext).

.DESCRIPTION
  V83.COMConnector — QuerySchema + Query.FindParameters.
  No ENTERPRISE / HTTP / extension.

  Agent-friendly path (fewer Cursor Allow prompts):
    1) once per session / after src dump: -Action ensure
    2) validate with -ReuseOnly (no ibcmd wipe/import/apply) + optional -BatchDir

.PARAMETER Action
  validate — check query (default)
  ensure   — prepare service IB (import + apply)
  stop     — no-op (back-compat)
  health   — COM connect smoke test

.PARAMETER ReuseOnly
  Do not call Ensure/ibcmd. Fail with NEED_ENSURE=true (exit 2) if .1c/ib-ext is missing/stale.
  Prefer this for every validate after ensure.
#>
[CmdletBinding()]
param(
  [ValidateSet("validate", "ensure", "stop", "health")]
  [string]$Action = "validate",

  [string]$ProjectRoot = (Get-Location).Path,
  [string]$QueryText = "",
  [string]$QueryFile = "",
  [string[]]$QueryFiles = @(),
  [string]$BatchDir = "",
  [switch]$ReuseOnly,
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
  throw "Provide -QueryText, -QueryFile, -QueryFiles, or -BatchDir"
}

function Get-ComErrorMessage([Exception]$Ex) {
  $cur = $Ex
  $parts = New-Object System.Collections.Generic.List[string]
  while ($null -ne $cur) {
    if ($cur.Message -and -not $parts.Contains($cur.Message)) { $parts.Add($cur.Message) }
    $cur = $cur.InnerException
  }
  $joined = ($parts -join " | ")
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

function Get-BatchItems([string]$BatchDir, [string[]]$QueryFiles, [string]$QueryFile, [string]$QueryText) {
  $items = New-Object System.Collections.Generic.List[object]
  if ($BatchDir) {
    if (-not (Test-Path -LiteralPath $BatchDir)) { throw "BatchDir not found: $BatchDir" }
    Get-ChildItem -LiteralPath $BatchDir -File |
      Where-Object { $_.Extension -match '^\.(txt|query)$' -or $_.Name -like '*.bsl-query' } |
      Sort-Object Name |
      ForEach-Object {
        $items.Add([pscustomobject]@{ Id = $_.Name; Text = (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8) })
      }
    if ($items.Count -eq 0) { throw "BatchDir has no .txt/.query files: $BatchDir" }
    return $items
  }
  if ($QueryFiles -and $QueryFiles.Count -gt 0) {
    $i = 0
    foreach ($f in $QueryFiles) {
      $i++
      $name = Split-Path -Leaf $f
      if (-not $name) { $name = "query-$i" }
      $items.Add([pscustomobject]@{ Id = $name; Text = (Resolve-QueryText "" $f) })
    }
    return $items
  }
  if ($QueryFile -or $QueryText) {
    $id = if ($QueryFile) { Split-Path -Leaf $QueryFile } else { "inline" }
    $items.Add([pscustomobject]@{ Id = $id; Text = (Resolve-QueryText $QueryText $QueryFile) })
    return $items
  }
  throw "Provide -QueryText, -QueryFile, -QueryFiles, or -BatchDir"
}

function Resolve-ServiceIbPathsReuseOnly($Cfg, [string]$ProjectRoot, [string]$SrcAbs) {
  if (-not (Test-ServiceIbEnabled $Cfg)) {
    throw "Service IB disabled (ext.serviceIb.enabled=false). Enable it for query validate."
  }
  $paths = Get-ServiceIbPaths $Cfg $ProjectRoot
  $cd = Join-Path $paths.DbAbs "1Cv8.1CD"
  if (-not (Test-Path -LiteralPath $cd)) {
    Write-Host "NEED_ENSURE=true"
    Write-Host "REASON=service IB missing ($($paths.DbAbs))"
    exit 2
  }
  $expected = "{0}|apply=True" -f (Get-ConfigImportStamp $SrcAbs)
  if (-not (Test-ServiceIbCurrent $paths $expected)) {
    Write-Host "NEED_ENSURE=true"
    Write-Host "REASON=stamp stale or missing (expected apply=True)"
    Write-Host "HINT=run: powershell -NoProfile -File ...\Invoke-1cValidateQuery.ps1 -Action ensure"
    exit 2
  }
  Write-Host "SERVICE_IB=reuse stamp=$expected path=$($paths.DbAbs)"
  return $paths
}

# --- main ---

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfgPath = Join-Path $ProjectRoot ".1c\project.json"
$localPath = Join-Path $ProjectRoot ".1c\project.local.json"
$cfg = Merge-Config (Read-JsonFile $cfgPath) (Read-JsonFile $localPath)
if ($null -eq $cfg) { throw "Missing .1c/project.json under $ProjectRoot" }

if ($ReuseOnly -and $RefreshServiceIb) {
  throw "-ReuseOnly cannot be combined with -RefreshServiceIb"
}
if ($ReuseOnly -and $Action -eq "ensure") {
  throw "-Action ensure prepares the IB; omit -ReuseOnly"
}

$state = Get-QvStatePaths $ProjectRoot
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Ensure-LogLine $state.Log "`n=== $ts action=$Action engine=Com reuseOnly=$ReuseOnly ==="

if ($Action -eq "stop") {
  Write-Host "OK action=stop (no-op; COM has no HTTP listener)"
  exit 0
}

$srcRel = Get-SrcRel $cfg
$srcAbs = Resolve-UnderRoot $ProjectRoot $srcRel

$paths = $null
if ($ReuseOnly) {
  $paths = Resolve-ServiceIbPathsReuseOnly $cfg $ProjectRoot $srcAbs
} else {
  # May run ibcmd create/import/apply (Cursor often prompts Allow)
  $ctx = Get-ServiceIbCfg $cfg $ProjectRoot $srcAbs `
    -ForceRefresh:$RefreshServiceIb `
    -AllowApply
  if (-not $ctx.Paths) {
    throw "Service IB disabled (ext.serviceIb.enabled=false). Enable it for query validate."
  }
  $paths = $ctx.Paths
}

if ($Action -eq "ensure") {
  Write-Host "OK action=ensure engine=Com db=$($paths.DbAbs)"
  exit 0
}

if ($Action -eq "health") {
  $c = Connect-ServiceIbCom $paths
  $null = $c
  Write-Host "OK action=health engine=Com"
  exit 0
}

$items = Get-BatchItems $BatchDir $QueryFiles $QueryFile $QueryText
$conn = Connect-ServiceIbCom $paths
$ok = 0
$fail = 0
foreach ($item in $items) {
  $result = Test-QueryViaCom $conn $item.Text
  if ($result.valid) {
    Write-Host "ITEM=$($item.Id) VALID=true"
    $ok++
  } else {
    Write-Host "ITEM=$($item.Id) VALID=false"
    Write-Host "ERROR=$($result.error)"
    $fail++
  }
}
$conn = $null
[GC]::Collect()
[GC]::WaitForPendingFinalizers()

Write-Host "SUMMARY ok=$ok fail=$fail"
if ($fail -eq 0) {
  if ($items.Count -eq 1) { Write-Host "VALID=true" }
  Write-Host "OK action=validate engine=Com"
  exit 0
}
if ($items.Count -eq 1) { Write-Host "VALID=false" }
Write-Host "FAIL action=validate engine=Com"
exit 1
