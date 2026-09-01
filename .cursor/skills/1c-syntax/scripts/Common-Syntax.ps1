# Shared helpers for 1C syntax-helper MCP (bsl-ctx).
# Home: 1c-syntax/scripts. ASCII only (PS 5.1 + UTF-8 BOM).

if ($script:CommonSyntaxLoaded) { return }
$script:CommonSyntaxLoaded = $true

$script:CommonSyntaxHome = $null
if ($MyInvocation.MyCommand.Path) {
  $script:CommonSyntaxHome = Split-Path -Parent $MyInvocation.MyCommand.Path
} elseif ($PSScriptRoot) {
  $script:CommonSyntaxHome = $PSScriptRoot
}

. (Join-Path $script:CommonSyntaxHome "..\..\1c-runtime\scripts\Common-Project.ps1")

$script:BslCtxSpec = "bsl-ctx==1.4.0"

function Get-BslCtxSpec { return $script:BslCtxSpec }

function Get-SyntaxDataDir {
  if ($env:BSL_CTX_DATA_DIR -and $env:BSL_CTX_DATA_DIR.Trim()) {
    return [string]$env:BSL_CTX_DATA_DIR.Trim()
  }
  return (Join-Path $env:LOCALAPPDATA "bsl-ctx")
}

function Read-SyntaxProjectCfg([string]$ProjectRoot) {
  $cfgPath = Join-Path $ProjectRoot ".1c\project.json"
  $localPath = Join-Path $ProjectRoot ".1c\project.local.json"
  return (Merge-Config (Read-JsonFile $cfgPath) (Read-JsonFile $localPath))
}

function Get-SyntaxPlatformVersion($Cfg) {
  if ($Cfg -and $Cfg.platformVersion) {
    $v = ([string]$Cfg.platformVersion).Trim()
    if ($v) { return $v }
  }
  return $null
}

function Resolve-SyntaxBinDir($Cfg) {
  $explicit = ""
  if ($Cfg -and $Cfg.designer) { $explicit = [string]$Cfg.designer }
  $ver = Get-SyntaxPlatformVersion $Cfg
  $designer = Resolve-Designer $explicit $ver
  return (Split-Path -Parent $designer)
}

function Test-SyntaxHbk([string]$BinDir) {
  $hbk = Join-Path $BinDir "shcntx_ru.hbk"
  return (Test-Path -LiteralPath $hbk)
}

function Get-SyntaxDbPath([string]$PlatformVersion) {
  if (-not $PlatformVersion) { return $null }
  return (Join-Path (Get-SyntaxDataDir) ("bsl-context-{0}.sqlite" -f $PlatformVersion))
}

function Find-SyntaxDb([string]$PlatformVersion) {
  $exact = Get-SyntaxDbPath $PlatformVersion
  if ($exact -and (Test-Path -LiteralPath $exact)) { return $exact }
  $dir = Get-SyntaxDataDir
  if (-not (Test-Path -LiteralPath $dir)) { return $null }
  $found = @(Get-ChildItem -LiteralPath $dir -Filter "bsl-context-*.sqlite" -File -EA SilentlyContinue |
    Sort-Object Name -Descending)
  if ($PlatformVersion) {
    $match = $found | Where-Object { $_.Name -like ("bsl-context-{0}*.sqlite" -f $PlatformVersion) } | Select-Object -First 1
    if ($match) { return $match.FullName }
  }
  if ($found.Count -eq 1) { return $found[0].FullName }
  return $null
}

function Convert-CompatToTarget([string]$Raw) {
  if (-not $Raw) { return $null }
  $s = $Raw.Trim()
  if ($s -match '^Version8_(\d+)_(\d+)$') {
    return ("8.{0}.{1}" -f $Matches[1], $Matches[2])
  }
  if ($s -match '^Version8_(\d+)$') {
    return ("8.{0}" -f $Matches[1])
  }
  if ($s -eq "DontUse") { return $null }
  return $null
}

function Get-SyntaxCompatTarget([string]$ProjectRoot, $Cfg) {
  $srcRel = Get-SrcRel $Cfg
  $xmlPath = Join-Path $ProjectRoot (Join-Path $srcRel "Configuration.xml")
  if (-not (Test-Path -LiteralPath $xmlPath)) { return $null }
  try {
    [xml]$doc = Get-Content -LiteralPath $xmlPath -Encoding UTF8
  } catch {
    return $null
  }
  $node = $doc.SelectSingleNode("//*[local-name()='CompatibilityMode']")
  if (-not $node -or -not $node.InnerText) { return $null }
  return (Convert-CompatToTarget ([string]$node.InnerText))
}

