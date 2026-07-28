<#
.SYNOPSIS
  Pack 1C hierarchical XML dump (src) into .cf via ibcmd.
#>
[CmdletBinding()]
param(
  [ValidateSet("pack", "pack-delta", "ensure-ib", "import", "save-cf")]
  [string]$Action = "pack",

  [string]$ProjectRoot = (Get-Location).Path,

  # For pack-delta: determine what changed via `git diff`.
  # If empty, can be taken from .1c/project.json -> delta.baseRef/delta.headRef.
  [string]$BaseRef = "",
  [string]$HeadRef = ""
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

function Resolve-Git([string]$Explicit) {
  if ($Explicit -and (Test-Path -LiteralPath $Explicit)) { return $Explicit }
  $candidates = @(
    "C:\\Program Files\\Git\\bin\\git.exe",
    "C:\\Program Files (x86)\\Git\\bin\\git.exe",
    "$env:LOCALAPPDATA\\Programs\\Git\\bin\\git.exe"
  )
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  $cmd = Get-Command git -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw "git.exe not found. Install Git or add it to PATH."
}

function Get-AuthArgs($Cfg, [string]$ProjectRoot = "") {
  $credHelper = Join-Path $PSScriptRoot "..\..\1c-project-bootstrap\scripts\1c-WindowsCredential.ps1"
  if (-not (Test-Path -LiteralPath $credHelper)) {
    throw "Missing credential helper: $credHelper"
  }
  . $credHelper
  $auth = Resolve-1cIbAuth -Cfg $Cfg -ProjectRoot $ProjectRoot
  if (-not $auth.Required) { return @() }
  Write-Host "ibcmd auth source=$($auth.Source)"
  $a = @("--user=$($auth.User)")
  if ($auth.Password) { $a += "--password=$($auth.Password)" }
  return $a
}

function Test-FileIbExists([string]$DbPath) {
  if (-not (Test-Path -LiteralPath $DbPath)) { return $false }
  foreach ($name in @("1Cv8.1CD", "1cv8.1cd")) {
    if (Test-Path -LiteralPath (Join-Path $DbPath $name)) { return $true }
  }
  return $false
}

function Invoke-Ibcmd([string]$IbcmdPath, [string[]]$IbcmdArgs) {
  $safe = ($IbcmdArgs | ForEach-Object {
    if ($_ -match '^--password=' -or $_ -match '^--db-pwd=' -or $_ -match '^-P') {
      if ($_ -match '^-P$') { '-P***' } else { ($_ -replace '=.*$', '=***') }
    } else { $_ }
  }) -join ' '
  Write-Host ">> $IbcmdPath $safe"
  $argStr = ($IbcmdArgs | ForEach-Object {
    if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
  }) -join ' '
  $outFile = [IO.Path]::GetTempFileName()
  $errFile = [IO.Path]::GetTempFileName()
  function Read-Shared([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    try {
      $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
      try {
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8, $true)
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
      } finally { $fs.Dispose() }
    } catch { return "" }
  }
  try {
    $cmdInner = "`"$IbcmdPath`" $argStr < NUL > `"$outFile`" 2> `"$errFile`""
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$cmdInner`"" -WindowStyle Hidden -PassThru
    $killedAuth = $false
    $reAuth = [string]::Concat(
      '\u0418\u043c\u044f \u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044f\s*:', '|',
      '\u041f\u0430\u0440\u043e\u043b\u044c \u0434\u043b\u044f\s+.', '|',
      '\u0442\u0440\u0435\u0431\u0443\u0435\u0442\u0441\u044f \u0430\u0443\u0442\u0435\u043d\u0442\u0438\u0444\u0438\u043a\u0430\u0446\u0438\u044f'
    )
    while (-not $p.HasExited) {
      $live = (Read-Shared $outFile) + "`n" + (Read-Shared $errFile)
      if ([regex]::IsMatch($live, $reAuth)) {
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
    $stdout = Read-Shared $outFile
    $stderr = Read-Shared $errFile
    if ($stdout.Length -gt 2000) { $stdout = $stdout.Substring(0, 500) + "`n...[truncated]...`n" + $stdout.Substring($stdout.Length - 300) }
    if ($stdout) { Write-Host $stdout.TrimEnd() }
    if ($stderr) { Write-Host $stderr.TrimEnd() }
    if ($killedAuth) {
      throw "ibcmd: IB auth failed (wrong/missing user or password). Fix auth in project.local.json; if IB has no users set auth.required=false."
    }
    if ($p.ExitCode -ne 0) {
      throw "ibcmd exited with code $($p.ExitCode)"
    }
  } finally {
    Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
  }
}

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfgPath = Join-Path $ProjectRoot ".1c\project.json"
$localPath = Join-Path $ProjectRoot ".1c\project.local.json"

if (-not (Test-Path -LiteralPath $cfgPath)) {
  throw "Missing $cfgPath - copy project.json.example from skill 1c-ibcmd-pack."
}

$cfg = Merge-Config (Read-JsonFile $cfgPath) (Read-JsonFile $localPath)
$ibcmdPath = Resolve-Ibcmd ([string]$cfg.ibcmd) ([string]$cfg.platformVersion)

$srcRel = if ($cfg.src) { [string]$cfg.src } else { "src" }
$artRel = if ($cfg.artifacts) { [string]$cfg.artifacts } else { "artifacts" }
$src = Join-Path $ProjectRoot $srcRel
$artifacts = Join-Path $ProjectRoot $artRel

if ($env:1C_IB_PATH) {
  $dbPath = $env:1C_IB_PATH
} elseif ($cfg.infobase.path) {
  $p = [string]$cfg.infobase.path
  $dbPath = if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $ProjectRoot $p }
} else {
  $dbPath = Join-Path $ProjectRoot ".1c\ib-pack"
}

if ($Action -eq "pack-delta") {
  # Use separate IB to avoid mixing full pack and delta pack results.
  $deltaDb = $null
  if ($cfg.delta -and $cfg.delta.infobase -and $cfg.delta.infobase.path) {
    $p = [string]$cfg.delta.infobase.path
    $deltaDb = if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $ProjectRoot $p }
  } else {
    $deltaDb = Join-Path $ProjectRoot ".1c\ib-pack-delta"
  }
  $dbPath = $deltaDb
}

