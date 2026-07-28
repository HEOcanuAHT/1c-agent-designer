#Requires -Version 5.1
<#
.SYNOPSIS
  Read/write 1C IB login via Windows Credential Manager (Generic credentials).
.NOTES
  Target example: 1c-ib/my-config
  Never Write-Host the password.
#>

$script:CredTypeLoaded = $false

function Ensure-1cCredNative {
  if ($script:CredTypeLoaded) { return }
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class OneCWinCred {
  public const uint CRED_TYPE_GENERIC = 1;
  public const uint CRED_PERSIST_LOCAL_MACHINE = 2;

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct CREDENTIAL {
    public uint Flags;
    public uint Type;
    public string TargetName;
    public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public uint CredentialBlobSize;
    public IntPtr CredentialBlob;
    public uint Persist;
    public uint AttributeCount;
    public IntPtr Attributes;
    public string TargetAlias;
    public string UserName;
  }

  [DllImport("Advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool CredWrite(ref CREDENTIAL userCredential, uint flags);

  [DllImport("Advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool CredRead(string target, uint type, int reservedFlag, out IntPtr credentialPtr);

  [DllImport("Advapi32.dll", SetLastError = true)]
  public static extern bool CredFree(IntPtr cred);

  [DllImport("Advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool CredDelete(string target, uint type, int flags);
}
"@
  $script:CredTypeLoaded = $true
}

function Get-1cDefaultCredentialTarget {
  param([string]$ProjectRoot, $Cfg)
  if ($Cfg -and $Cfg.auth -and $Cfg.auth.credentialTarget) {
    return [string]$Cfg.auth.credentialTarget
  }
  $name = "project"
  if ($Cfg -and $Cfg.name) { $name = [string]$Cfg.name }
  elseif ($ProjectRoot) { $name = [IO.Path]::GetFileName($ProjectRoot.TrimEnd('\', '/')) }
  $safe = ($name -replace '[^\w\.\-]+', '-').Trim('-')
  if (-not $safe) { $safe = "project" }
  return "1c-ib/$safe"
}

function Set-1cWindowsCredential {
  param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$Password
  )
  Ensure-1cCredNative
  $bytes = [Text.Encoding]::Unicode.GetBytes($Password)
  $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal($bytes.Length)
  try {
    [Runtime.InteropServices.Marshal]::Copy($bytes, 0, $ptr, $bytes.Length)
    $cred = New-Object OneCWinCred+CREDENTIAL
    $cred.Type = [OneCWinCred]::CRED_TYPE_GENERIC
    $cred.TargetName = $Target
    $cred.UserName = $User
    $cred.CredentialBlob = $ptr
    $cred.CredentialBlobSize = [uint32]$bytes.Length
    $cred.Persist = [OneCWinCred]::CRED_PERSIST_LOCAL_MACHINE
    $cred.AttributeCount = 0
    $ok = [OneCWinCred]::CredWrite([ref]$cred, 0)
    if (-not $ok) {
      throw "CredWrite failed for target='$Target' Win32=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
  } finally {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
  }
}

function Get-1cWindowsCredential {
  param([Parameter(Mandatory = $true)][string]$Target)
  Ensure-1cCredNative
  $credPtr = [IntPtr]::Zero
  $ok = [OneCWinCred]::CredRead($Target, [OneCWinCred]::CRED_TYPE_GENERIC, 0, [ref]$credPtr)
  if (-not $ok -or $credPtr -eq [IntPtr]::Zero) { return $null }
  try {
    $cred = [Runtime.InteropServices.Marshal]::PtrToStructure($credPtr, [type][OneCWinCred+CREDENTIAL])
    $pwd = ""
    if ($cred.CredentialBlobSize -gt 0 -and $cred.CredentialBlob -ne [IntPtr]::Zero) {
      $bytes = New-Object byte[] $cred.CredentialBlobSize
      [Runtime.InteropServices.Marshal]::Copy($cred.CredentialBlob, $bytes, 0, $cred.CredentialBlobSize)
      $pwd = [Text.Encoding]::Unicode.GetString($bytes)
      # CredMgr often stores null-terminated Unicode
      $pwd = $pwd.TrimEnd([char]0)
    }
    return @{ User = [string]$cred.UserName; Password = $pwd; Target = $Target }
  } finally {
    [void][OneCWinCred]::CredFree($credPtr)
  }
}

function Resolve-1cIbAuth {
  <#
    Priority: env → Windows Credential Manager (auth.credentialTarget) → auth.user/password in JSON.
  #>
  param($Cfg, [string]$ProjectRoot = "")
  $required = $true
  if ($Cfg.auth -and $null -ne $Cfg.auth.required) { $required = [bool]$Cfg.auth.required }

  $user = $env:1C_IB_USER
  $pwd = $env:1C_IB_PASSWORD
  $source = "env"

  $target = $null
  if ($Cfg.auth -and $Cfg.auth.credentialTarget) {
    $target = [string]$Cfg.auth.credentialTarget
  } elseif ($required) {
    $target = Get-1cDefaultCredentialTarget -ProjectRoot $ProjectRoot -Cfg $Cfg
  }

  if ((-not $user) -and $target) {
    $stored = Get-1cWindowsCredential -Target $target
    if ($stored) {
      $user = $stored.User
      $pwd = $stored.Password
      $source = "credmgr:$target"
    }
  }

  if ($Cfg.auth -and $Cfg.auth.user -and [string]$Cfg.auth.user -ne "") {
    if (-not $user) { $user = [string]$Cfg.auth.user; $source = "json" }
  }
  if ($Cfg.auth -and $null -ne $Cfg.auth.password -and [string]$Cfg.auth.password -ne "") {
    if ($null -eq $pwd -or $pwd -eq "") { $pwd = [string]$Cfg.auth.password; if ($source -eq "env") { $source = "json" } }
  }

  if ($null -eq $user) { $user = "" }
  if ($null -eq $pwd) { $pwd = "" }

  if ($required -and -not $user) {
    $hintTarget = if ($target) { $target } else { "1c-ib/<project>" }
    throw "IB auth required but no user. Set Windows Credential Manager target '$hintTarget' via Set-1cIbCredential.ps1, or 1C_IB_USER/1C_IB_PASSWORD, or auth.user in project.local.json."
  }

  return @{
    User              = $user
    Password          = $pwd
    Required          = $required
    Source            = $source
    CredentialTarget  = $target
  }
}
