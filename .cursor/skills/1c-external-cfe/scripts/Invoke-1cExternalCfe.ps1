<#
.SYNOPSIS
  Configuration extensions (.cfe): scaffold / dump (.cfe→XML) / pack (XML→.cfe).
  Reuses service IB (.1c/ib-ext) from Common-ServiceIb.ps1 (same as EPF).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("scaffold", "dump", "pack")]
  [string]$Action,

  [string]$ProjectRoot = (Get-Location).Path,
  [string]$Name = "",
  [string]$Synonym = "",
  [string]$Prefix = "",
  [ValidateSet("Customization", "AddOn", "Patch", "customization", "add-on", "patch")]
  [string]$Purpose = "Customization",
  [string]$CfePath = "",
  [string]$XmlDir = "",

  [switch]$RefreshServiceIb,
  [switch]$SkipServiceIbPrepare
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CommonPath = Join-Path $ScriptDir "..\..\1c-external-epf\scripts\Common-ServiceIb.ps1"
. (Resolve-Path -LiteralPath $CommonPath).Path

function Get-CfeDirRel($Cfg) {
  if ($Cfg.cfe -and $Cfg.cfe.dir) { return ([string]$Cfg.cfe.dir -replace "\\", "/").TrimEnd("/") }
  return "src/_extensions"
}

function Get-CfeArtifactsRel($Cfg) {
  if ($Cfg.cfe -and $Cfg.cfe.artifacts) { return ([string]$Cfg.cfe.artifacts -replace "\\", "/").TrimEnd("/") }
  return "artifacts/cfe"
}

function Assert-ExtName([string]$Value) {
  if (-not $Value) { throw "Name is required" }
  if ($Value -match '[\\/:*?"<>|.\s]') {
    throw "Invalid Name (no path chars/spaces): $Value"
  }
  if ($Value -notmatch '^[\p{L}_][\p{L}\p{Nd}_]*$') {
    throw "Invalid Name (1C identifier expected): $Value"
  }
}

function ConvertTo-IbcmdPurpose([string]$Value) {
  switch -Regex ($Value) {
    '^(?i)add[-_]?on$' { return "add-on" }
    '^(?i)patch$' { return "patch" }
    default { return "customization" }
  }
}

function ConvertTo-NStrSynonym([string]$Text) {
  $escaped = $Text -replace '"', '""'
  return "NStr(`"ru='$escaped'`")"
}

function Get-ExtensionNameFromXml([string]$ConfigXmlPath) {
  if (-not (Test-Path -LiteralPath $ConfigXmlPath)) { return $null }
  $text = Get-Content -LiteralPath $ConfigXmlPath -Raw -Encoding UTF8
  $m = [regex]::Match($text, '(?s)<Properties>.*?<Name>([^<]+)</Name>')
  if ($m.Success) { return $m.Groups[1].Value.Trim() }
  return $null
}

function Get-ExtensionPrefixFromXml([string]$ConfigXmlPath) {
  if (-not (Test-Path -LiteralPath $ConfigXmlPath)) { return $null }
  $text = Get-Content -LiteralPath $ConfigXmlPath -Raw -Encoding UTF8
  $m = [regex]::Match($text, '<NamePrefix>([^<]*)</NamePrefix>')
  if ($m.Success) { return $m.Groups[1].Value.Trim() }
  return $null
}

function Find-ExtensionXmlDir([string]$CfeRootAbs, [string]$Name) {
  $candidate = Join-Path $CfeRootAbs $Name
  $cfg = Join-Path $candidate "Configuration.xml"
  if (Test-Path -LiteralPath $cfg) { return $candidate }
  throw "Extension XML not found: $cfg (expected src/_extensions/<Name>/Configuration.xml)"
}

function Get-ServiceContext($Cfg, [string]$ProjectRoot, [string]$SrcAbs) {
  $ctx = Get-ServiceIbCfg $Cfg $ProjectRoot $SrcAbs $RefreshServiceIb $SkipServiceIbPrepare
  if (-not $ctx.Paths) {
    # Skip prepare → use project file IB path if type=file
    $paths = Get-ServiceIbPaths $Cfg $ProjectRoot
    if ($Cfg.infobase -and $Cfg.infobase.type -eq "file" -and $Cfg.infobase.path) {
      $p = [string]$Cfg.infobase.path
      $paths.DbAbs = if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $ProjectRoot ($p -replace "/", "\") }
      $paths.DbRel = ($p -replace "\\", "/")
    }
    $ibcmdExplicit = ""
    if ($Cfg.ibcmd -and $Cfg.ibcmd.path) { $ibcmdExplicit = [string]$Cfg.ibcmd.path }
    $platformVersion = if ($Cfg.platformVersion) { [string]$Cfg.platformVersion } else { "" }
    $ctx.Paths = $paths
    $ctx.IbcmdPath = Resolve-Ibcmd $ibcmdExplicit $platformVersion
  }
  return $ctx
}

function Remove-ExtensionIfExists([string]$IbcmdPath, $Paths, [string]$Name, [string]$Log) {
  try {
    Invoke-IbcmdSimple $IbcmdPath (@(
      "infobase", "config", "extension", "delete"
    ) + (Get-IbcmdDbArgs $Paths) + @("--name=$Name")) $Log
  } catch {
    # missing extension is OK
    Write-Host "EXTENSION_DELETE=skip ($Name): $($_.Exception.Message)"
  }
}

function New-EmptyExtension([string]$IbcmdPath, $Paths, [string]$Name, [string]$NamePrefix, [string]$PurposeIbcmd, [string]$SynonymNStr, [string]$Log) {
  $args = @(
    "infobase", "config", "extension", "create"
  ) + (Get-IbcmdDbArgs $Paths) + @(
    "--name=$Name",
    "--name-prefix=$NamePrefix",
    "--purpose=$PurposeIbcmd"
  )
  if ($SynonymNStr) { $args += "--synonym=$SynonymNStr" }
  Invoke-IbcmdSimple $IbcmdPath $args $Log
}

function Ensure-Log([string]$ProjectRoot, [string]$Name) {
  $logDir = Join-Path $ProjectRoot ".1c"
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  $log = Join-Path $logDir $Name
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content -LiteralPath $log -Value "`n=== $ts ===" -Encoding UTF8
  return $log
}

