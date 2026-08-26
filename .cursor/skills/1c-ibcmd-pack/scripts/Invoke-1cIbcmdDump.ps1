<#
.SYNOPSIS
  Dump / incremental dump / partial load via ibcmd (infobase config export|import).

.NOTES
  - Always `ibcmd infobase config ...` (not bare `config`) - otherwise auth hang on stdin.
  - No /IBName / cluster: --db-path or --dbms/--db-server/--db-name.
  - MSSQL Windows auth: omit --db-user/--db-pwd.
  - import files → MAIN config only; NEVER config apply (no update-db-cfg / КБД).
  - export/--sync also reads MAIN (verified: sees edits without applying DB cfg).
  - File IB + open Designer: exclusive lock error - tell user to close Configurator on that IB.
#>
[CmdletBinding()]
param(
  [ValidateSet("dump-full", "dump-update", "dump-objects", "load-files", "ping")]
  [string]$Action = "dump-full",

  [string]$ProjectRoot = (Get-Location).Path,

  # XML dir for dump out / load base-dir (default: project src)
  [string]$OutDir = "",

  # load-files: paths relative to OutDir/src. dump-objects: those paths and/or metadata names.
  [string]$ListFile = "",

  # dump-objects: comma-separated metadata names (Catalog.Name, Catalog.Name.Form.FormName)
  [string]$Objects = "",

  # dump-full into a non-empty OutDir: delete XML there, then export in-place (no staging copy).
  # Agent must ask the user first; do not pass this switch without an explicit yes.
  [switch]$WipeOutDir,

  # Incremental: do not park preserve leftovers (may fail if README/_ext still in OutDir).
  [switch]$NoStaging
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Convert-1cDumpObjectList.ps1")
. (Join-Path $PSScriptRoot "Common-IbcmdConnection.ps1")

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
  throw "ibcmd.exe not found. Set platformVersion or ibcmd / 1C_IBCMD."
}

function Get-PreserveRels($Cfg, [string]$DumpRel) {
  $rels = [System.Collections.Generic.List[string]]::new()
  # Leftovers from the old layout (inside dump dir). New defaults live outside src/.
  [void]$rels.Add("README.md")
  [void]$rels.Add("_extDataProcessors")
  [void]$rels.Add("_extensions")
  $dumpNorm = ($DumpRel -replace "\\", "/").TrimEnd("/")

  $extraDirs = [System.Collections.Generic.List[string]]::new()
  $extDir = "ext"
  if ($Cfg.ext -and $Cfg.ext.dir) { $extDir = ([string]$Cfg.ext.dir -replace "\\", "/").TrimEnd("/") }
  [void]$extraDirs.Add($extDir)
  $cfeDir = "cfe"
  if ($Cfg.cfe -and $Cfg.cfe.dir) { $cfeDir = ([string]$Cfg.cfe.dir -replace "\\", "/").TrimEnd("/") }
  [void]$extraDirs.Add($cfeDir)

  foreach ($dir in $extraDirs) {
    if ($dir.StartsWith("$dumpNorm/", [System.StringComparison]::OrdinalIgnoreCase)) {
      [void]$rels.Add($dir.Substring($dumpNorm.Length + 1))
    }
  }

  if ($Cfg.ibcmd -and $Cfg.ibcmd.preservePaths) {
    foreach ($p in @($Cfg.ibcmd.preservePaths)) {
      $norm = ([string]$p -replace "\\", "/").TrimStart("./")
      if ($norm) { [void]$rels.Add($norm) }
    }
  }
  return @($rels | Select-Object -Unique)
}

