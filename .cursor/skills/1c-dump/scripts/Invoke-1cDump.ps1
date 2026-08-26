<#
.SYNOPSIS
  Facade: dump/load XML of the main configuration via tools.preferredDump (ibcmd|agent).
#>
[CmdletBinding()]
param(
  [ValidateSet("dump-full", "dump-update", "dump-objects", "load-changed", "load-files", "ping")]
  [string]$Action = "dump-full",

  [string]$ProjectRoot = (Get-Location).Path,
  [string]$OutDir = "",
  [string]$ListFile = "",
  [string]$Objects = "",
  [string]$BaseRef = "",
  [string]$HeadRef = "",
  [switch]$WipeOutDir,
  [switch]$NoStaging,
  [ValidateSet("", "ibcmd", "agent")]
  [string]$Tool = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "..\..\1c-runtime\scripts\Common-Project.ps1")

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfgPath = Join-Path $ProjectRoot ".1c\project.json"
if (-not (Test-Path -LiteralPath $cfgPath)) {
  throw "Missing $cfgPath - copy .1c/project.json.example -> .1c/project.json."
}
$Cfg = Merge-Config (Read-JsonFile $cfgPath) (Read-JsonFile (Join-Path $ProjectRoot ".1c\project.local.json"))

$preferred = "ibcmd"
if ($Cfg.tools -and $Cfg.tools.preferredDump) {
  $preferred = ([string]$Cfg.tools.preferredDump).Trim().ToLowerInvariant()
}
if ($Tool) { $preferred = $Tool.ToLowerInvariant() }
if ($preferred -ne "ibcmd" -and $preferred -ne "agent") {
  throw "tools.preferredDump must be ibcmd or agent (got: $preferred)"
}

$skillsRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$ibcmdDump = Join-Path $skillsRoot "1c-ibcmd-pack\scripts\Invoke-1cIbcmdDump.ps1"
$agentDump = Join-Path $skillsRoot "1c-designer-agent\scripts\Invoke-1cDesignerAgent.ps1"
if (-not (Test-Path -LiteralPath $ibcmdDump)) { throw "Missing $ibcmdDump" }
if (-not (Test-Path -LiteralPath $agentDump)) { throw "Missing $agentDump" }

Write-Host "1c-dump tool=$preferred action=$Action"

if ($preferred -eq "ibcmd") {
  $ibAction = $Action
  if ($Action -eq "load-changed") { $ibAction = "load-files" }
  $params = @{
    Action = $ibAction
    ProjectRoot = $ProjectRoot
  }
  if ($OutDir) { $params.OutDir = $OutDir }
  if ($ListFile) { $params.ListFile = $ListFile }
  if ($Objects) { $params.Objects = $Objects }
  if ($WipeOutDir) { $params.WipeOutDir = $true }
  if ($NoStaging) { $params.NoStaging = $true }
  & $ibcmdDump @params
  exit $LASTEXITCODE
}

# agent
$agAction = $Action
if ($Action -eq "load-files") { $agAction = "load-changed" }
if ($WipeOutDir) {
  Write-Host "WARN: -WipeOutDir is ibcmd-only; designer-agent dump-full writes into src/ without wipe flag."
}
$params = @{
  Action = $agAction
  ProjectRoot = $ProjectRoot
}
if ($ListFile) { $params.ListFile = $ListFile }
if ($Objects) { $params.Objects = $Objects }
if ($BaseRef) { $params.BaseRef = $BaseRef }
if ($HeadRef) { $params.HeadRef = $HeadRef }
& $agentDump @params
exit $LASTEXITCODE