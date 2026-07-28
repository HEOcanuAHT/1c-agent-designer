<#
.SYNOPSIS
  Dump / incremental dump / partial load via ibcmd (infobase config export|import).

.NOTES
  - Always `ibcmd infobase config …` (not bare `config`) — otherwise auth hang on stdin.
  - No /IBName / cluster: --db-path or --dbms/--db-server/--db-name.
  - MSSQL Windows auth: omit --db-user/--db-pwd.
  - import files → MAIN config only; NEVER config apply (no update-db-cfg / КБД).
  - export/--sync also reads MAIN (verified: sees edits without applying DB cfg).
  - File IB + open Designer: exclusive lock error — tell user to close Configurator on that IB.
#>
[CmdletBinding()]
param(
  [ValidateSet("dump-full", "dump-update", "load-files", "ping")]
  [string]$Action = "dump-full",

  [string]$ProjectRoot = (Get-Location).Path,

  # XML dir for dump out / load base-dir (default: project src)
  [string]$OutDir = "",

  # For load-files: paths relative to OutDir/src, one per line (UTF-8)
  [string]$ListFile = "",

  # Export/sync directly into OutDir (bench dirs). Default: staging when README/_ext present.
  [switch]$NoStaging
)

$ErrorActionPreference = "Stop"

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

function Get-IbAuthArgs($Cfg, [string]$ProjectRoot = "") {
  $credHelper = Join-Path $PSScriptRoot "..\..\1c-project-bootstrap\scripts\1c-WindowsCredential.ps1"
  if (-not (Test-Path -LiteralPath $credHelper)) {
    throw "Missing credential helper: $credHelper"
  }
  . $credHelper
  $auth = Resolve-1cIbAuth -Cfg $Cfg -ProjectRoot $ProjectRoot
  if (-not $auth.Required) { return @() }
  Write-Host "ibcmd auth source=$($auth.Source)"
  $a = @("--user=$($auth.User)")
  if ($null -ne $auth.Password -and $auth.Password -ne "") { $a += "--password=$($auth.Password)" }
  return $a
}

function Get-InfobaseType($Cfg) {
  if ($Cfg.infobase -and $Cfg.infobase.type) { return [string]$Cfg.infobase.type }
  return "file"
}

function Get-InfobaseDbms($Cfg) {
  if ($Cfg.infobase -and $Cfg.infobase.dbms) { return $Cfg.infobase.dbms }
  if ($Cfg.ibcmd -and $Cfg.ibcmd.dbms) {
    Write-Warning "ibcmd.dbms is deprecated; move dbms into infobase (one IB description for all tools)."
    return $Cfg.ibcmd.dbms
  }
  return $null
}

function Get-InfobaseFilePath($Cfg, [string]$ProjectRoot) {
  $p = $null
  if ($env:1C_IB_PATH) { $p = $env:1C_IB_PATH }
  elseif ($Cfg.infobase -and $Cfg.infobase.path) { $p = [string]$Cfg.infobase.path }
  else { $p = ".1c/ib-dev" }
  if ([System.IO.Path]::IsPathRooted($p)) { return $p }
  return Join-Path $ProjectRoot $p
}

function Get-ConnectionArgs($Cfg, [string]$ProjectRoot) {
  $type = Get-InfobaseType $Cfg

  if ($type -eq "file") {
    $dbPath = Get-InfobaseFilePath $Cfg $ProjectRoot
    return @{ Mode = "file"; Args = @("--db-path=$dbPath"); Label = "file:$dbPath" }
  }

  if ($type -eq "ibname" -or $type -eq "server") {
    $dbms = Get-InfobaseDbms $Cfg
    if (-not $dbms) {
      throw @"
infobase.type=$type but infobase.dbms is missing (ibcmd needs direct SQL).
Fill infobase.dbms { kind, server, name } or use designer-agent (tools.preferredDump=agent).
"@
    }
    $kind = [string]$dbms.kind
    if (-not $kind -and $dbms.PSObject.Properties["type"]) { $kind = [string]$dbms.type }
    if (-not $kind) { $kind = "MSSQLServer" }
    $server = [string]$dbms.server
    if (-not $server -and $dbms.PSObject.Properties["dbServer"]) { $server = [string]$dbms.dbServer }
    $name = [string]$dbms.name
    if (-not $name -and $dbms.PSObject.Properties["dbName"]) { $name = [string]$dbms.dbName }
    if (-not $server -or -not $name) {
      throw "infobase.dbms.server and infobase.dbms.name are required for client-server IB."
    }
    $args = @("--dbms=$kind", "--db-server=$server", "--db-name=$name")

    $winAuth = $true
    if ($null -ne $dbms.windowsAuth) { $winAuth = [bool]$dbms.windowsAuth }
    if (-not $winAuth) {
      $dbUser = $env:1C_DB_USER
      $dbPwd = $env:1C_DB_PASSWORD
      if ($dbms.user) { $dbUser = [string]$dbms.user }
      if ($dbms.password) { $dbPwd = [string]$dbms.password }
      if (-not $dbUser) { throw "infobase.dbms.windowsAuth=false but db user missing (dbms.user / 1C_DB_USER)." }
      $args += "--db-user=$dbUser"
      if ($null -ne $dbPwd -and $dbPwd -ne "") { $args += "--db-pwd=$dbPwd" }
    }
    return @{ Mode = "dbms"; Args = $args; Label = "$kind/$server/$name (windowsAuth=$winAuth)" }
  }

  throw "infobase.type must be file, ibname, or server (got '$type')."
}

