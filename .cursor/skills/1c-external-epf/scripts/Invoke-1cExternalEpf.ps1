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
  $required = $true
  if ($Cfg.auth -and $null -ne $Cfg.auth.required) { $required = [bool]$Cfg.auth.required }
  $user = $env:1C_IB_USER
  $pwd = $env:1C_IB_PASSWORD
  $auth = $Cfg.auth
  if ($auth) {
    if ($auth -is [hashtable]) {
      if ($auth.ContainsKey("user") -and $auth["user"]) { $user = [string]$auth["user"] }
      if ($auth.ContainsKey("password") -and $null -ne $auth["password"]) { $pwd = [string]$auth["password"] }
    } else {
      if ($auth.user) { $user = [string]$auth.user }
      if ($null -ne $auth.password) { $pwd = [string]$auth.password }
    }
  }
  if (-not $user -and $required) {
    $ibType = "file"
    if ($Cfg.infobase -and $Cfg.infobase.type) { $ibType = [string]$Cfg.infobase.type }
    if ($ibType -eq "file") { $user = "Admin" }
  }
  if (-not $user -and $required) { throw "Need auth.user in project.local.json or 1C_IB_USER." }
  if ($null -eq $pwd) { $pwd = "" }
  return @{ User = $user; Password = $pwd; Required = $required }
}

