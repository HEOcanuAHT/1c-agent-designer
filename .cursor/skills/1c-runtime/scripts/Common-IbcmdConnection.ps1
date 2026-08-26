# Shared ibcmd connection args (file / DBMS) and 1C-IB auth.
# Home: 1c-runtime/scripts. Dot-source from Invoke-1cIbcmdDump / Common-ServiceIb.
# Pulls Common-Project.ps1. SQL auth != 1C IB auth (rule 1c-ibcmd-auth).

$script:CommonIbcmdConnectionHome = $null
if ($MyInvocation.MyCommand.Path) {
  $script:CommonIbcmdConnectionHome = Split-Path -Parent $MyInvocation.MyCommand.Path
} elseif ($PSScriptRoot) {
  $script:CommonIbcmdConnectionHome = $PSScriptRoot
}

. (Join-Path $script:CommonIbcmdConnectionHome "Common-Project.ps1")

if ($script:CommonIbcmdConnectionLoaded) { return }
$script:CommonIbcmdConnectionLoaded = $true

function Get-IbcmdCredHelperPath {
  return (Get-1cCredHelperPath)
}

function Get-IbAuthArgs($Cfg, [string]$ProjectRoot = "") {
  Import-1cCredHelper
  $auth = Resolve-1cIbAuth -Cfg $Cfg -ProjectRoot $ProjectRoot
  if (-not $auth.Required) {
    Write-Host "ibcmd 1C-IB auth: none (auth.required=false)"
    return @()
  }
  # CredMgr/auth -> ONLY 1C IB --user/--password. Never SQL (--db-user).
  Write-Host "ibcmd 1C-IB auth source=$($auth.Source) (--user only; NOT SQL)"
  $a = @("--user=$($auth.User)")
  if ($null -ne $auth.Password -and $auth.Password -ne "") { $a += "--password=$($auth.Password)" }
  return $a
}

function Test-DbmsWindowsAuth($Dbms) {
  # Default: Windows/Integrated to SQL. Do not use [bool]$string - [bool]"false" is $true in PS.
  if ($null -eq $Dbms -or $null -eq $Dbms.windowsAuth) { return $true }
  $v = $Dbms.windowsAuth
  if ($v -is [bool]) { return $v }
  $s = ([string]$v).Trim().ToLowerInvariant()
  if ($s -in @("0", "false", "no", "off")) { return $false }
  if ($s -in @("1", "true", "yes", "on")) { return $true }
  return $true
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
      throw "infobase.type=$type but infobase.dbms is missing (ibcmd needs direct SQL). Fill infobase.dbms { kind, server, name } or use designer-agent (tools.preferredDump=agent)."
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

    $winAuth = Test-DbmsWindowsAuth $dbms
    if ($winAuth) {
      return @{ Mode = "dbms"; Args = $args; Label = "$kind/$server/$name"; SqlAuth = "windows (no --db-user; NOT auth.credentialTarget)" }
    }

    # SQL login (not 1C IB). Prefer dbms.credentialTarget, then env, then plaintext dbms.user/password.
    $dbUser = $env:1C_DB_USER
    $dbPwd = $env:1C_DB_PASSWORD
    $sqlSource = "env"
    if ($dbms.credentialTarget) {
      Import-1cCredHelper
      $stored = Get-1cWindowsCredential -Target ([string]$dbms.credentialTarget)
      if ($stored) {
        $dbUser = $stored.User
        $dbPwd = $stored.Password
        $sqlSource = "credmgr:$($dbms.credentialTarget)"
      }
    }
    if ($dbms.user) { $dbUser = [string]$dbms.user; $sqlSource = "json" }
    if ($dbms.password) { $dbPwd = [string]$dbms.password; if ($sqlSource -eq "env") { $sqlSource = "json" } }
    if (-not $dbUser) {
      throw "infobase.dbms.windowsAuth=false but SQL user missing (dbms.credentialTarget / dbms.user / 1C_DB_USER). Do NOT use auth.credentialTarget - that is 1C IB only."
    }
    $args += "--db-user=$dbUser"
    if ($null -ne $dbPwd -and $dbPwd -ne "") { $args += "--db-pwd=$dbPwd" }
    return @{ Mode = "dbms"; Args = $args; Label = "$kind/$server/$name"; SqlAuth = "sql-login source=$sqlSource" }
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

function Get-IbcmdFailureHint([string]$Combined, [int]$ExitCode) {
  if (-not $Combined) { return $null }
  $reLock = '\u0438\u0441\u043a\u043b\u044e\u0447\u0438\u0442\u0435\u043b\u044c\u043d\w* \u0431\u043b\u043e\u043a\u0438\u0440\u043e\u0432\u043a|exclusive lock'
  $reAuth = [string]::Concat(
    '\u0418\u0434\u0435\u043d\u0442\u0438\u0444\u0438\u043a\u0430\u0446\u0438\u044f \u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044f \u043d\u0435 \u0432\u044b\u043f\u043e\u043b\u043d\u0435\u043d\u0430', '|',
    '\u0442\u0440\u0435\u0431\u0443\u0435\u0442\u0441\u044f \u0430\u0443\u0442\u0435\u043d\u0442\u0438\u0444\u0438\u043a\u0430\u0446\u0438\u044f', '|',
    '\u0418\u043c\u044f \u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044f\s*:', '|',
    '\u041f\u0430\u0440\u043e\u043b\u044c \u0434\u043b\u044f\s+.'
  )
  if ([regex]::IsMatch($Combined, $reLock)) {
    return "ibcmd: exclusive lock on file IB - Configurator (or another process) holds this base. Close Designer on this IB and retry. exit=$ExitCode"
  }
  if ([regex]::IsMatch($Combined, $reAuth)) {
    return "ibcmd: IB auth failed (wrong/missing user or password). Fix auth in project.local.json; if IB has no users set auth.required=false. exit=$ExitCode"
  }
  return $null
}
