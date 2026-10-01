# UTF-8 BOM required (PS 5.1). ASCII punctuation only.
# Dot-source this file. Converts dump file paths / metadata names to object anchors
# and can invalidate ConfigDumpInfo.xml versions so export --sync re-dumps them.

function Get-1cDumpPluralToType {
  return @{
    "AccumulationRegisters"           = "AccumulationRegister"
    "AccountingRegisters"             = "AccountingRegister"
    "BusinessProcesses"               = "BusinessProcess"
    "Bots"                            = "Bot"
    "CalculationRegisters"            = "CalculationRegister"
    "Catalogs"                        = "Catalog"
    "ChartsOfAccounts"                = "ChartOfAccounts"
    "ChartsOfCalculationTypes"        = "ChartOfCalculationTypes"
    "ChartsOfCharacteristicTypes"     = "ChartOfCharacteristicTypes"
    "CommandGroups"                   = "CommandGroup"
    "CommonAttributes"                = "CommonAttribute"
    "CommonCommands"                  = "CommonCommand"
    "CommonForms"                     = "CommonForm"
    "CommonModules"                   = "CommonModule"
    "CommonPictures"                  = "CommonPicture"
    "CommonTemplates"                 = "CommonTemplate"
    "Constants"                       = "Constant"
    "DataProcessors"                  = "DataProcessor"
    "DefinedTypes"                    = "DefinedType"
    "DocumentJournals"                = "DocumentJournal"
    "DocumentNumerators"              = "DocumentNumerator"
    "Documents"                       = "Document"
    "Enums"                           = "Enum"
    "EventSubscriptions"              = "EventSubscription"
    "ExchangePlans"                   = "ExchangePlan"
    "ExternalDataSources"             = "ExternalDataSource"
    "FilterCriteria"                  = "FilterCriterion"
    "FunctionalOptions"               = "FunctionalOption"
    "FunctionalOptionsParameters"     = "FunctionalOptionsParameter"
    "HTTPServices"                    = "HTTPService"
    "InformationRegisters"            = "InformationRegister"
    "IntegrationServices"             = "IntegrationService"
    "Languages"                       = "Language"
    "Reports"                         = "Report"
    "Roles"                           = "Role"
    "ScheduledJobs"                   = "ScheduledJob"
    "Sequences"                       = "Sequence"
    "SessionParameters"               = "SessionParameter"
    "SettingsStorages"                = "SettingsStorage"
    "StyleItems"                      = "StyleItem"
    "Styles"                          = "Style"
    "Subsystems"                      = "Subsystem"
    "Tasks"                           = "Task"
    "WebServices"                     = "WebService"
    "WSReferences"                    = "WSReference"
    "XDTOPackages"                    = "XDTOPackage"
  }
}

function Get-1cDumpTypeToPlural {
  $inv = @{}
  $map = Get-1cDumpPluralToType
  foreach ($k in $map.Keys) { $inv[$map[$k]] = $k }
  return $inv
}

function Get-1cDumpTypeSet {
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $map = Get-1cDumpPluralToType
  foreach ($t in $map.Values) { [void]$set.Add($t) }
  [void]$set.Add("Configuration")
  return $set
}

function Test-1cDumpObjectName([string]$Line) {
  if (-not $Line) { return $false }
  if ($Line -match '[\\/]') { return $false }
  $head = $Line.Split('.')[0]
  if ($head -eq "Configuration") { return $true }
  $types = Get-1cDumpTypeSet
  return $types.Contains($head)
}

