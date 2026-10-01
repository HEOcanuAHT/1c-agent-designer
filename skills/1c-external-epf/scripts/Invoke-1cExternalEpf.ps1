<#
.SYNOPSIS
  External data processors: scaffold / dump (.epf→XML) / pack (XML→.epf) / extract-from-config.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("scaffold", "dump", "pack", "extract-from-config")]
  [string]$Action,

  [string]$ProjectRoot = (Get-Location).Path,
  [string]$Name = "",
  [string]$Synonym = "",
  [string]$EpfPath = "",
  [string]$RootXml = "",

  [switch]$RefreshServiceIb,
  [switch]$SkipServiceIbPrepare
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillRoot = Split-Path -Parent $ScriptDir
$ExternalClassId = "c3831ec8-d8d5-4f93-8a22-f9bfae07327f"

. (Join-Path $ScriptDir "..\..\1c-runtime\scripts\Common-ServiceIb.ps1")

function Get-ExtDirRel($Cfg) {
  if ($Cfg.ext -and $Cfg.ext.dir) { return ([string]$Cfg.ext.dir -replace "\\", "/").TrimEnd("/") }
  return "ext"
}

function Get-ArtifactsRel($Cfg) {
  if ($Cfg.ext -and $Cfg.ext.artifacts) { return ([string]$Cfg.ext.artifacts -replace "\\", "/").TrimEnd("/") }
  return "artifacts/ext"
}

function New-Uuid {
  return [guid]::NewGuid().ToString()
}

function Assert-ProcessorName([string]$Value) {
  if (-not $Value) { throw "Name is required" }
  if ($Value -match '[\\/:*?"<>|.\s]') {
    throw "Invalid Name (no path chars/spaces): $Value"
  }
  # Unicode letter/digit identifiers (Latin + Cyrillic etc.)
  if ($Value -notmatch '^[\p{L}_][\p{L}\p{Nd}_]*$') {
    throw "Invalid Name (1C identifier expected): $Value"
  }
}

function Invoke-DesignerBatch {
  param(
    [string]$DesignerPath,
    $Cfg,
    [string]$ProjectRoot,
    [string[]]$ExtraArgs,
    [string]$LogName
  )
  Import-1cCredHelper
  $auth = Resolve-1cIbAuth -Cfg $Cfg -ProjectRoot $ProjectRoot
  $authArgs = Get-DesignerAuthArgs $auth
  $logDir = Join-Path $ProjectRoot ".1c"
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  $log = Join-Path $logDir $LogName
  if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

  $allArgs = @("DESIGNER") + (Get-IbArgs $Cfg $ProjectRoot) + $authArgs + @(
    "/DisableStartupDialogs", "/DisableStartupMessages", "/Out", $log
  ) + $ExtraArgs
  $argsForLog = $allArgs | ForEach-Object {
    if ($_ -eq "/P$($auth.Password)" -and $auth.Password) { "/P***" } elseif ($_ -match '^/P') { "/P***" } else { $_ }
  }
  Write-Host ">> $DesignerPath $($argsForLog -join ' ')"

  $argStr = ($allArgs | ForEach-Object {
    if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '""') + '"' } else { $_ }
  }) -join ' '
  $cmdInner = "`"$DesignerPath`" $argStr < NUL"
  $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$cmdInner`"" -WorkingDirectory $ProjectRoot -PassThru -Wait -NoNewWindow
  Write-Host "BATCH_EXIT=$($p.ExitCode) LOG=$log"
  if (Test-Path -LiteralPath $log) {
    Get-Content -LiteralPath $log -Encoding Default -EA SilentlyContinue | Select-Object -Last 40 | ForEach-Object { Write-Host $_ }
  }
  if ($p.ExitCode -ne 0) { throw "Designer batch exit $($p.ExitCode). See $log" }
}