function Get-DesignerAuthArgs($Auth) {
  if (-not $Auth.User) { return @() }
  return @("/N$($Auth.User)", "/P$($Auth.Password)")
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

function Test-ServiceIbEnabled($Cfg) {
  if ($Cfg.ext -and $Cfg.ext.serviceIb -and $null -ne $Cfg.ext.serviceIb.enabled) {
    return [bool]$Cfg.ext.serviceIb.enabled
  }
  return $true
}

function Get-ServiceIbPaths($Cfg, [string]$ProjectRoot) {
  $dbRel = ".1c/ib-ext"
  $dataRel = ".1c/ib-ext-data"
  if ($Cfg.ext -and $Cfg.ext.serviceIb) {
    if ($Cfg.ext.serviceIb.dbPath) { $dbRel = ([string]$Cfg.ext.serviceIb.dbPath -replace "\\", "/").TrimEnd("/") }
    if ($Cfg.ext.serviceIb.dataDir) { $dataRel = ([string]$Cfg.ext.serviceIb.dataDir -replace "\\", "/").TrimEnd("/") }
  }
  $dbAbs = if ([IO.Path]::IsPathRooted($dbRel)) { $dbRel } else { Join-Path $ProjectRoot ($dbRel -replace "/", "\") }
  $dataAbs = if ([IO.Path]::IsPathRooted($dataRel)) { $dataRel } else { Join-Path $ProjectRoot ($dataRel -replace "/", "\") }
  $stampAbs = Join-Path $dbAbs ".config-stamp"
  return @{ DbRel = $dbRel; DataRel = $dataRel; DbAbs = $dbAbs; DataAbs = $dataAbs; StampAbs = $stampAbs }
}

function Resolve-Ibcmd([string]$Explicit, [string]$PlatformVersion) {
  if ($env:1C_IBCMD -and (Test-Path -LiteralPath $env:1C_IBCMD)) { return $env:1C_IBCMD }
  if ($Explicit -and (Test-Path -LiteralPath $Explicit)) { return $Explicit }
  if ($PlatformVersion) {
    $candidate = Join-Path ${env:ProgramFiles} "1cv8\$PlatformVersion\bin\ibcmd.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }
  $found = Get-ChildItem (Join-Path ${env:ProgramFiles} "1cv8") -Recurse -Filter "ibcmd.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1 -ExpandProperty FullName
  if ($found) { return $found }
  throw "ibcmd.exe not found. Set platformVersion or 1C_IBCMD."
}

function Invoke-IbcmdSimple([string]$IbcmdPath, [string[]]$IbcmdArgs, [string]$LogPath) {
  $safe = ($IbcmdArgs | ForEach-Object {
    if ($_ -match '^--password=' -or $_ -match '^--db-pwd=') { ($_ -replace '=.*$', '=***') } else { $_ }
  }) -join ' '
  Write-Host ">> $IbcmdPath $safe"
  if ($LogPath) { Add-Content -LiteralPath $LogPath -Value ">> $IbcmdPath $safe" -Encoding UTF8 }

  $argStr = ($IbcmdArgs | ForEach-Object {
    if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
  }) -join ' '
  $outFile = [IO.Path]::GetTempFileName()
  $errFile = [IO.Path]::GetTempFileName()
  try {
    $cmdInner = "`"$IbcmdPath`" $argStr < NUL > `"$outFile`" 2> `"$errFile`""
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$cmdInner`"" -WindowStyle Hidden -PassThru -Wait
    $stdout = if (Test-Path $outFile) { Get-Content -LiteralPath $outFile -Raw -Encoding Default } else { "" }
    $stderr = if (Test-Path $errFile) { Get-Content -LiteralPath $errFile -Raw -Encoding Default } else { "" }
    $combined = ($stdout + "`n" + $stderr).Trim()
    if ($combined.Length -gt 1200) {
      Write-Host ($combined.Substring(0, 600) + "`n...[truncated]...`n" + $combined.Substring($combined.Length - 400))
    } elseif ($combined) {
      Write-Host $combined
    }
    if ($LogPath -and $combined) { Add-Content -LiteralPath $LogPath -Value $combined -Encoding UTF8 }
    if ($p.ExitCode -ne 0) {
      throw "ibcmd exit $($p.ExitCode). See $LogPath"
    }
  } finally {
    Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
  }
}

function Get-ConfigImportStamp([string]$SrcAbs) {
  $cfgXml = Join-Path $SrcAbs "Configuration.xml"
  if (-not (Test-Path -LiteralPath $cfgXml)) {
    throw "Configuration.xml not found under $SrcAbs - dump config to src/ first."
  }
  $item = Get-Item -LiteralPath $cfgXml
  return "{0}|{1}" -f $item.LastWriteTimeUtc.Ticks, $item.Length
}

function Test-ServiceIbCurrent($Paths, [string]$ExpectedStamp) {
  $cd = Join-Path $Paths.DbAbs "1Cv8.1CD"
  if (-not (Test-Path -LiteralPath $cd)) { return $false }
  if (-not (Test-Path -LiteralPath $Paths.StampAbs)) { return $false }
  $saved = (Get-Content -LiteralPath $Paths.StampAbs -Raw -Encoding UTF8).Trim()
  return $saved -eq $ExpectedStamp
}

function Remove-ServiceIbTree($Paths) {
  if (Test-Path -LiteralPath $Paths.DbAbs) { Remove-Item -LiteralPath $Paths.DbAbs -Recurse -Force }
  if (Test-Path -LiteralPath $Paths.DataAbs) { Remove-Item -LiteralPath $Paths.DataAbs -Recurse -Force }
}

function Ensure-ServiceIb($Cfg, [string]$ProjectRoot, [string]$SrcAbs, [switch]$Force) {
  $paths = Get-ServiceIbPaths $Cfg $ProjectRoot
  $stamp = Get-ConfigImportStamp $SrcAbs
  if (-not $Force -and (Test-ServiceIbCurrent $paths $stamp)) {
    Write-Host "SERVICE_IB=ready stamp=$stamp path=$($paths.DbAbs)"
    return $paths
  }

  $ibcmdExplicit = ""
  if ($Cfg.ibcmd -and $Cfg.ibcmd.path) { $ibcmdExplicit = [string]$Cfg.ibcmd.path }
  $platformVersion = if ($Cfg.platformVersion) { [string]$Cfg.platformVersion } else { "" }
  $ibcmdPath = Resolve-Ibcmd $ibcmdExplicit $platformVersion

  $logDir = Join-Path $ProjectRoot ".1c"
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  $log = Join-Path $logDir "ext-service-ib.log"
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content -LiteralPath $log -Value "`n=== $ts Ensure-ServiceIb force=$Force ===" -Encoding UTF8

  Write-Host "SERVICE_IB=prepare wipe+create+import (no apply) path=$($paths.DbAbs)"
  Remove-ServiceIbTree $paths
  New-Item -ItemType Directory -Force -Path $paths.DbAbs, $paths.DataAbs | Out-Null

  Invoke-IbcmdSimple $ibcmdPath @(
    "infobase", "create",
    "--db-path=$($paths.DbAbs)",
    "--data=$($paths.DataAbs)",
    "--create-database", "--force"
  ) $log

  Invoke-IbcmdSimple $ibcmdPath @(
    "infobase", "config", "import",
    "--db-path=$($paths.DbAbs)",
    "--data=$($paths.DataAbs)",
    $SrcAbs
  ) $log

  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [IO.File]::WriteAllText($paths.StampAbs, $stamp, $utf8NoBom)
  Write-Host "SERVICE_IB=ready stamp=$stamp"
  return $paths
}

function Get-DesignerCfgForEpf($Cfg, [string]$ProjectRoot, [string]$SrcAbs, [switch]$ForceRefresh, [switch]$SkipPrepare) {
  if ($SkipPrepare -or -not (Test-ServiceIbEnabled $Cfg)) {
    Write-Host "SERVICE_IB=skipped (using project infobase from project.json)"
    return $Cfg
  }
  $paths = Ensure-ServiceIb $Cfg $ProjectRoot $SrcAbs $ForceRefresh
  $epfCfg = $Cfg | ConvertTo-Json -Depth 20 | ConvertFrom-Json
  $epfCfg.infobase = [pscustomobject]@{
    type = "file"
    path = $paths.DbRel
  }
  $epfCfg.auth = [pscustomobject]@{ required = $false }
  return $epfCfg
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
    $epfCfg = Get-DesignerCfgForEpf $cfg $ProjectRoot $srcAbs $RefreshServiceIb $SkipServiceIbPrepare
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
    $epfCfg = Get-DesignerCfgForEpf $cfg $ProjectRoot $srcAbs $RefreshServiceIb $SkipServiceIbPrepare
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