function Reduce-1cDumpAnchor([string]$Name) {
  $n = ($Name -replace '\\', '/').Trim().Trim('.')
  if (-not $n) { return $n }
  $leaf = @(
    "ObjectModule", "ManagerModule", "RecordSetModule", "ValueManagerModule",
    "CommandModule", "SessionModule", "ManagedApplicationModule",
    "OrdinaryApplicationModule", "ExternalConnectionModule",
    "Help", "Predefined", "Module"
  )
  $parts = @($n.Split('.'))
  if ($parts.Count -ge 2 -and $parts[0] -eq "Configuration" -and ($leaf -contains $parts[-1])) {
    return "Configuration"
  }
  $changed = $true
  while ($changed -and $parts.Count -ge 3) {
    $changed = $false
    $last = $parts[-1]
    if ($leaf -contains $last) {
      $parts = @($parts[0..($parts.Count - 2)])
      $changed = $true
      continue
    }
    if ($last -eq "Form" -and $parts.Count -ge 4 -and $parts[-3] -eq "Form") {
      $parts = @($parts[0..($parts.Count - 2)])
      $changed = $true
      continue
    }
    if ($last -eq "Template" -and $parts.Count -ge 4 -and $parts[-3] -eq "Template") {
      $parts = @($parts[0..($parts.Count - 2)])
      $changed = $true
    }
  }
  return ($parts -join '.')
}

function Convert-1cSubsystemDumpPath([string[]]$Parts) {
  $names = New-Object System.Collections.Generic.List[string]
  $i = 0
  while ($i -lt $Parts.Count) {
    if (-not $Parts[$i].Equals("Subsystems", [StringComparison]::OrdinalIgnoreCase)) { break }
    $i++
    if ($i -ge $Parts.Count) { break }
    $n = [IO.Path]::GetFileNameWithoutExtension($Parts[$i])
    if ($n) { [void]$names.Add($n) }
    $i++
    if ($i -lt $Parts.Count -and -not $Parts[$i].Equals("Subsystems", [StringComparison]::OrdinalIgnoreCase)) {
      break
    }
  }
  if ($names.Count -eq 0) { throw "incomplete Subsystems path" }
  return (($names | ForEach-Object { "Subsystem.$_" }) -join '.')
}

function Convert-1cSrcRelToDumpObject([string]$Rel) {
  $rel = ($Rel -replace '\\', '/').Trim().Trim('/')
  if (-not $rel) { throw "empty dump path" }
  if ($rel -match '^(?i)ConfigDumpInfo\.xml$') { return $null }
  if ($rel -match '^(?i)Configuration\.xml$') { return "Configuration" }
  if ($rel -match '^(?i)Ext/([^/]+)$') {
    return "Configuration"
  }

  $parts = @($rel.Split('/'))
  $folder = $parts[0]
  $map = Get-1cDumpPluralToType
  if (-not $map.ContainsKey($folder)) {
    throw "unknown dump folder '$folder' in '$rel' - pass a metadata name (Catalog.Name) instead"
  }
  $type = $map[$folder]

  if ($type -eq "Subsystem") {
    return (Convert-1cSubsystemDumpPath $parts)
  }

  if ($parts.Count -lt 2) { throw "incomplete dump path: $rel" }

  $nameSeg = $parts[1]
  $objName = [IO.Path]::GetFileNameWithoutExtension($nameSeg)
  if (-not $objName) { throw "incomplete dump path: $rel" }

  $isFile = $nameSeg.Contains('.')
  if ($isFile -or $parts.Count -eq 2) {
    return "$type.$objName"
  }

  $kind = $parts[2]
  if ($kind.Equals("Forms", [StringComparison]::OrdinalIgnoreCase)) {
    if ($parts.Count -lt 4) { return "$type.$objName" }
    $form = [IO.Path]::GetFileNameWithoutExtension($parts[3])
    return "$type.$objName.Form.$form"
  }
  if ($kind.Equals("Templates", [StringComparison]::OrdinalIgnoreCase)) {
    if ($parts.Count -lt 4) { return "$type.$objName" }
    $t = [IO.Path]::GetFileNameWithoutExtension($parts[3])
    return "$type.$objName.Template.$t"
  }
  if ($kind.Equals("Commands", [StringComparison]::OrdinalIgnoreCase)) {
    if ($parts.Count -lt 4) { return "$type.$objName" }
    $c = [IO.Path]::GetFileNameWithoutExtension($parts[3])
    return "$type.$objName.Command.$c"
  }
  return "$type.$objName"
}

