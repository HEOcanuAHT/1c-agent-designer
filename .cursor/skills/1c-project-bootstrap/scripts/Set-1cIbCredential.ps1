#Requires -Version 5.1
<#
.SYNOPSIS
  Save 1C IB username/password into Windows Credential Manager (interactive).
.EXAMPLE
  .\Set-1cIbCredential.ps1 -ProjectRoot .
  .\Set-1cIbCredential.ps1 -Target "1c-ib/my-base" -User "Ivanov"
#>
[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$Target = "",
  [string]$User = "",
  [string]$Password = ""
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
. (Join-Path $here "1c-WindowsCredential.ps1")

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfgPath = Join-Path $ProjectRoot ".1c\project.json"
$localPath = Join-Path $ProjectRoot ".1c\project.local.json"
$cfg = $null
if (Test-Path -LiteralPath $cfgPath) {
  $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if (Test-Path -LiteralPath $localPath) {
    $local = Get-Content -LiteralPath $localPath -Raw -Encoding UTF8 | ConvertFrom-Json
    # shallow overlay auth
    if ($local.auth) {
      if (-not $cfg.auth) { $cfg | Add-Member -NotePropertyName auth -NotePropertyValue $local.auth -Force }
      else {
        foreach ($p in $local.auth.PSObject.Properties) {
          $cfg.auth | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
        }
      }
    }
  }
}

if (-not $Target) {
  $Target = Get-1cDefaultCredentialTarget -ProjectRoot $ProjectRoot -Cfg $cfg
}

Write-Host "Windows Credential Manager"
Write-Host "target: $Target"
Write-Host "(password is not echoed)"

if (-not $User) {
  $User = Read-Host "IB user"
}
if (-not $User) { throw "User is empty" }

if (-not $Password) {
  $sec = Read-Host "IB password" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try {
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

Set-1cWindowsCredential -Target $Target -User $User -Password $Password
Write-Host "OK saved credential target=$Target user=$User"
Write-Host "Put into .1c/project.json or project.local.json:"
Write-Host @"
  "auth": {
    "required": true,
    "credentialTarget": "$Target"
  }
"@
Write-Host "Do not store password in JSON when using Credential Manager."