# --- main ---

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfgPath = Join-Path $ProjectRoot ".1c\project.json"
$localPath = Join-Path $ProjectRoot ".1c\project.local.json"
$cfg = Merge-Config (Read-JsonFile $cfgPath) (Read-JsonFile $localPath)
if ($null -eq $cfg) { throw "Missing .1c/project.json under $ProjectRoot" }

$cfeRel = Get-CfeDirRel $cfg
$artRel = Get-CfeArtifactsRel $cfg
$srcRel = Get-SrcRel $cfg
$srcAbs = Resolve-UnderRoot $ProjectRoot $srcRel
$cfeRootAbs = Resolve-UnderRoot $ProjectRoot $cfeRel
$artAbs = Resolve-UnderRoot $ProjectRoot $artRel

Write-Host "action=$Action project=$ProjectRoot cfe=$cfeRel"

switch ($Action) {
  "scaffold" {
    Assert-ExtName $Name
    if (-not $Synonym) { $Synonym = $Name }
    if (-not $Prefix) { $Prefix = "${Name}_" }
    if ($Prefix -notmatch '^[\p{L}_][\p{L}\p{Nd}_]*$') {
      throw "Invalid Prefix (1C identifier expected): $Prefix"
    }

    $outDir = Join-Path $cfeRootAbs $Name
    if (Test-Path -LiteralPath $outDir) {
      throw "Already exists: $outDir (remove or rename first)"
    }

    $ctx = Get-ServiceContext $cfg $ProjectRoot $srcAbs
    $log = Ensure-Log $ProjectRoot "cfe-scaffold.log"
    $purposeIb = ConvertTo-IbcmdPurpose $Purpose
    $synNStr = ConvertTo-NStrSynonym $Synonym

    Remove-ExtensionIfExists $ctx.IbcmdPath $ctx.Paths $Name $log
    New-EmptyExtension $ctx.IbcmdPath $ctx.Paths $Name $Prefix $purposeIb $synNStr $log

    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    Invoke-IbcmdSimple $ctx.IbcmdPath (@(
      "infobase", "config", "export"
    ) + (Get-IbcmdDbArgs $ctx.Paths) + @(
      "--extension=$Name",
      "--force",
      $outDir
    )) $log

    $cfgXml = Join-Path $outDir "Configuration.xml"
    if (-not (Test-Path -LiteralPath $cfgXml)) {
      throw "Scaffold export finished but Configuration.xml missing: $cfgXml"
    }
    Write-Host "SCAFFOLD_DIR=$outDir"
  }

  "dump" {
    if (-not $CfePath) { throw "-CfePath required for dump" }
    if (-not (Test-Path -LiteralPath $CfePath)) { throw "CFE not found: $CfePath" }
    $cfeAbs = (Resolve-Path -LiteralPath $CfePath).Path
    Assert-ExtName $Name

    $outDir = if ($XmlDir) {
      if ([IO.Path]::IsPathRooted($XmlDir)) { $XmlDir } else { Join-Path $ProjectRoot $XmlDir }
    } else {
      Join-Path $cfeRootAbs $Name
    }

    $ctx = Get-ServiceContext $cfg $ProjectRoot $srcAbs
    $log = Ensure-Log $ProjectRoot "cfe-dump.log"

    if (-not $Prefix) { $Prefix = "${Name}_" }
    $purposeIb = ConvertTo-IbcmdPurpose $Purpose

    Remove-ExtensionIfExists $ctx.IbcmdPath $ctx.Paths $Name $log
    New-EmptyExtension $ctx.IbcmdPath $ctx.Paths $Name $Prefix $purposeIb "" $log

    Invoke-IbcmdSimple $ctx.IbcmdPath (@(
      "infobase", "config", "load"
    ) + (Get-IbcmdDbArgs $ctx.Paths) + @(
      "--extension=$Name",
      "--force",
      $cfeAbs
    )) $log

    if (Test-Path -LiteralPath $outDir) {
      Remove-Item -LiteralPath $outDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    Invoke-IbcmdSimple $ctx.IbcmdPath (@(
      "infobase", "config", "export"
    ) + (Get-IbcmdDbArgs $ctx.Paths) + @(
      "--extension=$Name",
      "--force",
      $outDir
    )) $log

    Write-Host "DUMP_DIR=$outDir"
  }

  "pack" {
    $extDir = if ($XmlDir) {
      if ([IO.Path]::IsPathRooted($XmlDir)) { $XmlDir } else { Join-Path $ProjectRoot $XmlDir }
    } else {
      Assert-ExtName $Name
      Find-ExtensionXmlDir $cfeRootAbs $Name
    }

    $cfgXml = Join-Path $extDir "Configuration.xml"
    if (-not (Test-Path -LiteralPath $cfgXml)) { throw "Configuration.xml not found: $cfgXml" }

    $extName = Get-ExtensionNameFromXml $cfgXml
    if (-not $extName) { throw "Cannot read <Name> from $cfgXml" }
    if ($Name -and ($Name -ne $extName)) {
      throw "Name mismatch: -Name=$Name but Configuration.xml Name=$extName"
    }
    $Name = $extName
    Assert-ExtName $Name

    $xmlPrefix = Get-ExtensionPrefixFromXml $cfgXml
    if (-not $Prefix) {
      $Prefix = if ($xmlPrefix) { $xmlPrefix } else { "${Name}_" }
    }

    New-Item -ItemType Directory -Force -Path $artAbs | Out-Null
    $outCfe = Join-Path $artAbs ($Name + ".cfe")

    $ctx = Get-ServiceContext $cfg $ProjectRoot $srcAbs
    $log = Ensure-Log $ProjectRoot "cfe-pack.log"
    $purposeIb = ConvertTo-IbcmdPurpose $Purpose

    Remove-ExtensionIfExists $ctx.IbcmdPath $ctx.Paths $Name $log
    New-EmptyExtension $ctx.IbcmdPath $ctx.Paths $Name $Prefix $purposeIb "" $log

    Invoke-IbcmdSimple $ctx.IbcmdPath (@(
      "infobase", "config", "import"
    ) + (Get-IbcmdDbArgs $ctx.Paths) + @(
      "--extension=$Name",
      $extDir
    )) $log

    if (Test-Path -LiteralPath $outCfe) { Remove-Item -LiteralPath $outCfe -Force }

    Invoke-IbcmdSimple $ctx.IbcmdPath (@(
      "infobase", "config", "save"
    ) + (Get-IbcmdDbArgs $ctx.Paths) + @(
      "--extension=$Name",
      $outCfe
    )) $log

    if (-not (Test-Path -LiteralPath $outCfe)) {
      throw "Pack finished but output missing: $outCfe"
    }
    Write-Host "CFE=$outCfe"
  }
}

Write-Host "OK action=$Action"
exit 0
