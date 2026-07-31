<#
.SYNOPSIS
  Validate 1C query text via service IB (.1c/ib-ext) + QueryValidate extension HTTP API.

.DESCRIPTION
  Loads extension QueryValidate into service IB (with config apply — runtime needs DB cfg),
  starts 1cv8 ENTERPRISE with /HTTPPort, POSTs query to /hs/qv/validate.

  Extension sources: .cursor/skills/1c-external-cfe/examples/QueryValidate
  (optional override: src/_extensions/QueryValidate).

.PARAMETER Action
  validate — check query (default)
  ensure   — prepare IB + extension + HTTP listener
  stop     — stop HTTP listener started by ensure/validate
  health   — GET /hs/qv/health

.PARAMETER QueryText
  Query language text to validate.

.PARAMETER QueryFile
  UTF-8 file with query text.
#>
[CmdletBinding()]
param(
  [ValidateSet("validate", "ensure", "stop", "health")]
  [string]$Action = "validate",

  [string]$ProjectRoot = (Get-Location).Path,
  [string]$QueryText = "",
  [string]$QueryFile = "",
  [int]$HttpPort = 0,
  [switch]$RefreshServiceIb,
  [switch]$SkipStartHttp,
  [int]$ReadyTimeoutSec = 45
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CommonPath = Join-Path $ScriptDir "..\..\1c-external-epf\scripts\Common-ServiceIb.ps1"
. (Resolve-Path -LiteralPath $CommonPath).Path

$ExtName = "QueryValidate"
$ExtPrefix = "Qv_"
$RootUrl = "qv"

function Get-QvStatePaths([string]$ProjectRoot) {
  $dir = Join-Path $ProjectRoot ".1c"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  return @{
    Dir = $dir
    Pid = Join-Path $dir "qv-http.pid"
    Port = Join-Path $dir "qv-http.port"
    ExtStamp = Join-Path $dir "qv-ext.stamp"
    Log = Join-Path $dir "qv-validate.log"
  }
}

function Get-QvHttpPort($Cfg, [int]$Override) {
  if ($Override -gt 0) { return $Override }
  if ($Cfg.queryValidate -and $Cfg.queryValidate.httpPort) {
    return [int]$Cfg.queryValidate.httpPort
  }
  return 18088
}

function Find-QueryValidateXmlDir([string]$ProjectRoot) {
  $candidates = @(
    (Join-Path $ProjectRoot "src\_extensions\QueryValidate"),
    (Join-Path $ProjectRoot ".cursor\skills\1c-external-cfe\examples\QueryValidate")
  )
  foreach ($c in $candidates) {
    $cfg = Join-Path $c "Configuration.xml"
    if (Test-Path -LiteralPath $cfg) { return $c }
  }
  throw "QueryValidate XML not found. Expected examples under .cursor/skills/1c-external-cfe/examples/QueryValidate"
}

function Find-LanguageXml([string]$Dir) {
  $langDir = Join-Path $Dir "Languages"
  if (-not (Test-Path -LiteralPath $langDir)) { return $null }
  $hit = Get-ChildItem -LiteralPath $langDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($hit) { return $hit.FullName }
  return $null
}

function Fix-ExtensionLanguageUuid([string]$ExtDir, [string]$SrcAbs) {
  $langFile = Find-LanguageXml $ExtDir
  if (-not $langFile) { return }
  $baseLang = Find-LanguageXml $SrcAbs
  if (-not $baseLang) {
    Write-Warning "Base Languages/*.xml missing - ExtendedConfigurationObject may stay zeros until dump."
    return
  }
  $baseDoc = New-Object System.Xml.XmlDocument
  $baseDoc.PreserveWhitespace = $false
  $baseDoc.Load($baseLang)
  $langEl = $null
  foreach ($n in $baseDoc.DocumentElement.ChildNodes) {
    if ($n.NodeType -eq 'Element' -and $n.LocalName -eq 'Language') { $langEl = $n; break }
  }
  if (-not $langEl) { return }
  $baseUuid = $langEl.GetAttribute("uuid")
  if (-not $baseUuid -or $baseUuid -eq "00000000-0000-0000-0000-000000000000") { return }

  $text = Get-Content -LiteralPath $langFile -Raw -Encoding UTF8
  if ($text -match '<ExtendedConfigurationObject>00000000-0000-0000-0000-000000000000</ExtendedConfigurationObject>') {
    $text = $text.Replace(
      '<ExtendedConfigurationObject>00000000-0000-0000-0000-000000000000</ExtendedConfigurationObject>',
      "<ExtendedConfigurationObject>$baseUuid</ExtendedConfigurationObject>"
    )
    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    [IO.File]::WriteAllText($langFile, $text, $utf8Bom)
    Write-Host "LANGUAGE_UUID=$baseUuid"
  }
}

function Ensure-LogLine([string]$Log, [string]$Line) {
  Add-Content -LiteralPath $Log -Value $Line -Encoding UTF8
}

function Remove-ExtensionIfExists([string]$IbcmdPath, $Paths, [string]$Name, [string]$Log) {
  try {
    Invoke-IbcmdSimple $IbcmdPath (@(
      "infobase", "config", "extension", "delete"
    ) + (Get-IbcmdDbArgs $Paths) + @("--name=$Name")) $Log
  } catch {
    Write-Host "EXTENSION_DELETE=skip ($Name)"
  }
}

function Get-ExtSourcesStamp([string]$ExtDir) {
  $files = @(
    (Join-Path $ExtDir "Configuration.xml"),
    (Join-Path $ExtDir "HTTPServices\Qv_QueryValidate.xml"),
    (Join-Path $ExtDir "HTTPServices\Qv_QueryValidate\Ext\Module.bsl")
  )
  $parts = foreach ($f in $files) {
    if (Test-Path -LiteralPath $f) {
      $i = Get-Item -LiteralPath $f
      "{0}:{1}:{2}" -f $i.Name, $i.Length, $i.LastWriteTimeUtc.Ticks
    }
  }
  return ($parts -join "|")
}

function Install-QueryValidateExtension([string]$IbcmdPath, $Paths, [string]$ExtDir, [string]$Log, [string]$StampPath, [switch]$Force) {
  $stamp = Get-ExtSourcesStamp $ExtDir
  if (-not $Force -and (Test-Path -LiteralPath $StampPath)) {
    $prev = (Get-Content -LiteralPath $StampPath -Raw -Encoding UTF8).Trim()
    if ($prev -eq $stamp) {
      Write-Host "EXTENSION=cached $ExtName"
      return
    }
  }

  Remove-ExtensionIfExists $IbcmdPath $Paths $ExtName $Log

  Invoke-IbcmdSimple $IbcmdPath (@(
    "infobase", "config", "extension", "create"
  ) + (Get-IbcmdDbArgs $Paths) + @(
    "--name=$ExtName",
    "--name-prefix=$ExtPrefix",
    "--purpose=add-on"
  )) $Log

  Invoke-IbcmdSimple $IbcmdPath (@(
    "infobase", "config", "import"
  ) + (Get-IbcmdDbArgs $Paths) + @(
    "--extension=$ExtName",
    $ExtDir
  )) $Log

  # Runtime HTTP needs DB configuration (extension applied)
  Invoke-IbcmdSimple $IbcmdPath (@(
    "infobase", "config", "apply"
  ) + (Get-IbcmdDbArgs $Paths) + @(
    "--extension=$ExtName",
    "--force"
  )) $Log

  $utf8 = New-Object System.Text.UTF8Encoding $false
  [IO.File]::WriteAllText($StampPath, $stamp, $utf8)
  Write-Host "EXTENSION=installed $ExtName"
}

function Get-StoredHttpPort($State) {
  if (Test-Path -LiteralPath $State.Port) {
    $t = (Get-Content -LiteralPath $State.Port -Raw -Encoding UTF8).Trim()
    $p = 0
    if ([int]::TryParse($t, [ref]$p) -and $p -gt 0) { return $p }
  }
  return 0
}

function Get-StoredPid($State) {
  if (Test-Path -LiteralPath $State.Pid) {
    $t = (Get-Content -LiteralPath $State.Pid -Raw -Encoding UTF8).Trim()
    $p = 0
    if ([int]::TryParse($t, [ref]$p) -and $p -gt 0) { return $p }
  }
  return 0
}

function Stop-QvHttp($State) {
  $pidVal = Get-StoredPid $State
  if ($pidVal -gt 0) {
    try {
      $proc = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
      if ($proc) {
        Stop-Process -Id $pidVal -Force -ErrorAction SilentlyContinue
        Write-Host "HTTP_STOP pid=$pidVal"
      }
    } catch {}
  }
  Remove-Item -LiteralPath $State.Pid, $State.Port -Force -ErrorAction SilentlyContinue
}

function Test-QvHealth([int]$Port, [int]$TimeoutSec = 5) {
  $url = "http://127.0.0.1:$Port/hs/$RootUrl/health"
  try {
    $resp = Invoke-WebRequest -Uri $url -Method GET -UseBasicParsing -TimeoutSec $TimeoutSec
    return ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300)
  } catch {
    return $false
  }
}