function Find-UvxExe {
  foreach ($name in @("uvx", "uv")) {
    $cmd = Get-Command $name -EA SilentlyContinue
    if ($cmd -and $cmd.Source -and ($cmd.Source -notmatch 'WindowsApps\\')) {
      if ($name -eq "uvx") { return $cmd.Source }
      $sibling = Join-Path (Split-Path -Parent $cmd.Source) "uvx.exe"
      if (Test-Path -LiteralPath $sibling) { return $sibling }
    }
  }
  foreach ($c in @(
      (Join-Path $env:USERPROFILE ".local\bin\uvx.exe"),
      (Join-Path $env:USERPROFILE ".cargo\bin\uvx.exe"),
      (Join-Path $env:LOCALAPPDATA "Programs\uv\uvx.exe")
    )) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  return $null
}

function Find-SyntaxPython {
  $candidates = [System.Collections.Generic.List[string]]::new()
  foreach ($name in @("python", "python3")) {
    $cmd = Get-Command $name -EA SilentlyContinue
    if ($cmd -and $cmd.Source -and ($cmd.Source -notmatch 'WindowsApps\\python')) {
      [void]$candidates.Add($cmd.Source)
    }
  }
  foreach ($c in @(
      "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
      "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
      "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
      "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe"
    )) {
    if (Test-Path -LiteralPath $c) { [void]$candidates.Add($c) }
  }
  foreach ($p in $candidates) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    & $p --version 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return $p }
  }
  return $null
}

function Write-SyntaxLog([string]$Message) {
  [Console]::Error.WriteLine($Message)
}

function Test-SyntaxDbOk([string]$DbPath, [string]$Uvx, [string]$Spec) {
  if (-not $DbPath -or -not (Test-Path -LiteralPath $DbPath)) { return $false }
  $len = (Get-Item -LiteralPath $DbPath).Length
  if ($len -lt 1MB) { return $false }
  $args = @("--from", $Spec, "bsl-ctx", "doctor", "--db", $DbPath)
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $Uvx @args 1>$null 2>$null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  } finally {
    $ErrorActionPreference = $prev
  }
}

function Set-BslCtxUtf8Env {
  $env:PYTHONUTF8 = "1"
  $env:PYTHONIOENCODING = "utf-8"
  $env:PYTHONLEGACYWINDOWSSTDIO = "0"
  $env:NO_COLOR = "1"
  try { chcp 65001 | Out-Null } catch { }
  try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
    [Console]::InputEncoding = New-Object System.Text.UTF8Encoding $false
  } catch { }
}

function Get-PseudoTypesSeedPath {
  return (Join-Path $script:CommonSyntaxHome "..\config\pseudo_types.yaml")
}

function Get-PseudoTypesWorkDir {
  $d = Join-Path $env:LOCALAPPDATA "1c-agent-designer"
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}

function Get-PseudoTypesWorkPath {
  return (Join-Path (Get-PseudoTypesWorkDir) "bsl-ctx-pseudo_types.yaml")
}

function Get-PseudoTypesExtraPath {
  return (Join-Path (Get-PseudoTypesWorkDir) "bsl-ctx-pseudo_extra.txt")
}

function Initialize-PseudoTypesFile {
  $seed = Get-PseudoTypesSeedPath
  $work = Get-PseudoTypesWorkPath
  if (-not (Test-Path -LiteralPath $seed)) {
    throw "Missing seed yaml: $seed"
  }
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $text = [IO.File]::ReadAllText($seed, $utf8)
  $extraPath = Get-PseudoTypesExtraPath
  if (Test-Path -LiteralPath $extraPath) {
    $extras = [IO.File]::ReadAllLines($extraPath, $utf8)
    foreach ($name in $extras) {
      $n = ([string]$name).Trim()
      if (-not $n) { continue }
      $text += ("`nnot_a_type:`n  - {0}`n" -f $n)
    }
  }
  [IO.File]::WriteAllText($work, $text, $utf8)
  $env:BSL_CTX_PSEUDO_TYPES = $work
  return $work
}

function Add-PseudoTypeName([string]$Name) {
  $n = $Name.Trim()
  if (-not $n) { return }
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $extraPath = Get-PseudoTypesExtraPath
  $known = @()
  if (Test-Path -LiteralPath $extraPath) {
    $known = @([IO.File]::ReadAllLines($extraPath, $utf8))
  }
  foreach ($k in $known) {
    if (([string]$k).Trim() -eq $n) { return }
  }
  [IO.File]::AppendAllText($extraPath, ($n + "`n"), $utf8)
  Initialize-PseudoTypesFile | Out-Null
}

function Get-UnknownTypeFromBslOutput([string[]]$Lines) {
  foreach ($line in $Lines) {
    if ($null -eq $line) { continue }
    $s = [string]$line
    # bsl-ctx: "...: 'TypeName' (... 1): path.html"
    if ($s -match ":\s*'([^']+)'\s*\([^)]*1\)") {
      return $Matches[1]
    }
  }
  return $null
}
