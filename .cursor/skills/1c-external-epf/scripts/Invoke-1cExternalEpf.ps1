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
  [string]$RootXml = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillRoot = Split-Path -Parent $ScriptDir
$ExternalClassId = "c3831ec8-d8d5-4f93-8a22-f9bfae07327f"

function Read-JsonFile([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Merge-Config($Base, $Overlay) {
  if ($null -eq $Overlay) { return $Base }
  if ($null -eq $Base) { return $Overlay }
  $json = $Base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
  foreach ($p in $Overlay.PSObject.Properties) {
    $name = $p.Name
    $val = $p.Value
    if ($null -ne $val -and ($val -is [System.Management.Automation.PSCustomObject]) -and
        $json.PSObject.Properties[$name] -and ($json.$name -is [System.Management.Automation.PSCustomObject])) {
      $json.$name = Merge-Config $json.$name $val
    } else {
      $json | Add-Member -NotePropertyName $name -NotePropertyValue $val -Force
    }
  }
  return $json
}

function Resolve-Designer([string]$Explicit, [string]$PlatformVersion) {
  if ($env:1C_DESIGNER -and (Test-Path -LiteralPath $env:1C_DESIGNER)) { return $env:1C_DESIGNER }
  if ($Explicit -and (Test-Path -LiteralPath $Explicit)) { return $Explicit }
  if ($PlatformVersion) {
    foreach ($root in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)})) {
      if (-not $root) { continue }
      $candidate = Join-Path $root "1cv8\$PlatformVersion\bin\1cv8.exe"
      if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
  }
  foreach ($root in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)})) {
    if (-not $root) { continue }
    $base = Join-Path $root "1cv8"
    if (-not (Test-Path -LiteralPath $base)) { continue }
    $found = Get-ChildItem $base -Recurse -Filter "1cv8.exe" -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '\\bin\\1cv8\.exe$' } |
      Sort-Object FullName -Descending |
      Select-Object -First 1 -ExpandProperty FullName
    if ($found) { return $found }
  }
  throw "1cv8.exe not found."
}

function Get-Auth($Cfg) {
  $user = $env:1C_IB_USER
  $pwd = $env:1C_IB_PASSWORD
  if ($Cfg.auth -and $Cfg.auth.user) { $user = [string]$Cfg.auth.user }
  if ($Cfg.auth -and $null -ne $Cfg.auth.password) { $pwd = [string]$Cfg.auth.password }
  if (-not $user) { throw "Need auth.user in project.local.json or 1C_IB_USER." }
  if ($null -eq $pwd) { $pwd = "" }
  return @{ User = $user; Password = $pwd }
}

function Get-IbArgs($Cfg, [string]$ProjectRoot) {
  $type = "file"
  if ($Cfg.infobase -and $Cfg.infobase.type) { $type = [string]$Cfg.infobase.type }
  if ($type -eq "server") {
    if (-not $Cfg.infobase.server) { throw "infobase.server required" }
    return @("/S", ([string]$Cfg.infobase.server))
  }
  if ($type -eq "ibname") {
    $ibName = $null
    if ($Cfg.infobase.name) { $ibName = [string]$Cfg.infobase.name }
    elseif ($Cfg.infobase.path) { $ibName = [string]$Cfg.infobase.path }
    if (-not $ibName) { throw "infobase.name required for type=ibname" }
    return @("/IBName", $ibName)
  }
  $p = if ($env:1C_IB_PATH) { $env:1C_IB_PATH }
    elseif ($Cfg.infobase -and $Cfg.infobase.path) { [string]$Cfg.infobase.path }
    else { ".1c/ib-dev" }
  $dbPath = if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $ProjectRoot $p }
  return @("/F", $dbPath)
}

function Get-ExtDirRel($Cfg) {
  if ($Cfg.ext -and $Cfg.ext.dir) { return ([string]$Cfg.ext.dir -replace "\\", "/").TrimEnd("/") }
  return "src/_extDataProcessors"
}

function Get-ArtifactsRel($Cfg) {
  if ($Cfg.ext -and $Cfg.ext.artifacts) { return ([string]$Cfg.ext.artifacts -replace "\\", "/").TrimEnd("/") }
  return "artifacts/ext"
}