if ($cfg.infobase.type -and [string]$cfg.infobase.type -ne "file") {
  throw "Only infobase.type=file is supported."
}

$createIfMissing = $true
if ($cfg.infobase -and $null -ne $cfg.infobase.createIfMissing) {
  $createIfMissing = [bool]$cfg.infobase.createIfMissing
}

if ($Action -eq "pack-delta" -and $cfg.delta -and $cfg.delta.infobase -and $null -ne $cfg.delta.infobase.createIfMissing) {
  $createIfMissing = [bool]$cfg.delta.infobase.createIfMissing
}

$force = $true
$apply = $true
$cfName = "config.cf"
if ($cfg.pack) {
  if ($null -ne $cfg.pack.force) { $force = [bool]$cfg.pack.force }
  if ($null -ne $cfg.pack.apply) { $apply = [bool]$cfg.pack.apply }
  if ($cfg.pack.cfName) { $cfName = [string]$cfg.pack.cfName }
}

if ($Action -eq "pack-delta") {
  if ($cfg.delta -and $cfg.delta.cfName) {
    $cfName = [string]$cfg.delta.cfName
  } else {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($cfName)
    $cfName = "${base}-delta.cf"
  }
}

$authArgs = Get-AuthArgs $cfg $ProjectRoot
$commonDb = @("--db-path=$dbPath") + $authArgs
$forceArgs = @()
if ($force) { $forceArgs = @("--force") }

$authRequired = $false
if ($cfg.auth -and $null -ne $cfg.auth.required) { $authRequired = [bool]$cfg.auth.required }

Write-Host "project=$ProjectRoot"
Write-Host "ibcmd=$ibcmdPath"
Write-Host "db-path=$dbPath"
Write-Host "src=$src"
Write-Host "auth.required=$authRequired"
Write-Host "action=$Action"

function Ensure-EmptyIb {
  if (Test-FileIbExists $dbPath) {
    Write-Host "IB exists: $dbPath"
    return
  }
  if (-not $createIfMissing) { throw "IB not found: $dbPath" }
  New-Item -ItemType Directory -Force -Path $dbPath | Out-Null
  Invoke-Ibcmd $ibcmdPath (@("infobase", "create") + $commonDb + @("--create-database") + $forceArgs)
}

function Import-Xml {
  if (-not (Test-Path -LiteralPath (Join-Path $src "Configuration.xml"))) {
    throw "Missing $src\Configuration.xml"
  }
  Invoke-Ibcmd $ibcmdPath (@("infobase", "config", "import", "files") + $commonDb + @("--base-dir=$src") + $forceArgs)
  if ($apply) {
    Invoke-Ibcmd $ibcmdPath (@("infobase", "config", "apply") + $commonDb + $forceArgs + @("--dynamic=disable", "--session-terminate=force"))
  }
}

function Save-Cf {
  New-Item -ItemType Directory -Force -Path $artifacts | Out-Null
  $outCf = Join-Path $artifacts $cfName
  Invoke-Ibcmd $ibcmdPath (@("infobase", "config", "save") + $commonDb + @($outCf))
  Write-Host "CF_OUT=$outCf"
}

function Pack-All {
  if (-not (Test-Path -LiteralPath (Join-Path $src "Configuration.xml"))) {
    throw "Missing $src\Configuration.xml"
  }

  if (-not (Test-FileIbExists $dbPath)) {
    if (-not $createIfMissing) { throw "IB not found: $dbPath" }
    New-Item -ItemType Directory -Force -Path $dbPath | Out-Null
    $oneShot = @("infobase", "create") + $commonDb + @("--create-database", "--import=$src") + $forceArgs
    if ($apply) { $oneShot += "--apply" }
    Invoke-Ibcmd $ibcmdPath $oneShot
  } else {
    Import-Xml
  }
  Save-Cf
}

