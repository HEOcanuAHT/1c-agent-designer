# Service IB (.1c/ib-ext) for EPF/CFE pack and query-validate.
# Home: 1c-runtime/scripts (with Common-Project / Common-IbcmdConnection).
# Dot-source from Invoke-1cExternalEpf / Invoke-1cExternalCfe / Invoke-1cValidateQuery.

$IbcmdConnPath = Join-Path $PSScriptRoot "Common-IbcmdConnection.ps1"
if (-not (Test-Path -LiteralPath $IbcmdConnPath)) {
  throw "Missing $IbcmdConnPath"
}
. $IbcmdConnPath

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

function Invoke-IbcmdSimple(
  [string]$IbcmdPath,
  [string[]]$IbcmdArgs,
  [string]$LogPath,
  [int]$StallSec = 90,
  [int]$HardTimeoutSec = 900
) {
  # Redirect to temp FILES (not console / not cmd). Under Cursor the agent console is a
  # pipe: ibcmd config import can block on WARN writes (CPU≈0, 1CD stuck). File redirect
  # + Hidden avoids that. Do not use cmd /c ... <NUL (also hang-prone).
  $safe = ($IbcmdArgs | ForEach-Object {
    if ($_ -match '^--password=' -or $_ -match '^--db-pwd=') { ($_ -replace '=.*$', '=***') } else { $_ }
  }) -join ' '
  Write-Host ">> $IbcmdPath $safe"
  if ($LogPath) { Add-Content -LiteralPath $LogPath -Value ">> $IbcmdPath $safe" -Encoding UTF8 }

  $argLine = ($IbcmdArgs | ForEach-Object {
    if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
  }) -join ' '

  $dbPath = $null
  foreach ($a in $IbcmdArgs) {
    if ($a -match '^--db-path=(.+)$') { $dbPath = $Matches[1].Trim('"'); break }
  }
  $cdFile = $null
  if ($dbPath) { $cdFile = Join-Path $dbPath "1Cv8.1CD" }

  $outArtifact = $null
  if ($IbcmdArgs.Count -gt 0) {
    $lastArg = [string]$IbcmdArgs[$IbcmdArgs.Count - 1]
    if ($lastArg -notmatch '^--' -and $lastArg -match '\.(cf|cfe|epf)$') {
      $outArtifact = $lastArg.Trim('"')
    }
  }

  $outFile = [IO.Path]::GetTempFileName()
  $errFile = [IO.Path]::GetTempFileName()
  $proc = $null
  try {
    $proc = Start-Process -FilePath $IbcmdPath -ArgumentList $argLine `
      -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
      -WindowStyle Hidden -PassThru

    $started = Get-Date
    $lastCpuMs = -1.0
    $lastCdSize = -1L
    $lastArtSize = -1L
    $lastIo = -1L
    $stallSince = $null
    $pollSec = 2

    while (-not $proc.HasExited) {
      Start-Sleep -Seconds $pollSec
      $elapsedNow = ((Get-Date) - $started).TotalSeconds
      if ($HardTimeoutSec -gt 0 -and $elapsedNow -ge $HardTimeoutSec) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        throw "ibcmd hard timeout after ${HardTimeoutSec}s (pid=$($proc.Id)). See $LogPath"
      }
      if ($StallSec -le 0) { continue }

      $cpuMs = -1.0
      $ioOps = -1L
      try {
        $live = Get-Process -Id $proc.Id -ErrorAction Stop
        $cpuMs = $live.TotalProcessorTime.TotalMilliseconds
        $ioOps = [int64]$live.ReadOperationCount + [int64]$live.WriteOperationCount
      } catch {
        break
      }

      $cdSize = -1L
      $cdProgress = $false
      if ($cdFile -and (Test-Path -LiteralPath $cdFile)) {
        $cdSize = (Get-Item -LiteralPath $cdFile).Length
        if ($lastCdSize -ge 0 -and $cdSize -gt $lastCdSize) { $cdProgress = $true }
      }
      $artProgress = $false
      if ($outArtifact -and (Test-Path -LiteralPath $outArtifact)) {
        $artSize = (Get-Item -LiteralPath $outArtifact).Length
        if ($lastArtSize -ge 0 -and $artSize -gt $lastArtSize) { $artProgress = $true }
        $lastArtSize = $artSize
      }
      $ioProgress = ($lastIo -ge 0 -and $ioOps -gt $lastIo)
      $cpuIdle = ($lastCpuMs -ge 0 -and [math]::Abs($cpuMs - $lastCpuMs) -lt 0.5)
      if ($cdProgress -or $ioProgress -or $artProgress) {
        $stallSince = $null
      } elseif ($cpuIdle) {
        if ($null -eq $stallSince) { $stallSince = Get-Date }
        elseif (((Get-Date) - $stallSince).TotalSeconds -ge $StallSec) {
          try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
          throw ("ibcmd stalled (CPU idle / no IO / 1CD not growing ~{0}s, pid={1}, 1CD={2}). Killed. See {3}" -f `
            $StallSec, $proc.Id, $cdSize, $LogPath)
        }
      } else {
        $stallSince = $null
      }
      $lastCpuMs = $cpuMs
      $lastIo = $ioOps
      if ($cdSize -ge 0) { $lastCdSize = $cdSize }
    }

    if (-not $proc.HasExited) {
      $null = $proc.WaitForExit()
    } else {
      $null = $proc.WaitForExit(0)
    }
    $proc.Refresh()
    $exitCode = $proc.ExitCode
    if ($null -eq $exitCode) {
      if ($proc.HasExited) { $exitCode = 0 } else { $exitCode = -1 }
    }

    $stdout = if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile -Raw -Encoding Default } else { "" }
    $stderr = if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile -Raw -Encoding Default } else { "" }
    if ($null -eq $stdout) { $stdout = "" }
    if ($null -eq $stderr) { $stderr = "" }
    $combined = ($stdout + "`n" + $stderr).Trim()
    if ($combined.Length -gt 1200) {
      Write-Host ($combined.Substring(0, 600) + "`n...[truncated]...`n" + $combined.Substring($combined.Length - 400))
    } elseif ($combined) {
      Write-Host $combined
    }
    if ($LogPath -and $combined) { Add-Content -LiteralPath $LogPath -Value $combined -Encoding UTF8 }
    $elapsed = [int]((Get-Date) - $started).TotalSeconds
    if ($LogPath) {
      Add-Content -LiteralPath $LogPath -Value ("ibcmd exit={0} elapsedSec={1}" -f $exitCode, $elapsed) -Encoding UTF8
    }
    Write-Host ("ibcmd exit={0} elapsedSec={1}" -f $exitCode, $elapsed)
    $hint = Get-IbcmdFailureHint $combined ([int]$exitCode)
    if ($hint) { throw $hint }
    if ($combined -match '(?m)^\[ERROR\]') {
      throw "ibcmd reported ERROR (exit $exitCode). See $LogPath"
    }
    if ([int]$exitCode -ne 0) {
      throw "ibcmd exit $exitCode. See $LogPath"
    }
  } finally {
    Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
  }
}

