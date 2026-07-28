#Requires -Version 5.1
<#
.SYNOPSIS
  Move IB auth from plaintext project.local.json into Windows Credential Manager.
.NOTES
  Does not print the password. Removes auth.password from local JSON after success.
#>
[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$Target = "",
  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
. (Join-Path $here "1c-WindowsCredential.ps1")

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$localPath = Join-Path $ProjectRoot ".1c\project.local.json"
if (-not (Test-Path -LiteralPath $localPath)) {
  Write-Host "SKIP: no .1c/project.local.json"
  exit 0
}

$local = Get-Content -LiteralPath $localPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $local.auth) {
  Write-Host "SKIP: no auth block in project.local.json"
  exit 0
}

$pwd = $null
if ($local.auth.PSObject.Properties['password'] -and $null -ne $local.auth.password) {
  $pwd = [string]$local.auth.password
}
$user = $null
if ($local.auth.PSObject.Properties['user'] -and $null -ne $local.auth.user) {
  $user = [string]$local.auth.user
}

$hasCredTarget = $local.auth.PSObject.Properties['credentialTarget'] -and [string]$local.auth.credentialTarget -ne ""

if (-not $pwd -or $pwd -eq "") {
  if ($hasCredTarget) {
    Write-Host "OK: credentialTarget already set, no plaintext password"
    exit 0
  }
  Write-Host "SKIP: no auth.password to migrate (nothing to do)"
  exit 0
}

if (-not $user -or $user -eq "") {
  throw "auth.password is set but auth.user is empty - fix project.local.json first"
}

$cfgPath = Join-Path $ProjectRoot ".1c\project.json"
$cfg = $null
if (Test-Path -LiteralPath $cfgPath) {
  $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

if (-not $Target) {
  if ($hasCredTarget) { $Target = [string]$local.auth.credentialTarget }
  else { $Target = Get-1cDefaultCredentialTarget -ProjectRoot $ProjectRoot -Cfg $cfg }
}

Write-Host "Migrate IB auth to Windows Credential Manager"
Write-Host "target: $Target"
Write-Host "user:   $user"
if ($WhatIf) {
  Write-Host "WHATIF: would save credential and remove auth.password from project.local.json"
  exit 0
}

Set-1cWindowsCredential -Target $Target -User $user -Password $pwd

$local.auth | Add-Member -NotePropertyName required -NotePropertyValue $true -Force
$local.auth | Add-Member -NotePropertyName credentialTarget -NotePropertyValue $Target -Force
$local.auth.PSObject.Properties.Remove('password')
# user in JSON optional after migration; remove to avoid drift
if ($local.auth.PSObject.Properties['user']) {
  $local.auth.PSObject.Properties.Remove('user')
}

$json = ($local | ConvertTo-Json -Depth 10)
[IO.File]::WriteAllText($localPath, $json + "`n", (New-Object Text.UTF8Encoding $false))
Write-Host "OK: credential saved; auth.password removed from project.local.json"
Write-Host "Verify: dump/ping with ibcmd or designer-agent"