function Start-QvHttp($Cfg, [string]$ProjectRoot, $Paths, [int]$Port, $State, [string]$Log) {
  if ((Get-StoredPid $State) -gt 0 -and (Test-QvHealth (Get-StoredHttpPort $State))) {
    Write-Host "HTTP_READY reuse port=$(Get-StoredHttpPort $State)"
    return (Get-StoredHttpPort $State)
  }
  Stop-QvHttp $State

  $designerExplicit = ""
  if ($Cfg.designer) { $designerExplicit = [string]$Cfg.designer }
  $platformVersion = if ($Cfg.platformVersion) { [string]$Cfg.platformVersion } else { "" }
  $designer = Resolve-Designer $designerExplicit $platformVersion

  $auth = Get-Auth $Cfg
  $authArgs = Get-DesignerAuthArgs $auth

  $argList = @(
    "ENTERPRISE",
    "/F`"$($Paths.DbAbs)`"",
    "/HTTPPort", "$Port",
    "/DisableStartupMessages"
  ) + $authArgs

  Write-Host ">> $designer $($argList -join ' ')"
  Ensure-LogLine $Log (">> start HTTPPort=$Port db=$($Paths.DbAbs)")

  $p = Start-Process -FilePath $designer -ArgumentList $argList -PassThru -WindowStyle Minimized
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [IO.File]::WriteAllText($State.Pid, "$($p.Id)", $utf8)
  [IO.File]::WriteAllText($State.Port, "$Port", $utf8)

  $deadline = (Get-Date).AddSeconds($ReadyTimeoutSec)
  while ((Get-Date) -lt $deadline) {
    if (Test-QvHealth $Port 2) {
      Write-Host "HTTP_READY port=$Port pid=$($p.Id)"
      return $Port
    }
    Start-Sleep -Seconds 1
    if ($p.HasExited) {
      throw "1cv8 exited early (code=$($p.ExitCode)). Check auth / apply / extension. Log: $Log"
    }
  }
  throw "HTTP health timeout after ${ReadyTimeoutSec}s: http://127.0.0.1:$Port/hs/$RootUrl/health"
}

function Invoke-ValidateRequest([int]$Port, [string]$Text) {
  $url = "http://127.0.0.1:$Port/hs/$RootUrl/validate"
  $bodyObj = @{ query = $Text }
  $json = $bodyObj | ConvertTo-Json -Compress
  $resp = Invoke-WebRequest -Uri $url -Method POST -Body ([Text.Encoding]::UTF8.GetBytes($json)) `
    -ContentType "application/json; charset=utf-8" -UseBasicParsing -TimeoutSec 60
  $parsed = $resp.Content | ConvertFrom-Json
  return $parsed
}

function Resolve-QueryText([string]$QueryText, [string]$QueryFile) {
  if ($QueryFile) {
    if (-not (Test-Path -LiteralPath $QueryFile)) { throw "QueryFile not found: $QueryFile" }
    return (Get-Content -LiteralPath $QueryFile -Raw -Encoding UTF8)
  }
  if ($QueryText) { return $QueryText }
  throw "Provide -QueryText or -QueryFile"
}

# --- main ---

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfgPath = Join-Path $ProjectRoot ".1c\project.json"
$localPath = Join-Path $ProjectRoot ".1c\project.local.json"
$cfg = Merge-Config (Read-JsonFile $cfgPath) (Read-JsonFile $localPath)
if ($null -eq $cfg) { throw "Missing .1c/project.json under $ProjectRoot" }

$state = Get-QvStatePaths $ProjectRoot
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Ensure-LogLine $state.Log "`n=== $ts action=$Action ==="

if ($Action -eq "stop") {
  Stop-QvHttp $state
  Write-Host "OK action=stop"
  exit 0
}

$srcRel = Get-SrcRel $cfg
$srcAbs = Resolve-UnderRoot $ProjectRoot $srcRel
$port = Get-QvHttpPort $cfg $HttpPort

# Runtime validate needs applied main config on service IB
$ctx = Get-ServiceIbCfg $cfg $ProjectRoot $srcAbs `
  -ForceRefresh:$RefreshServiceIb `
  -AllowApply

if ($RefreshServiceIb) {
  Remove-Item -LiteralPath $state.ExtStamp -Force -ErrorAction SilentlyContinue
}

if (-not $ctx.Paths) {
  throw "Service IB disabled (ext.serviceIb.enabled=false). Enable it or point to an IB with QueryValidate."
}

$extDir = Find-QueryValidateXmlDir $ProjectRoot
Fix-ExtensionLanguageUuid $extDir $srcAbs
Install-QueryValidateExtension $ctx.IbcmdPath $ctx.Paths $extDir $state.Log $state.ExtStamp `
  -Force:($RefreshServiceIb -or ($Action -eq "ensure"))

if ($Action -eq "ensure") {
  if (-not $SkipStartHttp) {
    $null = Start-QvHttp $cfg $ProjectRoot $ctx.Paths $port $state $state.Log
  }
  Write-Host "OK action=ensure ext=$extDir endpoint=http://127.0.0.1:$port/hs/$RootUrl/validate"
  exit 0
}

if (-not $SkipStartHttp) {
  $port = Start-QvHttp $cfg $ProjectRoot $ctx.Paths $port $state $state.Log
} else {
  $stored = Get-StoredHttpPort $state
  if ($stored -gt 0) { $port = $stored }
}

if ($Action -eq "health") {
  $ok = Test-QvHealth $port 10
  if (-not $ok) { throw "health failed: http://127.0.0.1:$port/hs/$RootUrl/health" }
  Write-Host "OK action=health port=$port"
  exit 0
}

# validate
$text = Resolve-QueryText $QueryText $QueryFile
$result = Invoke-ValidateRequest $port $text

$valid = [bool]$result.valid
$err = ""
if ($result.PSObject.Properties["error"]) { $err = [string]$result.error }

if ($valid) {
  Write-Host "VALID=true"
  Write-Host "OK action=validate"
  exit 0
}

Write-Host "VALID=false"
Write-Host "ERROR=$err"
Write-Host "FAIL action=validate"
exit 1
