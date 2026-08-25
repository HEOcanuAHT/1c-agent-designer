<#
.SYNOPSIS
  Configuration extensions (.cfe): scaffold / dump (.cfe->XML) / pack (XML->.cfe).
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
  [switch]$SkipServiceIbPrepare,
  # When main config CompatibilityMode is older than platform (e.g. 8.3.10 on 8.3.23),
  # extension create fails after import-without-apply. One-shot apply on .1c/ib-ext only.
  [switch]$AllowServiceIbApplyOnCompatMismatch
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CommonPath = Join-Path $ScriptDir "..\..\1c-external-epf\scripts\Common-ServiceIb.ps1"
. (Resolve-Path -LiteralPath $CommonPath).Path

function Get-CfeDirRel($Cfg) {
  if ($Cfg.cfe -and $Cfg.cfe.dir) { return ([string]$Cfg.cfe.dir -replace "\\", "/").TrimEnd("/") }
  return "cfe"
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

function Test-AsciiIdentifier([string]$Value) {
  return ($Value -match '^[A-Za-z_][A-Za-z0-9_]*$')
}

function Warn-PreferAsciiName([string]$Label, [string]$Value) {
  if (-not (Test-AsciiIdentifier $Value)) {
    Write-Warning ("{0}='{1}' contains non-ASCII. ibcmd via cmd.exe may corrupt Cyrillic. Prefer Latin Name/Prefix (e.g. FixDbmsType / Fix_)." -f $Label, $Value)
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

function Set-ExtensionNamePrefix([string]$ConfigXmlPath, [string]$Prefix) {
  if (-not (Test-Path -LiteralPath $ConfigXmlPath)) { return }
  $text = Get-Content -LiteralPath $ConfigXmlPath -Raw -Encoding UTF8
  if ($text -match '<NamePrefix/>') {
    $text = $text.Replace('<NamePrefix/>', "<NamePrefix>$Prefix</NamePrefix>")
  } elseif ($text -match '<NamePrefix></NamePrefix>') {
    $text = $text.Replace('<NamePrefix></NamePrefix>', "<NamePrefix>$Prefix</NamePrefix>")
  } elseif ($text -match '<NamePrefix>[^<]*</NamePrefix>') {
    $cur = Get-ExtensionPrefixFromXml $ConfigXmlPath
    if (-not $cur) {
      $text = [regex]::Replace($text, '<NamePrefix>[^<]*</NamePrefix>', "<NamePrefix>$Prefix</NamePrefix>")
    } else {
      return
    }
  } else {
    return
  }
  $utf8Bom = New-Object System.Text.UTF8Encoding $true
  [IO.File]::WriteAllText($ConfigXmlPath, $text, $utf8Bom)
  Write-Host "NAME_PREFIX=$Prefix ($ConfigXmlPath)"
}

function Find-ExtensionXmlDir([string]$CfeRootAbs, [string]$Name) {
  $candidate = Join-Path $CfeRootAbs $Name
  $cfg = Join-Path $candidate "Configuration.xml"
  if (Test-Path -LiteralPath $cfg) { return $candidate }
  throw "Extension XML not found: $cfg (expected cfe/<Name>/Configuration.xml or cfe.dir)"
}

function Get-ServiceContext($Cfg, [string]$ProjectRoot, [string]$SrcAbs) {
  $ctx = Get-ServiceIbCfg $Cfg $ProjectRoot $SrcAbs `
    -ForceRefresh:$RefreshServiceIb `
    -SkipPrepare:$SkipServiceIbPrepare `
    -AllowApply:$AllowServiceIbApplyOnCompatMismatch
  if (-not $ctx.Paths) {
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

function Test-CompatMismatchMessage([string]$Message) {
  if (-not $Message) { return $false }
  if ($Message -match 'CompatibilityMode|compatibility') { return $true }
  # Avoid Cyrillic literals in .ps1 (PS 5.1 without BOM breaks parse) - build from codepoints
  $compatRu = -join ([char[]](0x0441,0x043E,0x0432,0x043C,0x0435,0x0441,0x0442,0x0438,0x043C,0x043E,0x0441,0x0442,0x0438))
  $mismatchRu = -join ([char[]](0x043D,0x0435,0x0020,0x0441,0x043E,0x043E,0x0442,0x0432,0x0435,0x0442,0x0441,0x0442,0x0432,0x0443,0x0435,0x0442))
  return ($Message.IndexOf($compatRu, [StringComparison]::Ordinal) -ge 0) -or
    ($Message.IndexOf($mismatchRu, [StringComparison]::Ordinal) -ge 0)
}

function Invoke-ExtensionCreateWithCompatHint {
  param(
    [string]$IbcmdPath,
    $Paths,
    [string]$Name,
    [string]$NamePrefix,
    [string]$PurposeIbcmd,
    [string]$SynonymNStr,
    [string]$Log,
    $Cfg,
    [string]$ProjectRoot,
    [string]$SrcAbs
  )
  try {
    New-EmptyExtension $IbcmdPath $Paths $Name $NamePrefix $PurposeIbcmd $SynonymNStr $Log
  } catch {
    $msg = $_.Exception.Message
    if ((Test-CompatMismatchMessage $msg) -and -not $AllowServiceIbApplyOnCompatMismatch) {
      throw ("ibcmd extension create failed (likely CompatibilityMode vs platform after import without apply). " +
        "Retry with -AllowServiceIbApplyOnCompatMismatch -RefreshServiceIb (applies ONLY on .1c/ib-ext, never project IB). " +
        "See $Log. Inner: $msg")
    }
    if ((Test-CompatMismatchMessage $msg) -and $AllowServiceIbApplyOnCompatMismatch) {
      Write-Warning "Compat mismatch on extension create - rebuilding service IB with apply..."
      $ctx2 = Get-ServiceIbCfg $Cfg $ProjectRoot $SrcAbs -ForceRefresh -AllowApply
      New-EmptyExtension $ctx2.IbcmdPath $ctx2.Paths $Name $NamePrefix $PurposeIbcmd $SynonymNStr $Log
      return $ctx2
    }
    throw
  }
  return $null
}

function Remove-ExtensionIfExists([string]$IbcmdPath, $Paths, [string]$Name, [string]$Log) {
  try {
    Invoke-IbcmdSimple $IbcmdPath (@(
      "infobase", "config", "extension", "delete"
    ) + (Get-IbcmdDbArgs $Paths) + @("--name=$Name")) $Log
  } catch {
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

if ($AllowServiceIbApplyOnCompatMismatch) {
  Write-Warning "AllowServiceIbApplyOnCompatMismatch: config apply will run on SERVICE IB (.1c/ib-ext) only - never on project/combat IB."
}

Write-Host "action=$Action project=$ProjectRoot cfe=$cfeRel"

switch ($Action) {
  "scaffold" {
    Assert-ExtName $Name
    Warn-PreferAsciiName "Name" $Name
    if (-not $Synonym) { $Synonym = $Name }
    if (-not $Prefix) { $Prefix = "${Name}_" }
    if ($Prefix -notmatch '^[\p{L}_][\p{L}\p{Nd}_]*$') {
      throw "Invalid Prefix (1C identifier expected): $Prefix"
    }
    Warn-PreferAsciiName "Prefix" $Prefix

    $outDir = Join-Path $cfeRootAbs $Name
    if (Test-Path -LiteralPath $outDir) {
      throw "Already exists: $outDir (remove or rename first)"
    }

    $ctx = Get-ServiceContext $cfg $ProjectRoot $srcAbs
    $log = Ensure-Log $ProjectRoot "cfe-scaffold.log"
    $purposeIb = ConvertTo-IbcmdPurpose $Purpose
    $synNStr = ConvertTo-NStrSynonym $Synonym

    Remove-ExtensionIfExists $ctx.IbcmdPath $ctx.Paths $Name $log
    $ctxNew = Invoke-ExtensionCreateWithCompatHint $ctx.IbcmdPath $ctx.Paths $Name $Prefix $purposeIb $synNStr $log $cfg $ProjectRoot $srcAbs
    if ($ctxNew) { $ctx = $ctxNew }

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
    Set-ExtensionNamePrefix $cfgXml $Prefix
    Write-Host "SCAFFOLD_DIR=$outDir"
  }

  "dump" {
    if (-not $CfePath) { throw "-CfePath required for dump" }
    if (-not (Test-Path -LiteralPath $CfePath)) { throw "CFE not found: $CfePath" }
    $cfeAbs = (Resolve-Path -LiteralPath $CfePath).Path
    Assert-ExtName $Name
    Warn-PreferAsciiName "Name" $Name

    $outDir = if ($XmlDir) {
      if ([IO.Path]::IsPathRooted($XmlDir)) { $XmlDir } else { Join-Path $ProjectRoot $XmlDir }
    } else {
      Join-Path $cfeRootAbs $Name
    }

    $ctx = Get-ServiceContext $cfg $ProjectRoot $srcAbs
    $log = Ensure-Log $ProjectRoot "cfe-dump.log"

    if (-not $Prefix) { $Prefix = "${Name}_" }
    Warn-PreferAsciiName "Prefix" $Prefix
    $purposeIb = ConvertTo-IbcmdPurpose $Purpose

    Remove-ExtensionIfExists $ctx.IbcmdPath $ctx.Paths $Name $log
    $ctxNew = Invoke-ExtensionCreateWithCompatHint $ctx.IbcmdPath $ctx.Paths $Name $Prefix $purposeIb "" $log $cfg $ProjectRoot $srcAbs
    if ($ctxNew) { $ctx = $ctxNew }

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
    Warn-PreferAsciiName "Name" $Name

    $xmlPrefix = Get-ExtensionPrefixFromXml $cfgXml
    if (-not $Prefix) {
      $Prefix = if ($xmlPrefix) { $xmlPrefix } else { "${Name}_" }
    }
    if (-not $xmlPrefix) {
      Set-ExtensionNamePrefix $cfgXml $Prefix
    }
    Warn-PreferAsciiName "Prefix" $Prefix

    New-Item -ItemType Directory -Force -Path $artAbs | Out-Null
    $outCfe = Join-Path $artAbs ($Name + ".cfe")

    $ctx = Get-ServiceContext $cfg $ProjectRoot $srcAbs
    $log = Ensure-Log $ProjectRoot "cfe-pack.log"
    $purposeIb = ConvertTo-IbcmdPurpose $Purpose

    try {
      Remove-ExtensionIfExists $ctx.IbcmdPath $ctx.Paths $Name $log
      $ctxNew = Invoke-ExtensionCreateWithCompatHint $ctx.IbcmdPath $ctx.Paths $Name $Prefix $purposeIb "" $log $cfg $ProjectRoot $srcAbs
      if ($ctxNew) { $ctx = $ctxNew }

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
    } catch {
      throw ("CFE pack failed. Inspect UTF-8 log: $log. Adopted XML checklist: skill 1c-external-cfe / reference-adopted.md. Inner: $($_.Exception.Message)")
    }

    if (-not (Test-Path -LiteralPath $outCfe)) {
      throw "Pack finished but output missing: $outCfe (see $log)"
    }
    Write-Host "CFE=$outCfe"
  }
}

Write-Host "OK action=$Action"
exit 0
