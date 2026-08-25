#Requires -Version 5.1
param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectRoot,
  [string]$PluginRoot = "",
  [switch]$Force
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Get-1cPluginRoot.ps1")

$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath $ProjectRoot)) {
  New-Item -ItemType Directory -Path $ProjectRoot -Force | Out-Null
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

if (-not $PluginRoot) {
  $PluginRoot = Get-1cPluginRoot -ProjectRoot $ProjectRoot
}

$relFiles = @(
  ".1c/project.json.example",
  ".1c/project.local.json.example",
  ".1c/README.md",
  ".1c/template-manifest.json",
  "ext/README.md",
  "cfe/README.md",
  "docs/WORKFLOW.md",
  "docs/INITIAL_DUMP.md",
  "docs/TEMPLATE_UPGRADE.md",
  "docs/ATTRIBUTION.md",
  "AGENTS.md",
  ".gitlab/merge_request_templates/Default.md"
)

function Copy-RelFile([string]$Rel) {
  $src = Join-Path $PluginRoot ($Rel -replace "/", "\")
  $dst = Join-Path $ProjectRoot ($Rel -replace "/", "\")
  if (-not (Test-Path -LiteralPath $src)) {
    Write-Host "MISSING $Rel"
    return
  }
  if ((Test-Path -LiteralPath $dst) -and -not $Force) {
    Write-Host "SKIP $Rel"
    return
  }
  $dir = Split-Path -Parent $dst
  if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  Copy-Item -LiteralPath $src -Destination $dst -Force
  Write-Host "COPY $Rel"
}

foreach ($rel in $relFiles) { Copy-RelFile $rel }

$srcDir = Join-Path $ProjectRoot "src"
if (-not (Test-Path -LiteralPath $srcDir)) {
  New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
  Write-Host "MKDIR src"
}

$giSrc = Join-Path $PSScriptRoot "..\scaffold\gitignore"
$giDst = Join-Path $ProjectRoot ".gitignore"
if (Test-Path -LiteralPath $giSrc) {
  if ((Test-Path -LiteralPath $giDst) -and -not $Force) {
    Write-Host "SKIP .gitignore"
  } else {
    Copy-Item -LiteralPath $giSrc -Destination $giDst -Force
    Write-Host "COPY .gitignore"
  }
}

Write-Host "plugin=$PluginRoot"
Write-Host "project=$ProjectRoot"
