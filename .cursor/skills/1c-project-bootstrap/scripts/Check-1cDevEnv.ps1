#Requires -Version 5.1
param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectRoot,
  [switch]$Json
)

$ErrorActionPreference = "Continue"
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

function Find-1cPlatforms {
  $roots = @(
    "${env:ProgramFiles}\1cv8",
    "${env:ProgramFiles(x86)}\1cv8"
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
  $found = @()
  foreach ($root in $roots) {
    Get-ChildItem -LiteralPath $root -Directory -EA SilentlyContinue | ForEach-Object {
      $exe = Join-Path $_.FullName "bin\1cv8.exe"
      if (Test-Path -LiteralPath $exe) {
        $found += [pscustomobject]@{ Version = $_.Name; Designer = $exe }
      }
    }
  }
  return @($found | Sort-Object Version -Descending)
}

function Find-Python {
  $candidates = @()
  $venvPy = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
  if (Test-Path -LiteralPath $venvPy) { $candidates += $venvPy }
  $candidates += @(
    "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python39\python.exe"
  )
  # uv-managed installs (shim in ~/.local/bin may fail without full env)
  $uvRoot = Join-Path $env:APPDATA "uv\python"
  if (Test-Path -LiteralPath $uvRoot) {
    Get-ChildItem -LiteralPath $uvRoot -Directory -EA SilentlyContinue |
      Sort-Object Name -Descending |
      ForEach-Object {
        $exe = Join-Path $_.FullName "python.exe"
        if (Test-Path -LiteralPath $exe) { $candidates += $exe }
      }
  }
  foreach ($p in $candidates) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    & $p --version 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return $p }
  }
  foreach ($name in @("python", "python3")) {
    $cmd = Get-Command $name -EA SilentlyContinue
    if ($cmd -and $cmd.Source -and ($cmd.Source -notmatch 'WindowsApps\\python')) {
      & $cmd.Source --version 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) { return $cmd.Source }
    }
  }
  return $null
}

function Test-Paramiko([string]$PythonExe) {
  if (-not $PythonExe) { return $false }
  $code = "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('paramiko') else 1)"
  & $PythonExe -c $code 2>$null | Out-Null
  return ($LASTEXITCODE -eq 0)
}

function Find-Plink {
  foreach ($c in @(
      "C:\Program Files\PuTTY\plink.exe",
      "C:\Program Files (x86)\PuTTY\plink.exe"
    )) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  $cmd = Get-Command plink -EA SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Find-Ibcmd([string]$PlatformVersion) {
  if ($PlatformVersion) {
    foreach ($root in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)})) {
      if (-not $root) { continue }
      $c = Join-Path $root "1cv8\$PlatformVersion\bin\ibcmd.exe"
      if (Test-Path -LiteralPath $c) { return $c }
    }
  }
  foreach ($root in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)})) {
    if (-not $root) { continue }
    $base = Join-Path $root "1cv8"
    if (-not (Test-Path -LiteralPath $base)) { continue }
    $found = Get-ChildItem $base -Recurse -Filter "ibcmd.exe" -EA SilentlyContinue |
      Sort-Object FullName -Descending |
      Select-Object -First 1 -ExpandProperty FullName
    if ($found) { return $found }
  }
  $cmd = Get-Command ibcmd -EA SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

# Force arrays: PowerShell unwraps single-element returns from functions.
$platforms = @(Find-1cPlatforms)
$python = Find-Python
$paramiko = Test-Paramiko $python
$plink = Find-Plink
$latestVer = if ($platforms.Count) { $platforms[0].Version } else { $null }
$ibcmd = Find-Ibcmd $latestVer
$gitCmd = Get-Command git -EA SilentlyContinue
$projectJson = Join-Path $ProjectRoot ".1c\project.json"
$projectLocal = Join-Path $ProjectRoot ".1c\project.local.json"
$exampleJson = Join-Path $ProjectRoot ".1c\project.json.example"