function Test-PathIsPreserved([string]$Name, [string[]]$PreserveRels) {
  foreach ($p in $PreserveRels) {
    $top = ($p -replace "\\", "/").Split("/")[0]
    if ($Name.Equals($top, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  }
  return $false
}

function Test-DumpDirNotEmpty([string]$DumpAbs) {
  $items = @(Get-ChildItem -LiteralPath $DumpAbs -Force -ErrorAction SilentlyContinue)
  return ($items.Count -gt 0)
}

function Test-NeedsPreservePark([string]$DumpAbs, [string[]]$PreserveRels) {
  foreach ($item in @(Get-ChildItem -LiteralPath $DumpAbs -Force -ErrorAction SilentlyContinue)) {
    if (Test-PathIsPreserved $item.Name $PreserveRels) { return $true }
  }
  return $false
}

function Get-ParkDir($Cfg, [string]$ProjectRoot) {
  $rel = ".1c/ibcmd-dump-park"
  if ($Cfg.ibcmd -and $Cfg.ibcmd.parkDir) { $rel = [string]$Cfg.ibcmd.parkDir }
  if ([System.IO.Path]::IsPathRooted($rel)) { return $rel }
  return Join-Path $ProjectRoot $rel
}

function Reset-EmptyDir([string]$Dir) {
  if (Test-Path -LiteralPath $Dir) {
    Remove-Item -LiteralPath $Dir -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
}

function Clear-DumpDirContents([string]$DumpAbs) {
  foreach ($item in @(Get-ChildItem -LiteralPath $DumpAbs -Force -ErrorAction SilentlyContinue)) {
    Remove-Item -LiteralPath $item.FullName -Recurse -Force
  }
}

# Move leftover README/_ext aside so export/--sync can run in-place (Move, not a full dump copy).
function Move-PreserveAside([string]$DumpAbs, [string]$ParkDir, [string[]]$PreserveRels) {
  Reset-EmptyDir $ParkDir
  $moved = [System.Collections.Generic.List[string]]::new()
  foreach ($item in @(Get-ChildItem -LiteralPath $DumpAbs -Force -ErrorAction SilentlyContinue)) {
    if (Test-PathIsPreserved $item.Name $PreserveRels) {
      Move-Item -LiteralPath $item.FullName -Destination $ParkDir -Force
      [void]$moved.Add($item.Name)
    }
  }
  return @($moved)
}

function Restore-PreserveFromPark([string]$ParkDir, [string]$DumpAbs) {
  if (-not (Test-Path -LiteralPath $ParkDir)) { return }
  New-Item -ItemType Directory -Force -Path $DumpAbs | Out-Null
  foreach ($item in @(Get-ChildItem -LiteralPath $ParkDir -Force -ErrorAction SilentlyContinue)) {
    $dest = Join-Path $DumpAbs $item.Name
    if (Test-Path -LiteralPath $dest) {
      Remove-Item -LiteralPath $dest -Recurse -Force
    }
    Move-Item -LiteralPath $item.FullName -Destination $DumpAbs -Force
  }
  Remove-Item -LiteralPath $ParkDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Test-IbcmdAuthPrompt([string]$Text) {
  if (-not $Text) { return $false }
  $re = [string]::Concat(
    '\u0418\u043c\u044f \u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044f\s*:', '|',
    '\u041f\u0430\u0440\u043e\u043b\u044c \u0434\u043b\u044f\s+.', '|',
    '\u0442\u0440\u0435\u0431\u0443\u0435\u0442\u0441\u044f \u0430\u0443\u0442\u0435\u043d\u0442\u0438\u0444\u0438\u043a\u0430\u0446\u0438\u044f'
  )
  return [bool]([regex]::IsMatch($Text, $re))
}

function Read-SharedText([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return "" }
  try {
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
      # ibcmd console messages are OEM866
      $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8, $true)
      try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    } finally { $fs.Dispose() }
  } catch { return "" }
}

function Throw-IbcmdFailure([string]$Combined, [int]$ExitCode) {
  $hint = Get-IbcmdFailureHint $Combined $ExitCode
  if ($hint) { throw $hint }
  $reFull = '\u044d\u043a\u0441\u043f\u043e\u0440\u0442\u0438\u0440\u043e\u0432\u0430\u0442\u044c \u043a\u043e\u043d\u0444\u0438\u0433\u0443\u0440\u0430\u0446\u0438\u044e \u043f\u043e\u043b\u043d\u043e\u0441\u0442\u044c\u044e|export.*full'
  $reNotEmpty = '\u043a\u0430\u0442\u0430\u043b\u043e\u0433 .+ \u043d\u0435 \u043f\u0443\u0441\u0442|directory .+ is not empty|not empty'
  if ([regex]::IsMatch($Combined, $reFull)) {
    throw "ibcmd: ConfigDumpInfo does not match this IB - run dump-full into this folder first, then dump-update. exit=$ExitCode"
  }
  if ([regex]::IsMatch($Combined, $reNotEmpty)) {
    throw "ibcmd: export target must be empty. dump-full into a non-empty dir needs -WipeOutDir (after the user confirms src will be cleared). exit=$ExitCode"
  }
  throw "ibcmd exited with code $ExitCode"
}

function Invoke-IbcmdNoHang([string]$IbcmdPath, [string[]]$IbcmdArgs, [string]$LogPath) {
  $safe = ($IbcmdArgs | ForEach-Object {
    if ($_ -match '^--password=' -or $_ -match '^--db-pwd=') {
      ($_ -replace '=.*$', '=***')
    } else { $_ }
  }) -join ' '
  Write-Host ">> $IbcmdPath $safe"
  if ($LogPath) { Add-Content -Path $LogPath -Value ">> $IbcmdPath $safe" }

  $argStr = ($IbcmdArgs | ForEach-Object {
    if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
  }) -join ' '

  $outFile = [IO.Path]::GetTempFileName()
  $errFile = [IO.Path]::GetTempFileName()
  $killedAuth = $false
  $exitCode = -1
  try {
    # Redirects inside cmd (not Start-Process) - reliable with paths that contain spaces.
    # Poll files: auth prompt is on stdout, often without waiting for process exit.
    $cmdInner = "`"$IbcmdPath`" $argStr < NUL > `"$outFile`" 2> `"$errFile`""
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$cmdInner`"" -WindowStyle Hidden -PassThru
    while (-not $p.HasExited) {
      $combinedLive = (Read-SharedText $outFile) + "`n" + (Read-SharedText $errFile)
      if ($combinedLive.Length -gt 8000) { $combinedLive = $combinedLive.Substring(0, 8000) }
      if (Test-IbcmdAuthPrompt $combinedLive) {
        $killedAuth = $true
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        Get-Process -Name ibcmd -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        break
      }
      Start-Sleep -Milliseconds 200
    }
    if (-not $p.HasExited) {
      [void]$p.WaitForExit(3000)
      if (-not $p.HasExited) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        Get-Process -Name ibcmd -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        [void]$p.WaitForExit(3000)
      }
    }
    if ($p.HasExited) { $exitCode = $p.ExitCode }
    if ($killedAuth) { $exitCode = -1 }

    $stdout = Read-SharedText $outFile
    $stderr = Read-SharedText $errFile
    # Avoid dumping megabytes of repeated "User name:" prompts
    $printOut = $stdout
    if ($printOut.Length -gt 2000) { $printOut = $printOut.Substring(0, 500) + "`n...[truncated]...`n" + $printOut.Substring($printOut.Length - 300) }
    if ($printOut.Trim()) {
      Write-Host $printOut.TrimEnd()
      if ($LogPath) { Add-Content -Path $LogPath -Value $printOut.TrimEnd() }
    }
    if ($stderr.Trim()) {
      Write-Host $stderr.TrimEnd()
      if ($LogPath) { Add-Content -Path $LogPath -Value $stderr.TrimEnd() }
    }
    $combined = $stdout + "`n" + $stderr
    if ($killedAuth -or $exitCode -ne 0) {
      Throw-IbcmdFailure $combined $exitCode
    }
  } finally {
    Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
  }
}

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfgPath = Join-Path $ProjectRoot ".1c\project.json"
$localPath = Join-Path $ProjectRoot ".1c\project.local.json"
if (-not (Test-Path -LiteralPath $cfgPath)) {
  throw "Missing $cfgPath"
}

