# Shared project.json merge, 1cv8/ibcmd paths, designer IB args, 1C-IB auth helpers.
# Home: 1c-runtime/scripts. Dot-source from Common-IbcmdConnection / designer-agent / template-sync.
# SQL auth != 1C IB auth (rule 1c-ibcmd-auth).

if ($script:CommonProjectLoaded) { return }
$script:CommonProjectLoaded = $true

$script:CommonProjectHome = $null
if ($MyInvocation.MyCommand.Path) {
  $script:CommonProjectHome = Split-Path -Parent $MyInvocation.MyCommand.Path
} elseif ($PSScriptRoot) {
  $script:CommonProjectHome = $PSScriptRoot
}

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

function Get-SrcRel($Cfg) {
  if ($Cfg.src) { return ([string]$Cfg.src -replace "\\", "/").TrimEnd("/") }
  return "src"
}

function Get-1cCredHelperPath {
  return (Join-Path $script:CommonProjectHome "..\..\1c-project-bootstrap\scripts\1c-WindowsCredential.ps1")
}

function Import-1cCredHelper {
  # Prefer script-level load below. This is a safety net if someone dotsources only the middle of the file.
  if (Get-Command Resolve-1cIbAuth -ErrorAction SilentlyContinue) { return }
  throw "Resolve-1cIbAuth missing - re-dot-source Common-Project.ps1 (credential helper loads at script scope)."
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

function Get-DesignerAuthArgs($Auth) {
  if (-not $Auth -or -not $Auth.Required) { return @() }
  if (-not $Auth.User) { return @() }
  return @("/N$($Auth.User)", "/P$($Auth.Password)")
}

# CredMgr helpers must load at SCRIPT scope (dotsource inside a function stays local in PS 5.1).
if (-not (Get-Command Resolve-1cIbAuth -ErrorAction SilentlyContinue)) {
  $__credPath = Get-1cCredHelperPath
  if (-not (Test-Path -LiteralPath $__credPath)) { throw "Missing credential helper: $__credPath" }
  . $__credPath
}