$report = [ordered]@{
  projectRoot        = $ProjectRoot
  platformCount      = $platforms.Count
  platforms          = @($platforms | ForEach-Object { $_.Version })
  latestPlatform     = $latestVer
  designer           = if ($platforms.Count) { $platforms[0].Designer } else { $null }
  ibcmd              = $ibcmd
  python             = $python
  paramiko           = [bool]$paramiko
  plink              = $plink
  git                = if ($gitCmd) { $gitCmd.Source } else { $null }
  hasProjectJson     = (Test-Path -LiteralPath $projectJson)
  hasProjectLocal    = (Test-Path -LiteralPath $projectLocal)
  hasProjectExample  = (Test-Path -LiteralPath $exampleJson)
  readyForAgentSsh   = [bool](($python -and $paramiko) -or $plink)
  readyForDesigner   = [bool]($platforms.Count -gt 0)
  readyForIbcmdPack  = [bool]$ibcmd
  missing            = @()
  hints              = @()
}

if (-not $report.readyForDesigner) {
  $report.missing += "1c-platform"
  $report.hints += "Install 1C:Enterprise platform (Designer). Set platformVersion in .1c/project.json."
}
if (-not $python) {
  $report.missing += "python"
  $report.hints += "Install Python 3.10+ from python.org (enable PATH), or: uv venv .venv"
} elseif (-not $paramiko) {
  if ($plink) {
    $report.hints += "paramiko optional (plink covers agent SSH). For Python SSH: uv pip install --python .venv\Scripts\python.exe paramiko"
  } else {
    $report.missing += "paramiko"
    $report.hints += "Run: uv venv .venv; uv pip install --python .venv\Scripts\python.exe paramiko"
  }
}
if (-not $plink -and -not ($python -and $paramiko)) {
  $report.hints += "Optional fallback: install PuTTY (plink.exe) or fix Python+paramiko."
}
if (-not $report.git) {
  $report.missing += "git"
  $report.hints += "Install Git for load-changed by diff."
}
if (-not $ibcmd) {
  $report.hints += "Optional: install ibcmd (same platform build) for pack XML→.cf and faster export/import."
}
if (-not $report.hasProjectJson) {
  $report.missing += "project.json"
  $report.hints += "Copy .1c/project.json.example -> .1c/project.json and fill infobase + platformVersion."
}
if (-not $report.hasProjectLocal) {
  $report.missing += "project.local.json"
  $report.hints += "Copy .1c/project.local.json.example -> .1c/project.local.json (auth only; do not commit)."
}

if ($Json) {
  $report | ConvertTo-Json -Depth 5
  exit 0
}

Write-Host "=== 1C project env check ==="
Write-Host "root: $($report.projectRoot)"
Write-Host ("platform: " + $(if ($report.latestPlatform) { "$($report.latestPlatform) ($($report.designer))" } else { "MISSING" }))
Write-Host ("ibcmd:    " + $(if ($report.ibcmd) { $report.ibcmd } else { "(optional, for pack)" }))
Write-Host ("python:   " + $(if ($report.python) { $report.python } else { "MISSING" }))
Write-Host ("paramiko: " + $(if ($report.paramiko) { "OK" } else { "MISSING" }))
Write-Host ("plink:    " + $(if ($report.plink) { $report.plink } else { "(optional)" }))
Write-Host ("git:      " + $(if ($report.git) { "OK" } else { "MISSING" }))
Write-Host ("project.json:      " + $(if ($report.hasProjectJson) { "OK" } else { "MISSING" }))
Write-Host ("project.local.json:" + $(if ($report.hasProjectLocal) { "OK" } else { "MISSING" }))
Write-Host ("agent SSH ready:   " + $(if ($report.readyForAgentSsh) { "YES" } else { "NO" }))
Write-Host ("ibcmd pack ready:  " + $(if ($report.readyForIbcmdPack) { "YES" } else { "NO" }))
if ($report.missing.Count) {
  Write-Host "MISSING: $($report.missing -join ', ')"
  foreach ($h in $report.hints) { Write-Host " - $h" }
  exit 1
}
Write-Host "OK: environment looks ready for designer-agent"
exit 0