function Get-SrcRel($Cfg) {
  if ($Cfg.src) { return ([string]$Cfg.src -replace "\\", "/").TrimEnd("/") }
  return "src"
}

function Resolve-UnderRoot([string]$ProjectRoot, [string]$RelOrAbs) {
  if ([System.IO.Path]::IsPathRooted($RelOrAbs)) { return $RelOrAbs }
  return (Join-Path $ProjectRoot ($RelOrAbs -replace "/", "\"))
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
  $auth = Get-Auth $Cfg
  $logDir = Join-Path $ProjectRoot ".1c"
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  $log = Join-Path $logDir $LogName
  if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

  $argsForLog = @("DESIGNER") + (Get-IbArgs $Cfg $ProjectRoot) + @(
    "/N$($auth.User)", "/P***", "/DisableStartupDialogs", "/DisableStartupMessages", "/Out", $log
  ) + $ExtraArgs
  Write-Host ">> $DesignerPath $($argsForLog -join ' ')"
  $args = @("DESIGNER") + (Get-IbArgs $Cfg $ProjectRoot) + @(
    "/N$($auth.User)", "/P$($auth.Password)", "/DisableStartupDialogs", "/DisableStartupMessages", "/Out", $log
  ) + $ExtraArgs
  $p = Start-Process -FilePath $DesignerPath -ArgumentList $args -WorkingDirectory $ProjectRoot -PassThru -Wait -NoNewWindow
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

  # Order matters: longer identifiers first.
  $text = $text.Replace("DataProcessorObject.", "ExternalDataProcessorObject.")
  $text = [regex]::Replace($text, '<DataProcessor(\s|>)', '<ExternalDataProcessor$1')
  $text = $text.Replace("</DataProcessor>", "</ExternalDataProcessor>")
  $text = [regex]::Replace(
    $text,
    '(?<=<xr:ClassId>)[0-9a-fA-F-]{36}(?=</xr:ClassId>)',
    $ExternalClassId
  )
  # DefaultForm / paths: DataProcessor.Name → ExternalDataProcessor.Name (not TabularSection*)
  $text = $text.Replace("DataProcessor.$Name.", "ExternalDataProcessor.$Name.")
  $text = [regex]::Replace($text, ">DataProcessor\.$([regex]::Escape($Name))<", ">ExternalDataProcessor.$Name<")

  $utf8Bom = New-Object System.Text.UTF8Encoding $true
  [System.IO.File]::WriteAllText($RootXmlPath, $text, $utf8Bom)
  Write-Host "Converted root to ExternalDataProcessor: $RootXmlPath"
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
    $designerPath = Resolve-Designer $designerExplicit $platformVersion
    Invoke-DesignerBatch -DesignerPath $designerPath -Cfg $cfg -ProjectRoot $ProjectRoot -LogName "ext-dump.log" -ExtraArgs @(
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
    $designerPath = Resolve-Designer $designerExplicit $platformVersion
    Invoke-DesignerBatch -DesignerPath $designerPath -Cfg $cfg -ProjectRoot $ProjectRoot -LogName "ext-pack.log" -ExtraArgs @(
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

    # Form.xml may reference cfg:DataProcessorObject.Name — fix in copied tree
    if (Test-Path -LiteralPath $dstDir) {
      Get-ChildItem -LiteralPath $dstDir -Recurse -Include *.xml,*.bsl -File | ForEach-Object {
        $t = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
        $orig = $t
        $t = $t.Replace("cfg:DataProcessorObject.$Name", "cfg:ExternalDataProcessorObject.$Name")
        $t = $t.Replace("DataProcessorObject.$Name", "ExternalDataProcessorObject.$Name")
        $t = $t.Replace("DataProcessor.$Name.", "ExternalDataProcessor.$Name.")
        if ($t -ne $orig) {
          $utf8Bom = New-Object System.Text.UTF8Encoding $true
          [System.IO.File]::WriteAllText($_.FullName, $t, $utf8Bom)
        }
      }
    }

    Write-Host "EXTRACT_ROOT=$dstXml"
    Write-Host "Source DataProcessors/$Name left unchanged (delete from config only on explicit request)."
  }
}

Write-Host "OK action=$Action"
exit 0