$cfg = Merge-Config (Read-JsonFile $cfgPath) (Read-JsonFile $localPath)
$ibcmdPath = Resolve-Ibcmd ([string]$cfg.ibcmd) ([string]$cfg.platformVersion)
$conn = Get-ConnectionArgs $cfg $ProjectRoot
$dataDir = Get-DataDir $cfg $ProjectRoot
$authArgs = Get-IbAuthArgs $cfg $ProjectRoot

$srcRel = if ($cfg.src) { ([string]$cfg.src -replace "\\", "/").TrimEnd("/") } else { "src" }
if ($OutDir) {
  $outRel = ($OutDir -replace "\\", "/").TrimEnd("/")
  $dumpAbs = if ([System.IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $ProjectRoot $OutDir }
} else {
  $outRel = $srcRel
  $dumpAbs = Join-Path $ProjectRoot ($srcRel -replace "/", "\")
}
New-Item -ItemType Directory -Force -Path $dumpAbs | Out-Null
$preserveRels = Get-PreserveRels $cfg $outRel
$parkDir = Get-ParkDir $cfg $ProjectRoot
$parkPreserve = (-not $NoStaging) -and ($Action -eq "dump-update" -or $Action -eq "dump-objects") -and (Test-NeedsPreservePark $dumpAbs $preserveRels)

$log = Join-Path $ProjectRoot ".1c\ibcmd-dump.log"
$common = @("infobase", "config") + $conn.Args + @("--data=$dataDir") + $authArgs

Write-Host "project=$ProjectRoot"
Write-Host "ibcmd=$ibcmdPath"
Write-Host "connection=$($conn.Label)"
if ($conn.SqlAuth) { Write-Host "SQL auth=$($conn.SqlAuth)" }
Write-Host "data=$dataDir"
Write-Host "xmlDir=$dumpAbs"
Write-Host "action=$Action"
if ($preserveRels.Count -gt 0) { Write-Host "preserve=$($preserveRels -join ', ')" }
if ($parkPreserve) { Write-Host "park=$parkDir" }
Write-Host "update-db-cfg/apply: never (main config only)"

$sw = [Diagnostics.Stopwatch]::StartNew()

switch ($Action) {
  "ping" {
    $probeDir = Join-Path $ProjectRoot ".1c\ibcmd-probe"
    New-Item -ItemType Directory -Force -Path $probeDir | Out-Null
    Invoke-IbcmdNoHang $ibcmdPath ($common + @("export", "info", "--out=$probeDir")) $log
    Write-Host "OK ping (export info)"
  }
  "dump-full" {
    if (Test-DumpDirNotEmpty $dumpAbs) {
      if (-not $WipeOutDir) {
        Write-Host "NEED_WIPE=true"
        throw "dump-full: $dumpAbs is not empty. Ask the user that XML in this folder will be deleted and rewritten from IB, then re-run with -WipeOutDir. ext/ and cfe/ outside src are not touched; leftover README/_extDataProcessors/_extensions inside src are parked and restored."
      }
      if (Test-NeedsPreservePark $dumpAbs $preserveRels) {
        $moved = Move-PreserveAside $dumpAbs $parkDir $preserveRels
        if ($moved.Count -gt 0) { Write-Host "parked=$($moved -join ', ')" }
      }
      try {
        Clear-DumpDirContents $dumpAbs
        Invoke-IbcmdNoHang $ibcmdPath ($common + @("export", $dumpAbs)) $log
      } finally {
        Restore-PreserveFromPark $parkDir $dumpAbs
      }
    } else {
      Invoke-IbcmdNoHang $ibcmdPath ($common + @("export", $dumpAbs)) $log
    }
  }
  "dump-update" {
    $cdi = Join-Path $dumpAbs "ConfigDumpInfo.xml"
    if (-not (Test-Path -LiteralPath $cdi)) {
      throw "need ConfigDumpInfo.xml in $dumpAbs - run dump-full first"
    }
    if ($parkPreserve) {
      $moved = Move-PreserveAside $dumpAbs $parkDir $preserveRels
      if ($moved.Count -gt 0) { Write-Host "parked=$($moved -join ', ')" }
      try {
        Invoke-IbcmdNoHang $ibcmdPath ($common + @("export", "--sync", $dumpAbs)) $log
      } finally {
        Restore-PreserveFromPark $parkDir $dumpAbs
      }
    } else {
      Invoke-IbcmdNoHang $ibcmdPath ($common + @("export", "--sync", $dumpAbs)) $log
    }
  }
  "dump-objects" {
    $cdi = Join-Path $dumpAbs "ConfigDumpInfo.xml"
    if (-not (Test-Path -LiteralPath $cdi)) {
      throw "need ConfigDumpInfo.xml in $dumpAbs - run dump-full first"
    }
    $anchors = Read-1cDumpObjectList -ListFile $ListFile -Objects $Objects -SrcRel $outRel -DumpAbs $dumpAbs -ProjectRoot $ProjectRoot
    Write-Host "OBJECTS=$($anchors -join ', ')"
    $bak = Join-Path $ProjectRoot ".1c\ConfigDumpInfo.dump-objects.bak"
    New-Item -ItemType Directory -Force -Path (Split-Path $bak) | Out-Null
    Copy-Item -LiteralPath $cdi -Destination $bak -Force
    try {
      [void](Invalidate-1cConfigDumpInfoVersions -CdiPath $cdi -Anchors $anchors)
      try {
        if ($parkPreserve) {
          $moved = Move-PreserveAside $dumpAbs $parkDir $preserveRels
          if ($moved.Count -gt 0) { Write-Host "parked=$($moved -join ', ')" }
          try {
            Invoke-IbcmdNoHang $ibcmdPath ($common + @("export", "--sync", $dumpAbs)) $log
          } finally {
            Restore-PreserveFromPark $parkDir $dumpAbs
          }
        } else {
          Invoke-IbcmdNoHang $ibcmdPath ($common + @("export", "--sync", $dumpAbs)) $log
        }
      } catch {
        Copy-Item -LiteralPath $bak -Destination $cdi -Force
        Write-Host "RESTORED ConfigDumpInfo.xml after failed dump-objects"
        throw
      }
    } finally {
      Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue
    }
  }
  "load-files" {
    if (-not $ListFile) { throw "load-files requires -ListFile (paths relative to xml dir)" }
    $listPath = if ([System.IO.Path]::IsPathRooted($ListFile)) { $ListFile } else { Join-Path $ProjectRoot $ListFile }
    if (-not (Test-Path -LiteralPath $listPath)) { throw "ListFile not found: $listPath" }
    $rels = Get-Content -LiteralPath $listPath -Encoding UTF8 |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ -and ($_ -notmatch '^\s*#') }
    if ($rels.Count -eq 0) { throw "ListFile is empty: $listPath" }
    $absFiles = @()
    foreach ($rel in $rels) {
      $norm = $rel -replace "/", "\"
      $abs = Join-Path $dumpAbs $norm
      if (-not (Test-Path -LiteralPath $abs)) { throw "missing file for load: $abs" }
      $absFiles += $abs
      Write-Host "LOAD $rel"
    }
    Write-Host "import files → MAIN config only (no apply)"
    Invoke-IbcmdNoHang $ibcmdPath ($common + @("import", "files", "--base-dir=$dumpAbs") + $absFiles) $log
  }
}

$sw.Stop()
if ($Action -eq "dump-full" -or $Action -eq "dump-update" -or $Action -eq "dump-objects") {
  $cfgXml = Join-Path $dumpAbs "Configuration.xml"
  $marker = Join-Path $dumpAbs "ConfigDumpInfo.xml"
  if (-not (Test-Path -LiteralPath $cfgXml)) { throw "${Action}: missing $cfgXml" }
  if (-not (Test-Path -LiteralPath $marker)) { throw "${Action}: missing $marker" }
  $files = @(Get-ChildItem -LiteralPath $dumpAbs -Recurse -File -EA SilentlyContinue)
  Write-Host "DUMP_DIR=$dumpAbs"
  Write-Host "DUMP_FILES=$($files.Count)"
  Write-Host "DUMP_BYTES=$(($files | Measure-Object Length -Sum).Sum)"
}
Write-Host ("ELAPSED_SEC={0}" -f [math]::Round($sw.Elapsed.TotalSeconds, 1))
Write-Host "OK action=$Action"