function Copy-TemplateTree([string]$SrcDir, [string]$DstDir) {
  New-Item -ItemType Directory -Force -Path $DstDir | Out-Null
  Get-ChildItem -LiteralPath $SrcDir -Force | ForEach-Object {
    $target = Join-Path $DstDir $_.Name
    if ($_.PSIsContainer) {
      Copy-TemplateTree $_.FullName $target
    } else {
      Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
  }
}

function Expand-PlaceholdersInTree([string]$RootDir, [hashtable]$Map) {
  Get-ChildItem -LiteralPath $RootDir -Recurse -File | ForEach-Object {
    $text = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    $changed = $false
    foreach ($k in $Map.Keys) {
      if ($text.Contains($k)) {
        $text = $text.Replace($k, [string]$Map[$k])
        $changed = $true
      }
    }
    if ($changed) {
      $utf8Bom = New-Object System.Text.UTF8Encoding $true
      [System.IO.File]::WriteAllText($_.FullName, $text, $utf8Bom)
    }
  }
}

function Rename-TemplateNodes([string]$ExtAbs, [string]$Name) {
  $srcXml = Join-Path $ExtAbs "__NAME__.xml"
  $dstXml = Join-Path $ExtAbs "$Name.xml"
  if (-not (Test-Path -LiteralPath $srcXml)) { throw "Template root missing: $srcXml" }
  if (Test-Path -LiteralPath $dstXml) { throw "Already exists: $dstXml" }
  Move-Item -LiteralPath $srcXml -Destination $dstXml

  $srcDir = Join-Path $ExtAbs "__NAME__"
  $dstDir = Join-Path $ExtAbs $Name
  if (-not (Test-Path -LiteralPath $srcDir)) { throw "Template dir missing: $srcDir" }
  if (Test-Path -LiteralPath $dstDir) { throw "Already exists: $dstDir" }
  Move-Item -LiteralPath $srcDir -Destination $dstDir
  return $dstXml
}

function Fix-ProcessorRefsToExternal([string]$Text, [string]$Name) {
  $t = $Text
  # Collapse accidental double External prefix from naive Replace
  $t = $t.Replace("ExternalExternalDataProcessor", "ExternalDataProcessor")
  $esc = [regex]::Escape($Name)
  # Only rewrite bare DataProcessor* refs (not already ExternalDataProcessor*)
  $t = [regex]::Replace($t, '(?<!External)DataProcessorObject\.' + $esc, "ExternalDataProcessorObject.$Name")
  $t = [regex]::Replace($t, '(?<!External)DataProcessorManager\.' + $esc, "ExternalDataProcessorManager.$Name")
  $t = [regex]::Replace($t, '(?<!External)DataProcessor\.' + $esc + '\.', "ExternalDataProcessor.$Name.")
  $t = [regex]::Replace($t, '(?<!External)DataProcessor\.' + $esc + '(?=<)', "ExternalDataProcessor.$Name")
  return $t
}

function Convert-DataProcessorRootToExternal([string]$RootXmlPath, [string]$Name) {
  if (-not (Test-Path -LiteralPath $RootXmlPath)) { throw "Root XML not found: $RootXmlPath" }
  $text = Get-Content -LiteralPath $RootXmlPath -Raw -Encoding UTF8

  if ($text -notmatch '<DataProcessor[\s>]') {
    if ($text -match '<ExternalDataProcessor[\s>]') {
      Write-Host "Root already ExternalDataProcessor: $RootXmlPath"
      return
    }
    throw "Expected DataProcessor root in $RootXmlPath"
  }

  # Fresh UUIDs: same TypeId/uuid as config DataProcessor clashes with service IB import.
  $uuidRoot = New-Uuid
  $uuidContained = New-Uuid
  $uuidType = New-Uuid
  $uuidValue = New-Uuid

  $text = [regex]::Replace($text, '(?<=<DataProcessor uuid=")[^"]+(?=")', $uuidRoot)
  $text = [regex]::Replace(
    $text,
    '(?s)<xr:GeneratedType name="DataProcessorManager\.[^"]+" category="Manager">.*?</xr:GeneratedType>\s*',
    ''
  )
  $text = $text.Replace("DataProcessorObject.", "ExternalDataProcessorObject.")
  $text = [regex]::Replace($text, '<DataProcessor(\s|>)', '<ExternalDataProcessor$1')
  $text = $text.Replace("</DataProcessor>", "</ExternalDataProcessor>")
  $text = $text.Replace("DataProcessor.$Name.", "ExternalDataProcessor.$Name.")
  $text = [regex]::Replace($text, ">DataProcessor\.$([regex]::Escape($Name))<", ">ExternalDataProcessor.$Name<")
  $text = Fix-ProcessorRefsToExternal $text $Name

  # Drop properties not valid on ExternalDataProcessor
  foreach ($prop in @("UseStandardCommands", "IncludeHelpInContents", "ExtendedPresentation", "Explanation")) {
    $text = [regex]::Replace($text, "(?s)\s*<$prop>.*?</$prop>", "")
    $text = [regex]::Replace($text, "\s*<$prop\s*/>", "")
  }

  # ContainedObject + ClassId required for external; regenerate TypeId/ValueId
  if ($text -notmatch '<xr:ContainedObject>') {
    $contained = @"
			<xr:ContainedObject>
				<xr:ClassId>$ExternalClassId</xr:ClassId>
				<xr:ObjectId>$uuidContained</xr:ObjectId>
			</xr:ContainedObject>
"@
    $text = $text.Replace("<InternalInfo>", "<InternalInfo>`r`n$contained")
  } else {
    $text = [regex]::Replace($text, '(?<=<xr:ClassId>)[0-9a-fA-F-]{36}(?=</xr:ClassId>)', $ExternalClassId)
    $text = [regex]::Replace($text, '(?<=<xr:ObjectId>)[0-9a-fA-F-]{36}(?=</xr:ObjectId>)', $uuidContained)
  }
  $text = [regex]::Replace(
    $text,
    '(?s)(<xr:GeneratedType name="ExternalDataProcessorObject\.' + [regex]::Escape($Name) + '" category="Object">\s*<xr:TypeId>)[0-9a-fA-F-]{36}(</xr:TypeId>\s*<xr:ValueId>)[0-9a-fA-F-]{36}',
    "`${1}$uuidType`${2}$uuidValue"
  )

  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($RootXmlPath, $text, $utf8NoBom)
  Write-Host "Converted root to ExternalDataProcessor: $RootXmlPath (new uuids)"
}

function Find-RootXml([string]$ExtAbs, [string]$Name) {
  $candidate = Join-Path $ExtAbs "$Name.xml"
  if (Test-Path -LiteralPath $candidate) { return $candidate }
  throw "Root XML not found: $candidate"
}

# --- main ---

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfgPath = Join-Path $ProjectRoot ".1c\project.json"
$localPath = Join-Path $ProjectRoot ".1c\project.local.json"
$cfg = Merge-Config (Read-JsonFile $cfgPath) (Read-JsonFile $localPath)
if ($null -eq $cfg) { throw "Missing .1c/project.json under $ProjectRoot" }

$extRel = Get-ExtDirRel $cfg
$artRel = Get-ArtifactsRel $cfg
$srcRel = Get-SrcRel $cfg
$srcAbs = Resolve-UnderRoot $ProjectRoot $srcRel
$extAbs = Resolve-UnderRoot $ProjectRoot $extRel
$artAbs = Resolve-UnderRoot $ProjectRoot $artRel

$designerExplicit = ""
if ($cfg.designer) { $designerExplicit = [string]$cfg.designer }
$platformVersion = ""
if ($cfg.platformVersion) { $platformVersion = [string]$cfg.platformVersion }

Write-Host "action=$Action project=$ProjectRoot ext=$extRel"

switch ($Action) {
  "scaffold" {
    Assert-ProcessorName $Name
    if (-not $Synonym) { $Synonym = $Name }
    New-Item -ItemType Directory -Force -Path $extAbs | Out-Null
    $templateSrc = Join-Path $SkillRoot "templates\minimal"
    if (-not (Test-Path -LiteralPath $templateSrc)) { throw "Template missing: $templateSrc" }

    $staging = Join-Path $ProjectRoot (".1c\ext-scaffold-" + [guid]::NewGuid().ToString("N"))
    try {
      Copy-TemplateTree $templateSrc $staging
      $map = @{
        "__PROCESSOR_NAME__"   = $Name
        "__PROCESSOR_SYNONYM__" = $Synonym
        "__UUID_ROOT__"        = (New-Uuid)
        "__UUID_OBJECT__"      = (New-Uuid)
        "__UUID_TYPE__"        = (New-Uuid)
        "__UUID_VALUE__"       = (New-Uuid)
        "__UUID_FORM__"        = (New-Uuid)
      }
      Expand-PlaceholdersInTree $staging $map

      # Move into ext dir (rename __NAME__)
      Get-ChildItem -LiteralPath $staging -Force | ForEach-Object {
        $dest = Join-Path $extAbs $_.Name
        if (Test-Path -LiteralPath $dest) { throw "Target exists: $dest" }
        Move-Item -LiteralPath $_.FullName -Destination $dest
      }
      $rootXml = Rename-TemplateNodes $extAbs $Name
      Write-Host "SCAFFOLD_ROOT=$rootXml"
    }
    finally {
      if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
    }
  }

  "dump" {
    if (-not $EpfPath) { throw "-EpfPath required for dump" }
    if (-not (Test-Path -LiteralPath $EpfPath)) { throw "EPF not found: $EpfPath" }
    $epfAbs = (Resolve-Path -LiteralPath $EpfPath).Path
    New-Item -ItemType Directory -Force -Path $extAbs | Out-Null
    $epfCfg = Get-DesignerCfgForEpf $cfg $ProjectRoot $srcAbs `
      -ForceRefresh:$RefreshServiceIb -SkipPrepare:$SkipServiceIbPrepare
    $designerPath = Resolve-Designer $designerExplicit $platformVersion
    Invoke-DesignerBatch -DesignerPath $designerPath -Cfg $epfCfg -ProjectRoot $ProjectRoot -LogName "ext-dump.log" -ExtraArgs @(
      "/DumpExternalDataProcessorOrReportToFiles", $extAbs, $epfAbs, "-Format", "Hierarchical"
    )
    Write-Host "DUMP_DIR=$extAbs"
  }

  "pack" {
    if ($RootXml) {
      $rootAbs = if ([System.IO.Path]::IsPathRooted($RootXml)) { $RootXml } else { Join-Path $ProjectRoot $RootXml }
    } else {
      Assert-ProcessorName $Name
      $rootAbs = Find-RootXml $extAbs $Name
    }
    if (-not (Test-Path -LiteralPath $rootAbs)) { throw "Root XML not found: $rootAbs" }
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($rootAbs)
    New-Item -ItemType Directory -Force -Path $artAbs | Out-Null
    $outEpf = Join-Path $artAbs ($baseName + ".epf")
    $epfCfg = Get-DesignerCfgForEpf $cfg $ProjectRoot $srcAbs `
      -ForceRefresh:$RefreshServiceIb -SkipPrepare:$SkipServiceIbPrepare
    $designerPath = Resolve-Designer $designerExplicit $platformVersion
    Invoke-DesignerBatch -DesignerPath $designerPath -Cfg $epfCfg -ProjectRoot $ProjectRoot -LogName "ext-pack.log" -ExtraArgs @(
      "/LoadExternalDataProcessorOrReportFromFiles", $rootAbs, $outEpf
    )
    if (-not (Test-Path -LiteralPath $outEpf)) {
      # Platform may fix extension; accept .erf too
      $alt = [System.IO.Path]::ChangeExtension($outEpf, ".erf")
      if (Test-Path -LiteralPath $alt) { $outEpf = $alt }
      else { throw "Pack finished but output missing: $outEpf" }
    }
    Write-Host "EPF=$outEpf"
  }

  "extract-from-config" {
    Assert-ProcessorName $Name
    $dpRootXml = Join-Path $ProjectRoot "$srcRel\DataProcessors\$Name.xml"
    $dpDir = Join-Path $ProjectRoot "$srcRel\DataProcessors\$Name"
    if (-not (Test-Path -LiteralPath $dpRootXml)) { throw "Config processor not found: $dpRootXml" }

    New-Item -ItemType Directory -Force -Path $extAbs | Out-Null
    $dstXml = Join-Path $extAbs "$Name.xml"
    $dstDir = Join-Path $extAbs $Name
    if ((Test-Path -LiteralPath $dstXml) -or (Test-Path -LiteralPath $dstDir)) {
      throw "Target already exists under $extRel : $Name (remove or rename first)"
    }

    Copy-Item -LiteralPath $dpRootXml -Destination $dstXml -Force
    if (Test-Path -LiteralPath $dpDir) {
      Copy-Item -LiteralPath $dpDir -Destination $dstDir -Recurse -Force
    }

    Convert-DataProcessorRootToExternal -RootXmlPath $dstXml -Name $Name

    # Form.xml may reference cfg:DataProcessorObject.Name - fix in copied tree;
    # regenerate Form uuid (same uuid as config form clashes with service IB).
    if (Test-Path -LiteralPath $dstDir) {
      Get-ChildItem -LiteralPath $dstDir -Recurse -Include *.xml,*.bsl -File | ForEach-Object {
        $t = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
        $fixed = Fix-ProcessorRefsToExternal $t $Name
        if ($_.Name -eq "$Name.xml" -or ($_.Name -eq "Форма.xml" -and $_.Directory.Name -eq "Forms") -or $_.FullName -match '\\Forms\\[^\\]+\\.xml$') {
          if ($fixed -match '<Form uuid="') {
            $fixed = [regex]::Replace($fixed, '(?<=<Form uuid=")[^"]+(?=")', (New-Uuid))
          }
        }
        # Forms\<Name>.xml meta
        if ($_.Directory.Name -eq "Forms" -and $_.Extension -eq ".xml") {
          $fixed = [regex]::Replace($fixed, '(?<=<Form uuid=")[^"]+(?=")', (New-Uuid))
        }
        if ($fixed -ne $t) {
          $utf8NoBom = New-Object System.Text.UTF8Encoding $false
          [System.IO.File]::WriteAllText($_.FullName, $fixed, $utf8NoBom)
        }
      }
    }

    Write-Host "EXTRACT_ROOT=$dstXml"
    Write-Host "Source DataProcessors/$Name left unchanged (delete from config only on explicit request)."
  }
}

Write-Host "OK action=$Action"
exit 0