function Convert-1cDumpListLine {
  param(
    [string]$Line,
    [string]$SrcRel,
    [string]$DumpAbs,
    [string]$ProjectRoot
  )
  $raw = ($Line -replace '\\', '/').Trim()
  if (-not $raw -or $raw.StartsWith('#')) { return $null }

  if (Test-1cDumpObjectName $raw) {
    return (Reduce-1cDumpAnchor $raw)
  }

  $rel = $raw
  if ([IO.Path]::IsPathRooted(($Line.Trim()))) {
    $full = [IO.Path]::GetFullPath($Line.Trim())
    $dumpFull = [IO.Path]::GetFullPath($DumpAbs)
    if ($full.StartsWith($dumpFull, [StringComparison]::OrdinalIgnoreCase)) {
      $rel = $full.Substring($dumpFull.Length).TrimStart('\', '/')
    } else {
      throw "path is outside xml dir: $Line"
    }
  } else {
    $srcPrefix = (($SrcRel -replace '\\', '/').Trim('/')) + '/'
    if ($rel.StartsWith($srcPrefix, [StringComparison]::OrdinalIgnoreCase)) {
      $rel = $rel.Substring($srcPrefix.Length)
    } elseif ($rel.StartsWith('src/', [StringComparison]::OrdinalIgnoreCase)) {
      $rel = $rel.Substring(4)
    }
  }
  $rel = ($rel -replace '\\', '/').Trim('/')
  $obj = Convert-1cSrcRelToDumpObject $rel
  if (-not $obj) { return $null }
  return (Reduce-1cDumpAnchor $obj)
}

function Read-1cDumpListRawLines {
  param(
    [string]$ListFile,
    [string]$Objects,
    [string]$ProjectRoot,
    [string]$NeedMsg
  )
  $lines = New-Object System.Collections.Generic.List[string]
  if ($ListFile) {
    $listPath = $ListFile
    if (-not [IO.Path]::IsPathRooted($listPath)) {
      $listPath = Join-Path $ProjectRoot $listPath
    }
    if (-not (Test-Path -LiteralPath $listPath)) { throw "ListFile not found: $listPath" }
    foreach ($ln in @(Get-Content -LiteralPath $listPath -Encoding UTF8)) {
      if ($null -ne $ln) { [void]$lines.Add([string]$ln) }
    }
  }
  if ($Objects) {
    foreach ($p in @($Objects.Split(@(',', ';'), [StringSplitOptions]::RemoveEmptyEntries))) {
      [void]$lines.Add($p)
    }
  }
  if ($lines.Count -eq 0) {
    throw $NeedMsg
  }
  return @($lines)
}

function Read-1cDumpObjectList {
  param(
    [string]$ListFile,
    [string]$Objects,
    [string]$SrcRel,
    [string]$DumpAbs,
    [string]$ProjectRoot
  )
  $lines = @(Read-1cDumpListRawLines -ListFile $ListFile -Objects $Objects -ProjectRoot $ProjectRoot -NeedMsg "dump-objects needs -ListFile and/or -Objects")

  $anchors = New-Object System.Collections.Generic.List[string]
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($ln in $lines) {
    $a = Convert-1cDumpListLine -Line $ln -SrcRel $SrcRel -DumpAbs $DumpAbs -ProjectRoot $ProjectRoot
    if (-not $a) { continue }
    if ($seen.Add($a)) { [void]$anchors.Add($a) }
  }
  if ($anchors.Count -eq 0) {
    throw "dump-objects: no metadata objects resolved from the list"
  }
  return @(Get-MinimalDumpAnchors @($anchors))
}

function Get-MinimalDumpAnchors([string[]]$Anchors) {
  $sorted = @($Anchors | Sort-Object Length, { $_ })
  $keep = New-Object System.Collections.Generic.List[string]
  foreach ($a in $sorted) {
    $covered = $false
    foreach ($k in $keep) {
      if ($a.Equals($k, [StringComparison]::OrdinalIgnoreCase)) { $covered = $true; break }
      if ($a.StartsWith(($k + '.'), [StringComparison]::OrdinalIgnoreCase)) { $covered = $true; break }
    }
    if (-not $covered) { [void]$keep.Add($a) }
  }
  return @($keep)
}

function Convert-1cDumpAnchorToSrcRel([string]$Anchor) {
  $n = ($Anchor -replace '\\', '/').Trim().Trim('.')
  if (-not $n) { throw "empty dump anchor" }

  $parts = @($n.Split('.'))
  if ($parts[0].Equals("Configuration", [StringComparison]::OrdinalIgnoreCase)) {
    throw "load-files: Configuration is too broad; pass an object/form xml (Catalogs/Name.xml, Catalogs/Name/Forms/Form.xml)"
  }

  if ($parts[0].Equals("Subsystem", [StringComparison]::OrdinalIgnoreCase)) {
    if ($parts.Count -lt 2 -or ($parts.Count % 2) -ne 0) {
      throw "cannot map dump anchor to xml: $n"
    }
    $segs = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $parts.Count; $i += 2) {
      if (-not $parts[$i].Equals("Subsystem", [StringComparison]::OrdinalIgnoreCase)) {
        throw "cannot map dump anchor to xml: $n"
      }
      $name = $parts[$i + 1]
      if (-not $name) { throw "cannot map dump anchor to xml: $n" }
      [void]$segs.Add("Subsystems")
      if ($i -eq ($parts.Count - 2)) {
        [void]$segs.Add("$name.xml")
      } else {
        [void]$segs.Add($name)
      }
    }
    return ($segs -join '/')
  }

  $inv = Get-1cDumpTypeToPlural
  $type = $parts[0]
  if (-not $inv.ContainsKey($type)) {
    throw "unknown metadata type '$type' in '$n'"
  }
  $plural = $inv[$type]
  if ($parts.Count -lt 2 -or -not $parts[1]) {
    throw "incomplete dump anchor: $n"
  }
  $objName = $parts[1]
  if ($parts.Count -eq 2) {
    return "$plural/$objName.xml"
  }
  if ($parts.Count -eq 4) {
    $kind = $parts[2]
    $child = $parts[3]
    if (-not $child) { throw "cannot map dump anchor to xml: $n" }
    if ($kind.Equals("Form", [StringComparison]::OrdinalIgnoreCase)) {
      return "$plural/$objName/Forms/$child.xml"
    }
    if ($kind.Equals("Template", [StringComparison]::OrdinalIgnoreCase)) {
      return "$plural/$objName/Templates/$child.xml"
    }
    if ($kind.Equals("Command", [StringComparison]::OrdinalIgnoreCase)) {
      return "$plural/$objName/Commands/$child.xml"
    }
  }
  throw "cannot map dump anchor to xml: $n"
}