function Stop-OrphanIbcmdForDb([string]$DbAbs) {
  if (-not $DbAbs) { return }
  $needle = $DbAbs -replace '\\', '/'
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'ibcmd.exe' -and $_.CommandLine -and ($_.CommandLine -replace '\\', '/') -like "*$needle*" } |
    ForEach-Object {
      Write-Warning "Killing orphan ibcmd pid=$($_.ProcessId) for $DbAbs"
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
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

function Test-ServiceIbCanLoadFromProjectCf($Cfg, [string]$ProjectRoot, $ServicePaths) {
  $type = Get-InfobaseType $Cfg
  if ($type -eq "file") {
    $dbPath = Get-InfobaseFilePath $Cfg $ProjectRoot
    if (-not $dbPath) { return $false }
    if ($ServicePaths -and $ServicePaths.DbAbs) {
      try {
        $liveFull = [IO.Path]::GetFullPath($dbPath).TrimEnd('\', '/')
        $svcFull = [IO.Path]::GetFullPath($ServicePaths.DbAbs).TrimEnd('\', '/')
        if ($liveFull.Equals($svcFull, [StringComparison]::OrdinalIgnoreCase)) { return $false }
      } catch { }
    }
    return (Test-Path -LiteralPath (Join-Path $dbPath "1Cv8.1CD"))
  }
  if ($type -notin @("server", "ibname")) { return $false }
  $dbms = Get-InfobaseDbms $Cfg
  if (-not $dbms) { return $false }
  $server = [string]$dbms.server
  if (-not $server -and $dbms.PSObject.Properties["dbServer"]) { $server = [string]$dbms.dbServer }
  $name = [string]$dbms.name
  if (-not $name -and $dbms.PSObject.Properties["dbName"]) { $name = [string]$dbms.dbName }
  return ($server.Length -gt 0) -and ($name.Length -gt 0)
}

function Assert-FileIbNotLocked([string]$DbPath) {
  $cd = Join-Path $DbPath "1Cv8.1CD"
  if (-not (Test-Path -LiteralPath $cd)) { return }
  $fs = $null
  try {
    $fs = [IO.File]::Open($cd, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
  } catch {
    throw "Project file IB is locked (Configurator or another process): $DbPath. Close Designer on this IB and retry. Will not wait for hang."
  } finally {
    if ($fs) { $fs.Dispose() }
  }
}

function New-ServiceIbTempCfDir {
  $root = Join-Path ([IO.Path]::GetTempPath()) "1c-agent-designer"
  $dir = Join-Path $root ("svc-ib-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  return $dir
}

function Save-ConfigCfFromProjectIb($Cfg, [string]$ProjectRoot, [string]$CfPath, [string]$IbcmdPath, [string]$LogPath) {
  $conn = Get-ConnectionArgs $Cfg $ProjectRoot
  if ($conn.Mode -eq "file") {
    Assert-FileIbNotLocked (Get-InfobaseFilePath $Cfg $ProjectRoot)
  }
  $dataDump = Get-DataDir $Cfg $ProjectRoot
  $saveArgs = @(
    "infobase", "config", "save"
  ) + $conn.Args + @(
    "--data=$dataDump"
  ) + (Get-IbAuthArgs $Cfg $ProjectRoot) + @(
    $CfPath
  )
  $sqlNote = ""
  if ($conn.SqlAuth) { $sqlNote = "; $($conn.SqlAuth)" }
  Write-Host ("SERVICE_IB=save cf from project IB mode={0} {1}{2} (no apply; XML import hangs on large Hierarchical dumps)" -f `
    $conn.Mode, $conn.Label, $sqlNote)
  try {
    Invoke-IbcmdSimple $IbcmdPath $saveArgs $LogPath 300 1800
  } catch {
    if ($conn.Mode -eq "file") {
      throw ("config save from file IB failed. If Configurator is open on that IB, close it (exclusive lock). " + $_.Exception.Message)
    }
    throw
  }
}

function Load-ConfigCfIntoServiceIb($Paths, [string]$CfPath, [string]$IbcmdPath, [string]$LogPath) {
  Invoke-IbcmdSimple $IbcmdPath @(
    "infobase", "config", "load",
    "--db-path=$($Paths.DbAbs)",
    "--data=$($Paths.DataAbs)",
    $CfPath
  ) $LogPath 300 1800
}

function Ensure-ServiceIb($Cfg, [string]$ProjectRoot, [string]$SrcAbs, [switch]$Force, [switch]$AllowApply) {
  $paths = Get-ServiceIbPaths $Cfg $ProjectRoot
  # Stamp includes apply flag so toggling Apply forces rebuild
  $stamp = "{0}|apply={1}" -f (Get-ConfigImportStamp $SrcAbs), ([bool]$AllowApply)
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
  Add-Content -LiteralPath $log -Value "`n=== $ts Ensure-ServiceIb force=$Force allowApply=$AllowApply ===" -Encoding UTF8

  # Leftover hung ibcmd keeps directory lock ("process NNNN")
  Stop-OrphanIbcmdForDb $paths.DbAbs

  $fromCf = Test-ServiceIbCanLoadFromProjectCf $Cfg $ProjectRoot $paths
  if ($AllowApply) {
    Write-Host "SERVICE_IB=prepare wipe+create+load+apply (SERVICE IB ONLY) path=$($paths.DbAbs)"
  } elseif ($fromCf) {
    Write-Host "SERVICE_IB=prepare wipe+create+load-cf (no apply) path=$($paths.DbAbs)"
  } else {
    Write-Host "SERVICE_IB=prepare wipe+create+import (no apply) path=$($paths.DbAbs)"
  }

  $tempCfDir = $null
  try {
    $cfPath = $null
    if ($fromCf) {
      $tempCfDir = New-ServiceIbTempCfDir
      $cfPath = Join-Path $tempCfDir "config.cf"
      # Save first so a failed save keeps the existing service IB.
      Save-ConfigCfFromProjectIb $Cfg $ProjectRoot $cfPath $ibcmdPath $log
    }

    Remove-ServiceIbTree $paths
    New-Item -ItemType Directory -Force -Path $paths.DbAbs, $paths.DataAbs | Out-Null

    Invoke-IbcmdSimple $ibcmdPath @(
      "infobase", "create",
      "--db-path=$($paths.DbAbs)",
      "--data=$($paths.DataAbs)",
      "--create-database", "--force"
    ) $log

    if ($fromCf) {
      Load-ConfigCfIntoServiceIb $paths $cfPath $ibcmdPath $log
    } else {
      # XML import of large Hierarchical dumps can deadlock at 1CD~30MB (CPU=0, no IO).
      Invoke-IbcmdSimple $ibcmdPath @(
        "infobase", "config", "import",
        "--db-path=$($paths.DbAbs)",
        "--data=$($paths.DataAbs)",
        $SrcAbs
      ) $log 300 1800
    }

    if ($AllowApply) {
      Write-Host "SERVICE_IB=apply --force (compat mismatch workaround; never on project IB)"
      Invoke-IbcmdSimple $ibcmdPath @(
        "infobase", "config", "apply",
        "--db-path=$($paths.DbAbs)",
        "--data=$($paths.DataAbs)",
        "--force"
      ) $log 300 1800
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($paths.StampAbs, $stamp, $utf8NoBom)
    Write-Host "SERVICE_IB=ready stamp=$stamp"
    return $paths
  } finally {
    if ($tempCfDir -and (Test-Path -LiteralPath $tempCfDir)) {
      Remove-Item -LiteralPath $tempCfDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Get-ServiceIbCfg($Cfg, [string]$ProjectRoot, [string]$SrcAbs, [switch]$ForceRefresh, [switch]$SkipPrepare, [switch]$AllowApply) {
  if ($SkipPrepare -or -not (Test-ServiceIbEnabled $Cfg)) {
    Write-Host "SERVICE_IB=skipped (using project infobase from project.json)"
    return @{ Cfg = $Cfg; Paths = $null; IbcmdPath = $null }
  }
  # Named switches required: positional SwitchParameter binding drops -AllowApply / -Force
  $paths = Ensure-ServiceIb $Cfg $ProjectRoot $SrcAbs -Force:$ForceRefresh -AllowApply:$AllowApply
  $svcCfg = $Cfg | ConvertTo-Json -Depth 20 | ConvertFrom-Json
  $svcCfg.infobase = [pscustomobject]@{
    type = "file"
    path = $paths.DbRel
  }
  $svcCfg.auth = [pscustomobject]@{ required = $false }

  $ibcmdExplicit = ""
  if ($Cfg.ibcmd -and $Cfg.ibcmd.path) { $ibcmdExplicit = [string]$Cfg.ibcmd.path }
  $platformVersion = if ($Cfg.platformVersion) { [string]$Cfg.platformVersion } else { "" }
  $ibcmdPath = Resolve-Ibcmd $ibcmdExplicit $platformVersion

  return @{ Cfg = $svcCfg; Paths = $paths; IbcmdPath = $ibcmdPath }
}

# Back-compat alias used by EPF script
function Get-DesignerCfgForEpf($Cfg, [string]$ProjectRoot, [string]$SrcAbs, [switch]$ForceRefresh, [switch]$SkipPrepare) {
  return (Get-ServiceIbCfg $Cfg $ProjectRoot $SrcAbs -ForceRefresh:$ForceRefresh -SkipPrepare:$SkipPrepare).Cfg
}

function Resolve-UnderRoot([string]$ProjectRoot, [string]$RelOrAbs) {
  if ([System.IO.Path]::IsPathRooted($RelOrAbs)) { return $RelOrAbs }
  return (Join-Path $ProjectRoot ($RelOrAbs -replace "/", "\"))
}

function Get-IbcmdDbArgs($Paths) {
  return @(
    "--db-path=$($Paths.DbAbs)",
    "--data=$($Paths.DataAbs)"
  )
}