function Pack-Delta {
  $base = $BaseRef
  if (-not $base -and $cfg.delta -and $cfg.delta.baseRef) { $base = [string]$cfg.delta.baseRef }
  if (-not $base) { $base = "HEAD~1" }

  $head = $HeadRef
  if (-not $head -and $cfg.delta -and $cfg.delta.headRef) { $head = [string]$cfg.delta.headRef }
  if (-not $head) { $head = "HEAD" }

  $srcPrefix = ($srcRel -replace "\\", "/").TrimEnd("/")

  $gitExe = Resolve-Git $null
  $diffLines = & $gitExe -C $ProjectRoot diff --name-only $base $head 2>$null
  $diffFiles = @($diffLines | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne "" })

  $changedUnderSrc = @()
  foreach ($f in $diffFiles) {
    $fn = $f -replace "\\", "/"
    $p = "$srcPrefix/"
    if ($fn.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)) {
      $changedUnderSrc += $fn.Substring($p.Length)
    }
  }

  if ($changedUnderSrc.Count -eq 0) {
    throw "pack-delta: no changed files under src/ from git diff '$base'..'$head'."
  }

  # Delta src directory: minimal copy of changed objects (+ Configuration.xml/ConfigDumpInfo.xml).
  $useTemp = $true
  if ($cfg.delta -and $null -ne $cfg.delta.useTemp) { $useTemp = [bool]$cfg.delta.useTemp }
  $purge = $true
  if ($cfg.delta -and $null -ne $cfg.delta.purgeOnFinish) { $purge = [bool]$cfg.delta.purgeOnFinish }

  $deltaRoot = if ($useTemp) {
    Join-Path $env:TEMP ("1c-delta-src-" + ([guid]::NewGuid().ToString("N")))
  } else {
    Join-Path $ProjectRoot ".1c\\delta-src"
  }
  if (Test-Path -LiteralPath $deltaRoot) { Remove-Item -LiteralPath $deltaRoot -Recurse -Force -ErrorAction SilentlyContinue }
  New-Item -ItemType Directory -Force -Path $deltaRoot | Out-Null

  Copy-Item -LiteralPath (Join-Path $src "Configuration.xml") -Destination (Join-Path $deltaRoot "Configuration.xml") -Force
  Copy-Item -LiteralPath (Join-Path $src "ConfigDumpInfo.xml") -Destination (Join-Path $deltaRoot "ConfigDumpInfo.xml") -Force

  # Copy only object roots impacted by changed files.
  $copied = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($rel in $changedUnderSrc) {
    $relNorm = $rel -replace "\\", "/"
    $segments = $relNorm.Split("/")
    if ($segments.Length -lt 2) { continue }

    $category = $segments[0]
    $second = $segments[1]

    # Case: Category/ObjectName.xml (2 segments, .xml file)
    if ($segments.Length -eq 2 -and $second.ToLower().EndsWith(".xml")) {
      $objName = [System.IO.Path]::GetFileNameWithoutExtension($second)

      $objXml = Join-Path $src $category ($objName + ".xml")
      if (Test-Path -LiteralPath $objXml) {
        $dstFile = Join-Path $deltaRoot $category ($objName + ".xml")
        $dstDir = Split-Path -Parent $dstFile
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        Copy-Item -LiteralPath $objXml -Destination $dstFile -Force
      }

      $objDir = Join-Path $src $category $objName
      if (Test-Path -LiteralPath $objDir) {
        $dstDir = Join-Path $deltaRoot $category $objName
        if ($copied.Add($objDir)) {
          Copy-Item -LiteralPath $objDir -Destination $dstDir -Recurse -Force
        }
      }
      continue
    }

    # General case: Category/ObjectName/... -> copy object dir
    $objDir = Join-Path $src $category $second
    if (Test-Path -LiteralPath $objDir) {
      $dstDir = Join-Path $deltaRoot $category $second
      if ($copied.Add($objDir)) {
        Copy-Item -LiteralPath $objDir -Destination $dstDir -Recurse -Force
      }
    }
  }

  # Start from empty IB for delta (avoid mixing with previous packs).
  if (Test-Path -LiteralPath $dbPath) {
    Remove-Item -LiteralPath $dbPath -Recurse -Force -ErrorAction SilentlyContinue
  }

  Ensure-EmptyIb

  $savedSrc = $src
  $src = $deltaRoot
  Import-Xml
  Save-Cf
  $src = $savedSrc

  if ($useTemp -and $purge -and (Test-Path -LiteralPath $deltaRoot)) {
    Remove-Item -LiteralPath $deltaRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

switch ($Action) {
  "ensure-ib" { Ensure-EmptyIb }
  "import" { Ensure-EmptyIb; Import-Xml }
  "save-cf" {
    if (-not (Test-FileIbExists $dbPath)) { throw "IB not found: $dbPath" }
    Save-Cf
  }
  "pack" { Pack-All }
  "pack-delta" { Pack-Delta }
}

Write-Host "OK action=$Action"