function Test-1cDumpRelIsExtPayload([string]$Rel) {
  $n = ($Rel -replace '\\', '/').Trim().Trim('/')
  if (-not $n) { return $false }
  $segs = @($n.Split('/'))
  $childKinds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($k in @("Forms", "Templates", "Commands", "Subsystems")) { [void]$childKinds.Add($k) }
  for ($i = 0; $i -lt $segs.Count; $i++) {
    if (-not $segs[$i].Equals("Ext", [StringComparison]::OrdinalIgnoreCase)) { continue }
    if ($i -eq ($segs.Count - 1)) { return $true }
    $next = $segs[$i + 1]
    $nextName = [IO.Path]::GetFileNameWithoutExtension($next)
    if ($childKinds.Contains($next) -or $childKinds.Contains($nextName)) { continue }
    return $true
  }
  return $false
}

function Convert-1cLoadFileList {
  param(
    [string]$ListFile,
    [string]$Objects,
    [string]$SrcRel,
    [string]$DumpAbs,
    [string]$ProjectRoot
  )
  $lines = @(Read-1cDumpListRawLines -ListFile $ListFile -Objects $Objects -ProjectRoot $ProjectRoot -NeedMsg "load-files needs -ListFile and/or -Objects")

  $absFiles = New-Object System.Collections.Generic.List[string]
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($ln in $lines) {
    $raw = ([string]$ln).Trim()
    $anchor = Convert-1cDumpListLine -Line $ln -SrcRel $SrcRel -DumpAbs $DumpAbs -ProjectRoot $ProjectRoot
    if (-not $anchor) { continue }
    $rel = Convert-1cDumpAnchorToSrcRel $anchor
    if (Test-1cDumpRelIsExtPayload $rel) {
      throw "load-files: do not pass Ext/Form.xml or Module.bsl; need Forms/<Name>.xml (got $rel from $raw)"
    }
    $norm = ($rel -replace '/', '\')
    $abs = [IO.Path]::GetFullPath((Join-Path $DumpAbs $norm))
    Write-Host "REDUCE $raw -> $anchor -> $rel"
    if (-not (Test-Path -LiteralPath $abs)) { throw "missing file for load: $abs" }
    if ($seen.Add($abs)) { [void]$absFiles.Add($abs) }
  }
  if ($absFiles.Count -eq 0) {
    throw "load-files: no metadata objects resolved from the list"
  }
  return @($absFiles)
}

function Get-FlippedConfigVersion([string]$Ver) {
  if ([string]::IsNullOrEmpty($Ver)) { return "1" }
  $c = $Ver.Substring(0, 1)
  $n = if ($c -eq '0') { '1' } else { '0' }
  if ($Ver.Length -eq 1) { return $n }
  return $n + $Ver.Substring(1)
}

function Invalidate-1cConfigDumpInfoVersions {
  param(
    [string]$CdiPath,
    [string[]]$Anchors
  )
  if (-not (Test-Path -LiteralPath $CdiPath)) {
    throw "need ConfigDumpInfo.xml - run dump-full first"
  }
  $bytes = [IO.File]::ReadAllBytes($CdiPath)
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $encIn = New-Object System.Text.UTF8Encoding $false
  $text = $encIn.GetString($bytes, $(if ($hasBom) { 3 } else { 0 }), $bytes.Length - $(if ($hasBom) { 3 } else { 0 }))

  $missing = New-Object System.Collections.Generic.List[string]
  $total = 0
  foreach ($anchor in @($Anchors)) {
    $esc = [regex]::Escape($anchor)
    $pattern = '(<Metadata name="(?:' + $esc + '|' + $esc + '\.[^"]+)"[^>]*configVersion=")([0-9A-Fa-f]+)(")'
    $re = New-Object System.Text.RegularExpressions.Regex($pattern)
    $count = $re.Matches($text).Count
    if ($count -eq 0) {
      [void]$missing.Add($anchor)
      continue
    }
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
      param($m)
      $flipped = Get-FlippedConfigVersion $m.Groups[2].Value
      $m.Groups[1].Value + $flipped + $m.Groups[3].Value
    }
    $text = $re.Replace($text, $evaluator)
    $total += $count
    Write-Host "INVALIDATE $anchor versions=$count"
  }
  if ($missing.Count -gt 0) {
    throw ("dump-objects: not in ConfigDumpInfo.xml: " + ($missing -join ', '))
  }
  if ($total -eq 0) {
    throw "dump-objects: no configVersion attributes updated"
  }
  $encOut = New-Object System.Text.UTF8Encoding $hasBom
  [IO.File]::WriteAllText($CdiPath, $text, $encOut)
  Write-Host "INVALIDATED_TOTAL=$total"
  return $total
}