function Get-DataDir($Cfg, [string]$ProjectRoot) {
  $rel = ".1c/ibcmd-data"
  if ($Cfg.ibcmd -and $Cfg.ibcmd.dataDir) { $rel = [string]$Cfg.ibcmd.dataDir }
  $path = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $ProjectRoot $rel }
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  return $path
}

function Get-StagingDir($Cfg, [string]$ProjectRoot) {
  $rel = ".1c/ibcmd-dump-staging"
  if ($Cfg.ibcmd -and $Cfg.ibcmd.stagingDir) { $rel = [string]$Cfg.ibcmd.stagingDir }
  if ([System.IO.Path]::IsPathRooted($rel)) { return $rel }
  return Join-Path $ProjectRoot $rel
}

function Get-PreserveRels($Cfg, [string]$DumpRel) {
  $rels = [System.Collections.Generic.List[string]]::new()
  [void]$rels.Add("README.md")
  $extDir = "src/_extDataProcessors"
  if ($Cfg.ext -and $Cfg.ext.dir) { $extDir = ([string]$Cfg.ext.dir -replace "\\", "/").TrimEnd("/") }
  $dumpNorm = ($DumpRel -replace "\\", "/").TrimEnd("/")
  if ($extDir.StartsWith("$dumpNorm/", [System.StringComparison]::OrdinalIgnoreCase)) {
    [void]$rels.Add($extDir.Substring($dumpNorm.Length + 1))
  } elseif ($extDir -notmatch "/") {
    [void]$rels.Add($extDir)
  } else {
    $leaf = [IO.Path]::GetFileName($extDir)
    if ($leaf) { [void]$rels.Add($leaf) }
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

function Test-NeedsDumpStaging([string]$DumpAbs, [string[]]$PreserveRels, [string]$Action) {
  $items = @(Get-ChildItem -LiteralPath $DumpAbs -Force -ErrorAction SilentlyContinue)
  if ($items.Count -eq 0) { return $false }
  if ($Action -eq "dump-full") { return $true }
  foreach ($item in $items) {
    if (Test-PathIsPreserved $item.Name $PreserveRels) { return $true }
  }
  return $false
}

function Reset-StagingDir([string]$Staging) {
  if (Test-Path -LiteralPath $Staging) {
    Remove-Item -LiteralPath $Staging -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $Staging | Out-Null
}

function Clear-DumpDirExceptPreserve([string]$DumpAbs, [string[]]$PreserveRels) {
  foreach ($item in @(Get-ChildItem -LiteralPath $DumpAbs -Force -ErrorAction SilentlyContinue)) {
    if (-not (Test-PathIsPreserved $item.Name $PreserveRels)) {
      Remove-Item -LiteralPath $item.FullName -Recurse -Force
    }
  }
}

function Copy-DumpTree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force -Path $To | Out-Null
  foreach ($item in @(Get-ChildItem -LiteralPath $From -Force -ErrorAction SilentlyContinue)) {
    Copy-Item -LiteralPath $item.FullName -Destination $To -Recurse -Force
  }
}

function Copy-ConfigDumpToStaging([string]$DumpAbs, [string]$Staging, [string[]]$PreserveRels) {
  Reset-StagingDir $Staging
  foreach ($item in @(Get-ChildItem -LiteralPath $DumpAbs -Force -ErrorAction SilentlyContinue)) {
    if (-not (Test-PathIsPreserved $item.Name $PreserveRels)) {
      Copy-Item -LiteralPath $item.FullName -Destination $Staging -Recurse -Force
    }
  }
}

function Merge-DumpStaging([string]$Staging, [string]$DumpAbs, [string[]]$PreserveRels) {
  New-Item -ItemType Directory -Force -Path $DumpAbs | Out-Null
  Clear-DumpDirExceptPreserve $DumpAbs $PreserveRels
  Copy-DumpTree $Staging $DumpAbs
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
  $reLock = '\u0438\u0441\u043a\u043b\u044e\u0447\u0438\u0442\u0435\u043b\u044c\u043d\w* \u0431\u043b\u043e\u043a\u0438\u0440\u043e\u0432\u043a|exclusive lock'
  $reAuth = [string]::Concat(
    '\u0418\u0434\u0435\u043d\u0442\u0438\u0444\u0438\u043a\u0430\u0446\u0438\u044f \u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044f \u043d\u0435 \u0432\u044b\u043f\u043e\u043b\u043d\u0435\u043d\u0430', '|',
    '\u0442\u0440\u0435\u0431\u0443\u0435\u0442\u0441\u044f \u0430\u0443\u0442\u0435\u043d\u0442\u0438\u0444\u0438\u043a\u0430\u0446\u0438\u044f', '|',
    '\u0418\u043c\u044f \u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044f\s*:', '|',
    '\u041f\u0430\u0440\u043e\u043b\u044c \u0434\u043b\u044f\s+.'
  )
  $reFull = '\u044d\u043a\u0441\u043f\u043e\u0440\u0442\u0438\u0440\u043e\u0432\u0430\u0442\u044c \u043a\u043e\u043d\u0444\u0438\u0433\u0443\u0440\u0430\u0446\u0438\u044e \u043f\u043e\u043b\u043d\u043e\u0441\u0442\u044c\u044e|export.*full'
  $reNotEmpty = '\u043a\u0430\u0442\u0430\u043b\u043e\u0433 .+ \u043d\u0435 \u043f\u0443\u0441\u0442|directory .+ is not empty|not empty'
  if ([regex]::IsMatch($Combined, $reLock)) {
    throw "ibcmd: exclusive lock on file IB - Configurator (or another process) holds this base. Close Designer on this IB and retry. exit=$ExitCode"
  }
  if ([regex]::IsMatch($Combined, $reAuth)) {
    throw "ibcmd: IB auth failed (wrong/missing user or password). Fix auth in project.local.json; if IB has no users set auth.required=false. exit=$ExitCode"
  }
  if ([regex]::IsMatch($Combined, $reFull)) {
    throw "ibcmd: ConfigDumpInfo does not match this IB - run dump-full into this folder first, then dump-update. exit=$ExitCode"
  }
  if ([regex]::IsMatch($Combined, $reNotEmpty)) {
    throw "ibcmd: export target must be empty (README/_extDataProcessors break full export). Use Invoke-1cIbcmdDump without -NoStaging. exit=$ExitCode"
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
$stagingDir = Get-StagingDir $cfg $ProjectRoot
$useStaging = (-not $NoStaging) -and (($Action -eq "dump-full") -or ($Action -eq "dump-update")) `
  -and (Test-NeedsDumpStaging $dumpAbs $preserveRels $Action)

$log = Join-Path $ProjectRoot ".1c\ibcmd-dump.log"
$common = @("infobase", "config") + $conn.Args + @("--data=$dataDir") + $authArgs

Write-Host "project=$ProjectRoot"
Write-Host "ibcmd=$ibcmdPath"
Write-Host "connection=$($conn.Label)"
Write-Host "data=$dataDir"
Write-Host "xmlDir=$dumpAbs"
Write-Host "action=$Action"
if ($preserveRels.Count -gt 0) { Write-Host "preserve=$($preserveRels -join ', ')" }
if ($useStaging) { Write-Host "staging=$stagingDir" }
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
    if ($useStaging) {
      Reset-StagingDir $stagingDir
      Invoke-IbcmdNoHang $ibcmdPath ($common + @("export", $stagingDir)) $log
      Merge-DumpStaging $stagingDir $dumpAbs $preserveRels
    } else {
      Invoke-IbcmdNoHang $ibcmdPath ($common + @("export", $dumpAbs)) $log
    }
  }
  "dump-update" {
    $cdi = Join-Path $dumpAbs "ConfigDumpInfo.xml"
    if (-not (Test-Path -LiteralPath $cdi)) {
      throw "need ConfigDumpInfo.xml in $dumpAbs - run dump-full first"
    }
    if ($useStaging) {
      Copy-ConfigDumpToStaging $dumpAbs $stagingDir $preserveRels
      $cdiStage = Join-Path $stagingDir "ConfigDumpInfo.xml"
      if (-not (Test-Path -LiteralPath $cdiStage)) {
        throw "staging copy missing ConfigDumpInfo.xml - run dump-full first"
      }
      Invoke-IbcmdNoHang $ibcmdPath ($common + @("export", "--sync", $stagingDir)) $log
      Merge-DumpStaging $stagingDir $dumpAbs $preserveRels
    } else {
      Invoke-IbcmdNoHang $ibcmdPath ($common + @("export", "--sync", $dumpAbs)) $log
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
if ($Action -eq "dump-full" -or $Action -eq "dump-update") {
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
