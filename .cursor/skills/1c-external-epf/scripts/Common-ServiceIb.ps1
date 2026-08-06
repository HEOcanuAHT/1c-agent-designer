# Shared helpers: project.json merge, ibcmd, service IB (.1c/ib-ext) for EPF/CFE pack.
# Dot-source from Invoke-1cExternalEpf.ps1 / Invoke-1cExternalCfe.ps1.

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

function Invoke-IbcmdSimple(
  [string]$IbcmdPath,
  [string[]]$IbcmdArgs,
  [string]$LogPath,
  [int]$StallSec = 300,
  [int]$HardTimeoutSec = 0
) {
  # Direct Start-Process (no cmd /c + Hidden + stdin NUL). The cmd+redirect wrapper
  # intermittently hung ibcmd config import (CPU≈0, 1CD not growing).
  $safe = ($IbcmdArgs | ForEach-Object {
    if ($_ -match '^--password=' -or $_ -match '^--db-pwd=') { ($_ -replace '=.*$', '=***') } else { $_ }
  }) -join ' '
  Write-Host ">> $IbcmdPath $safe"
  if ($LogPath) { Add-Content -LiteralPath $LogPath -Value ">> $IbcmdPath $safe" -Encoding UTF8 }

  $outFile = [IO.Path]::GetTempFileName()
  $errFile = [IO.Path]::GetTempFileName()
  $proc = $null
  try {
    # Quote args for Start-Process (array binding is lossy with spaces)
    $argLine = ($IbcmdArgs | ForEach-Object {
      if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' '

    $proc = Start-Process -FilePath $IbcmdPath -ArgumentList $argLine `
      -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
      -NoNewWindow -PassThru

    $started = Get-Date
    $lastCpuMs = -1.0
    $stallSince = $null
    $pollSec = 2

    while (-not $proc.HasExited) {
      Start-Sleep -Seconds $pollSec
      if ($HardTimeoutSec -gt 0 -and ((Get-Date) - $started).TotalSeconds -ge $HardTimeoutSec) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        throw "ibcmd hard timeout after ${HardTimeoutSec}s (pid=$($proc.Id)). See $LogPath"
      }
      if ($StallSec -le 0) { continue }
      try {
        $live = Get-Process -Id $proc.Id -ErrorAction Stop
        $cpuMs = $live.TotalProcessorTime.TotalMilliseconds
        if ($lastCpuMs -ge 0 -and [math]::Abs($cpuMs - $lastCpuMs) -lt 0.5) {
          if ($null -eq $stallSince) { $stallSince = Get-Date }
          elseif (((Get-Date) - $stallSince).TotalSeconds -ge $StallSec) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
            throw ("ibcmd stalled (CPU idle ~{0}s, pid={1}). Killed. See {2}" -f $StallSec, $proc.Id, $LogPath)
          }
        } else {
          $stallSince = $null
        }
        $lastCpuMs = $cpuMs
      } catch {
        # process exited between HasExited check and Get-Process
        break
      }
    }

    if (-not $proc.HasExited) {
      $null = $proc.WaitForExit()
    } else {
      # Ensure ExitCode is populated after async exit
      $null = $proc.WaitForExit(0)
    }
    $proc.Refresh()
    $exitCode = $proc.ExitCode
    if ($null -eq $exitCode) {
      # Start-Process can leave ExitCode null briefly; treat missing code after exit as failure signal only if HasExited is false
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
    # ibcmd sometimes prints [ERROR] but still exits 0
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

  if ($AllowApply) {
    Write-Host "SERVICE_IB=prepare wipe+create+import+apply (SERVICE IB ONLY) path=$($paths.DbAbs)"
  } else {
    Write-Host "SERVICE_IB=prepare wipe+create+import (no apply) path=$($paths.DbAbs)"
  }
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

  if ($AllowApply) {
    Write-Host "SERVICE_IB=apply --force (compat mismatch workaround; never on project IB)"
    Invoke-IbcmdSimple $ibcmdPath @(
      "infobase", "config", "apply",
      "--db-path=$($paths.DbAbs)",
      "--data=$($paths.DataAbs)",
      "--force"
    ) $log
  }

  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [IO.File]::WriteAllText($paths.StampAbs, $stamp, $utf8NoBom)
  Write-Host "SERVICE_IB=ready stamp=$stamp"
  return $paths
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
