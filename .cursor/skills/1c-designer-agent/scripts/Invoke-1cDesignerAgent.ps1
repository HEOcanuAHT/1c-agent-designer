<#
.SYNOPSIS
  1C dump/load via Designer batch (default) or AgentMode+plink (transport=agent).
#>
[CmdletBinding()]
param(
  [ValidateSet("start", "stop", "dump-full", "dump-update", "load-changed", "ping")]
  [string]$Action = "ping",
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$BaseRef = "",
  [string]$HeadRef = "",
  [switch]$NoAutoStart,
  [switch]$UseAgent,
  [switch]$ClearAgentPort,
  # Optional list of paths relative to src/ (one per line). Skips git diff when set.
  [string]$ListFile = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

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

function Resolve-Git {
  foreach ($c in @(
      "C:\\Program Files\\Git\\bin\\git.exe",
      "C:\\Program Files (x86)\\Git\\bin\\git.exe",
      "$env:LOCALAPPDATA\\Programs\\Git\\bin\\git.exe"
    )) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  $cmd = Get-Command git -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw "git.exe not found."
}

function Resolve-Plink {
  foreach ($c in @("C:\Program Files\PuTTY\plink.exe", "C:\Program Files (x86)\PuTTY\plink.exe")) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  $cmd = Get-Command plink -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Get-AgentAuth($Cfg) {
  $required = $true
  if ($Cfg.auth -and $null -ne $Cfg.auth.required) { $required = [bool]$Cfg.auth.required }
  $user = $env:1C_IB_USER
  $pwd = $env:1C_IB_PASSWORD
  if ($Cfg.auth -and $null -ne $Cfg.auth.user -and [string]$Cfg.auth.user -ne "") {
    $user = [string]$Cfg.auth.user
  }
  if ($Cfg.auth -and $null -ne $Cfg.auth.password) { $pwd = [string]$Cfg.auth.password }
  if ($null -eq $user) { $user = "" }
  if ($null -eq $pwd) { $pwd = "" }
  if ($required -and -not $user) {
    throw "Need auth.user in project.local.json or 1C_IB_USER (or set auth.required=false for empty IB)."
  }
  return @{ User = $user; Password = $pwd; Required = $required }
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

function Get-SrcRel($Cfg) {
  if ($Cfg.src) { return ([string]$Cfg.src -replace "\\", "/").TrimEnd("/") }
  return "src"
}

function Get-Transport($Cfg) {
  if ($UseAgent) { return "agent" }
  if ($Cfg.designerAgent -and $Cfg.designerAgent.transport) { return [string]$Cfg.designerAgent.transport }
  return "batch"
}

function Test-TcpOpen([string]$HostName, [int]$Port) {
  try {
    $client = New-Object System.Net.Sockets.TcpClient
    $iar = $client.BeginConnect($HostName, $Port, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne(800)
    if (-not $ok) { $client.Close(); return $false }
    $client.EndConnect($iar) | Out-Null
    $client.Close()
    return $true
  } catch { return $false }
}

function Clear-AgentPort([int]$Port) {
  $conns = @(Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue)
  foreach ($c in $conns) {
    $procId = $c.OwningProcess
    if ($procId -and $procId -gt 0) {
      Write-Host "Stopping process $procId on port $Port"
      Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
    }
  }
  Start-Sleep -Seconds 2
}

function Start-DesignerAgent($Cfg, [string]$DesignerPath, [string]$ProjectRoot) {
  $da = $Cfg.designerAgent
  $hostName = if ($da.host) { [string]$da.host } else { "127.0.0.1" }
  $port = if ($da.port) { [int]$da.port } else { 1543 }
  $listen = if ($da.listenAddress) { [string]$da.listenAddress } else { $hostName }

  if (Test-TcpOpen $hostName $port) {
    Write-Host "Agent already listening on ${hostName}:${port}"
    return
  }

  $baseDirRel = if ($da.baseDir) { [string]$da.baseDir } else { "." }
  $baseDir = if ([System.IO.Path]::IsPathRooted($baseDirRel)) { $baseDirRel } else { Join-Path $ProjectRoot $baseDirRel }
  $baseDir = (Resolve-Path -LiteralPath $baseDir).Path

  $ibArgs = Get-IbArgs $Cfg $ProjectRoot
  # Single argument string; quote only paths. Avoid Start-Process -ArgumentList array bugs.
  $ibPart = ""
  for ($i = 0; $i -lt $ibArgs.Count; $i += 2) {
    $key = $ibArgs[$i]
    $val = $ibArgs[$i + 1]
    $ibPart += " $key `"$val`""
  }
  $visiblePart = ""
  if ($da.visible -ne $false) { $visiblePart = " /Visible" }

  $baseDirArg = ($baseDir -replace '\\', '/')
  $ibPath = ($ibArgs[1] -replace '\\', '/')
  $argString = "DESIGNER $($ibArgs[0]) `"$ibPath`" /AgentMode /AgentPort $port /AgentListenAddress $listen /AgentSSHHostKeyAuto /AgentBaseDir $baseDirArg$visiblePart"
  Write-Host ">> $DesignerPath $argString"
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $DesignerPath
  $psi.Arguments = $argString
  $psi.WorkingDirectory = $ProjectRoot
  $psi.UseShellExecute = $false
  $proc = [System.Diagnostics.Process]::Start($psi)
  if ($null -eq $proc) { throw "Failed to start Designer agent process" }
  $pidFile = Join-Path $ProjectRoot ".1c\agent.pid"
  New-Item -ItemType Directory -Force -Path (Split-Path $pidFile) | Out-Null
  Set-Content -LiteralPath $pidFile -Value $proc.Id -Encoding ASCII

  $wait = 30
  if ($da.startupWaitSec) { $wait = [int]$da.startupWaitSec }
  $deadline = (Get-Date).AddSeconds($wait)
  while ((Get-Date) -lt $deadline) {
    if (Test-TcpOpen $hostName $port) {
      Write-Host "Agent started on ${hostName}:${port} baseDir=$baseDir pid=$($proc.Id)"
      return
    }
    if ($proc.HasExited) {
      throw "Designer agent process exited early code=$($proc.ExitCode) (IB locked by another Designer?)"
    }
    Start-Sleep -Milliseconds 400
  }
  throw "Designer agent did not open port ${hostName}:${port}"
}

function Stop-DesignerAgentAfterOp {
  param($Cfg, [string]$Label)
  if ((Get-Transport $Cfg) -ne "agent") { return }
  $da = $Cfg.designerAgent
  if ($da -and $null -ne $da.keepAlive -and [bool]$da.keepAlive) {
    Write-Host "keepAlive=true - agent left running after $Label"
    return
  }
  $hostName = if ($da -and $da.host) { [string]$da.host } else { "127.0.0.1" }
  $port = if ($da -and $da.port) { [int]$da.port } else { 1543 }
  $pidFile = Join-Path $ProjectRoot ".1c\agent.pid"

  # Prefer local process stop: second SSH session for "common shutdown" was hanging
  # up to ~120s after the agent already closed the transport.
  if (Test-Path -LiteralPath $pidFile) {
    $agentPid = 0
    [void][int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$agentPid)
    if ($agentPid -gt 0) {
      $alive = Get-Process -Id $agentPid -ErrorAction SilentlyContinue
      if ($alive) {
        Write-Host ("Stopping agent pid=" + $agentPid + " after " + $Label)
        Stop-Process -Id $agentPid -Force -ErrorAction SilentlyContinue
      }
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
  }

  $deadline = (Get-Date).AddSeconds(5)
  while ((Get-Date) -lt $deadline) {
    if (-not (Test-TcpOpen $hostName $port)) { break }
    Start-Sleep -Milliseconds 200
  }
  if (Test-TcpOpen $hostName $port) {
    Write-Warning ("Agent port still open after cleanup: " + $hostName + ":" + $port)
  } else {
    Write-Host ("Agent port closed " + $hostName + ":" + $port)
  }
}

function Ensure-AgentReady($Cfg, [string]$DesignerPath, [string]$ProjectRoot) {
  $da = $Cfg.designerAgent
  $hostName = if ($da.host) { [string]$da.host } else { "127.0.0.1" }
  $port = if ($da.port) { [int]$da.port } else { 1543 }
  $auto = $true
  if ($NoAutoStart) { $auto = $false }
  elseif ($null -ne $da.autoStart) { $auto = [bool]$da.autoStart }
  if (-not (Test-TcpOpen $hostName $port)) {
    if (-not $auto) { throw "Agent not running on ${hostName}:${port}" }
    Start-DesignerAgent $Cfg $DesignerPath $ProjectRoot
  }
}

function Test-AgentOutputFailed([string]$Text) {
  $t = $Text.ToLowerInvariant()
  foreach ($s in @('"type":"error"', '"type": "error"', "операция не выполнена", "unknown command")) {
    if ($t.Contains($s)) { return $true }
  }
  return $false
}

function Invoke-AgentViaPlink {
  param([string]$HostName, [int]$Port, $Auth, [string[]]$Commands, [string]$PlinkPath, [string]$SuccessMarkerFile = "")

  Write-Host "PLINK=$PlinkPath ${HostName}:${Port} user=$($Auth.User)"
  foreach ($c in $Commands) { Write-Host ">>> $c" }

  # One SSH client only - do not prime host key in a second session.
  # Empty IB (no users): AgentMode accepts empty login; plink needs explicit -l "".
  $sshUser = if ($Auth.User -ne "") { $Auth.User } else { '""' }
  $sshPwd = if ($null -ne $Auth.Password) { $Auth.Password } else { "" }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $PlinkPath
  $psi.Arguments = "-ssh -P $Port -l $sshUser -pw `"$sshPwd`" -batch $HostName"
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true

  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi
  if (-not $proc.Start()) { throw "plink Start failed" }
  Write-Host "PLINK_PID=$($proc.Id)"

  # Drain stdout/stderr asynchronously to avoid pipe deadlocks during long dump.
  $outTask = $proc.StandardOutput.ReadToEndAsync()
  $errTask = $proc.StandardError.ReadToEndAsync()

  try {
    # Wait for shell to come up (no live parse of async buffer - use fixed settle + marker for long ops)
    Start-Sleep -Seconds 3
    if ($proc.HasExited) {
      $o = $outTask.Result
      $e = $errTask.Result
      throw "plink exited early code=$($proc.ExitCode)`nOUT=$o`nERR=$e"
    }

    $all = @("options set --show-prompt=no", "options set --output-format=json") + $Commands
    foreach ($cmd in $all) {
      Write-Host "SEND: $cmd"
      $markerBefore = $null
      if ($SuccessMarkerFile -and (Test-Path -LiteralPath $SuccessMarkerFile)) {
        $markerBefore = (Get-Item -LiteralPath $SuccessMarkerFile).LastWriteTimeUtc
      }

      $proc.StandardInput.WriteLine($cmd)
      $proc.StandardInput.Flush()

      $long = $cmd -match "dump-config-to-files|load-config-from-files|update-db-cfg"
      if ($long -and $SuccessMarkerFile) {
        $endAt = (Get-Date).AddSeconds(36000)
        $ok = $false
        while ((Get-Date) -lt $endAt) {
          Start-Sleep -Seconds 2
          if ($proc.HasExited) { throw "plink exited during: $cmd" }
          if (Test-Path -LiteralPath $SuccessMarkerFile) {
            $mt = (Get-Item -LiteralPath $SuccessMarkerFile).LastWriteTimeUtc
            if ($null -eq $markerBefore -or $mt -gt $markerBefore) {
              $cdi = Join-Path (Split-Path $SuccessMarkerFile) "ConfigDumpInfo.xml"
              if (Test-Path -LiteralPath $cdi) {
                $a = (Get-Item $cdi).Length
                Start-Sleep -Seconds 3
                $b = (Get-Item $cdi).Length
                Start-Sleep -Seconds 3
                $c = (Get-Item $cdi).Length
                if ($a -eq $b -and $b -eq $c -and $a -gt 0) {
                  Write-Host "MARKER_STABLE ConfigDumpInfo.xml ($a bytes)"
                  $ok = $true
                  break
                }
              } elseif (((Get-Date).ToUniversalTime() - $mt).TotalSeconds -gt 5) {
                # Configuration.xml appeared; wait a bit more for CDI
                Write-Host "Configuration.xml updated, waiting ConfigDumpInfo..."
              }
            }
          }
        }
        if (-not $ok) { throw "Timeout waiting marker for: $cmd" }
      } else {
        # short commands: fixed pause (agent has no progress on async stdout until session ends)
        Start-Sleep -Seconds 4
        if ($proc.HasExited) {
          $o = $outTask.Result
          $e = $errTask.Result
          throw "plink exited during: $cmd`nOUT=$o`nERR=$e"
        }
      }
    }

    try { $proc.StandardInput.Close() } catch {}
    if (-not $proc.WaitForExit(60000)) {
      $proc.Kill()
      throw "plink did not exit after stdin close"
    }

    $outText = $outTask.Result
    $errText = $errTask.Result
    Write-Host "PLINK_DONE exit=$($proc.ExitCode)"
    if ($outText) { Write-Host $outText }
    if ($errText) { Write-Host $errText }
    $combined = $outText + "`n" + $errText
    if (Test-AgentOutputFailed $combined) {
      throw "Agent reported error"
    }
    if ($combined -notmatch "designer>|1C:Enterprise|1C Designer Shell") {
      throw "No designer shell in plink output (host key / auth / busy agent?)"
    }
    return $combined
  }
  finally {
    if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch {} }
    if ($proc) { $proc.Dispose() }
  }
}

function Resolve-Python {
  $candidates = @(
    (Join-Path $ProjectRoot ".venv\Scripts\python.exe"),
    "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python39\python.exe"
  )
  $uvRoot = Join-Path $env:APPDATA "uv\python"
  if (Test-Path -LiteralPath $uvRoot) {
    Get-ChildItem -LiteralPath $uvRoot -Directory -EA SilentlyContinue |
      Sort-Object Name -Descending |
      ForEach-Object {
        $exe = Join-Path $_.FullName "python.exe"
        if (Test-Path -LiteralPath $exe) { $candidates += $exe }
      }
  }
  foreach ($c in $candidates) {
    if (-not (Test-Path -LiteralPath $c)) { continue }
    & $c --version 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return @{ Exe = $c; Prefix = @() } }
  }
  $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
  if ($pyLauncher) { return @{ Exe = $pyLauncher.Source; Prefix = @("-3") } }
  foreach ($name in @("python", "python3")) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notmatch 'WindowsApps') {
      & $cmd.Source --version 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) { return @{ Exe = $cmd.Source; Prefix = @() } }
    }
  }
  return $null
}

function Invoke-AgentViaPython {
  param([string]$HostName, [int]$Port, $Auth, [string[]]$Commands, [string]$SuccessMarkerFile = "")
  $py = Resolve-Python
  if ($null -eq $py) { return $null }

  $helper = Join-Path $ScriptDir "designer_agent_ssh.py"
  if (-not (Test-Path -LiteralPath $helper)) { throw "Missing $helper" }

  $cmdFile = Join-Path $env:TEMP ("1c-agent-cmd-" + [guid]::NewGuid().ToString("N") + ".txt")
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllLines($cmdFile, $Commands, $utf8NoBom)

  # Start-Process -ArgumentList rejects empty-string entries (empty IB login/password).
  function Quote-Arg([string]$Value) {
    if ($null -eq $Value) { $Value = "" }
    return '"' + ($Value -replace '"', '\"') + '"'
  }
  $argParts = @()
  if ($py.Prefix -and $py.Prefix.Count) { $argParts += $py.Prefix }
  $argParts += @(
    (Quote-Arg $helper),
    "--host", (Quote-Arg $HostName),
    "--port", "$Port",
    "--user", (Quote-Arg ([string]$Auth.User)),
    "--password", (Quote-Arg ([string]$Auth.Password)),
    "--commands-file", (Quote-Arg $cmdFile)
  )
  if ($SuccessMarkerFile) {
    $argParts += @("--marker-file", (Quote-Arg $SuccessMarkerFile))
  }
  $argLine = ($argParts -join " ")

  Write-Host "PYTHON_SSH helper=$helper user=$($Auth.User) cmds=$($Commands.Count)"
  $env:PYTHONIOENCODING = "utf-8"
  $outFile = Join-Path $env:TEMP ("1c-agent-out-" + [guid]::NewGuid().ToString("N") + ".txt")
  $errFile = Join-Path $env:TEMP ("1c-agent-err-" + [guid]::NewGuid().ToString("N") + ".txt")

  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $py.Exe
    $psi.Arguments = $argLine
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $ProjectRoot
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { throw "Failed to start python SSH helper" }
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $text = [string]$outTask.Result
    $errText = [string]$errTask.Result
    if ($errText) { $text = ($text + "`n" + $errText).Trim() }
    if ($text.Trim()) {
      [System.IO.File]::WriteAllText($outFile, $text)
      Write-Host $text.TrimEnd()
    }
    if ($proc.ExitCode -ne 0) {
      $snip = if ($text.Length -gt 4000) { $text.Substring($text.Length - 4000) } else { $text }
      throw ("designer_agent_ssh.py exit=" + $proc.ExitCode + "`n" + $snip)
    }
  } finally {
    Remove-Item -LiteralPath $cmdFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
  }
  return $true
}

function Invoke-AgentCommands {
  param($Cfg, [string[]]$Commands, [string]$Label, [string]$SuccessMarkerFile = "")
  $da = $Cfg.designerAgent
  $hostName = if ($da.host) { [string]$da.host } else { "127.0.0.1" }
  $port = if ($da.port) { [int]$da.port } else { 1543 }
  $auth = Get-AgentAuth $Cfg
  Write-Host "Agent session: $Label"

  $prefer = "python"
  if ($da -and $da.sshClient) { $prefer = [string]$da.sshClient }

  try {
    if ($prefer -in @("python", "auto", "paramiko")) {
      $r = Invoke-AgentViaPython -HostName $hostName -Port $port -Auth $auth -Commands $Commands -SuccessMarkerFile $SuccessMarkerFile
      if ($null -ne $r) { return }
      if ($prefer -eq "python" -or $prefer -eq "paramiko") {
        throw "Python/paramiko unavailable. pip install paramiko"
      }
    }
    if ($prefer -in @("plink", "auto")) {
      $plink = Resolve-Plink
      if ($plink) {
        Invoke-AgentViaPlink -HostName $hostName -Port $port -Auth $auth -Commands $Commands -PlinkPath $plink -SuccessMarkerFile $SuccessMarkerFile | Out-Null
        return
      }
      if ($prefer -eq "plink") { throw "plink.exe not found" }
    }
    throw "No SSH client for agent (need Python+paramiko or plink)"
  } catch {
    $errFile = Join-Path $ProjectRoot ".1c\last-agent-error.txt"
    $errText = $_ | Out-String
    $errText | Set-Content -LiteralPath $errFile -Encoding UTF8
    Write-Host "AGENT_ERROR=$($_.Exception.Message)"
    # Storage capture lock — ASCII-safe (WinPS5 may misread Cyrillic literals in .ps1)
    $metaRe = '(Catalog|Document|DataProcessor|Report|CommonModule|InformationRegister|Enum|ChartOfCharacteristicTypes)\.[\p{L}\w]+'
    $lockPhrase = -join ([int[]](0x043D,0x0435,0x0020,0x0437,0x0430,0x0445,0x0432,0x0430,0x0447,0x0435,0x043D) | ForEach-Object { [char]$_ })
    $isStorageLock = $errText.Contains($lockPhrase) -or ($errText -match 'ConfigFilesError' -and $errText -match $metaRe)
    if ($isStorageLock) {
      $obj = $null
      $m = [regex]::Match($errText, $metaRe)
      if ($m.Success) { $obj = $m.Value.TrimEnd('!','.',',') }
      if ($obj) {
        Write-Host "STORAGE_LOCK: object $obj is not captured in configuration storage — capture it and retry load."
      } else {
        Write-Host "STORAGE_LOCK: object is not captured in configuration storage — capture required objects and retry load."
      }
    }
    Write-Host "Details: $errFile"
    throw
  }
}

function Invoke-DesignerBatch {
  param([string]$DesignerPath, $Cfg, [string]$ProjectRoot, [string[]]$ExtraArgs, [string]$LogName)
  $auth = Get-AgentAuth $Cfg
  $logDir = Join-Path $ProjectRoot ".1c"
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  $log = Join-Path $logDir $LogName
  if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

  $authArgs = @()
  if ($auth.User -ne "" -or $auth.Required) {
    $authArgs += "/N$($auth.User)"
    $authArgs += "/P$($auth.Password)"
  }
  $argsForLog = @("DESIGNER") + (Get-IbArgs $Cfg $ProjectRoot) + @($authArgs | ForEach-Object {
      if ($_ -like '/P*') { '/P***' } else { $_ }
    }) + @("/DisableStartupDialogs", "/DisableStartupMessages", "/Out", $log) + $ExtraArgs
  Write-Host ">> $DesignerPath $($argsForLog -join ' ')"
  $args = @("DESIGNER") + (Get-IbArgs $Cfg $ProjectRoot) + $authArgs + @("/DisableStartupDialogs", "/DisableStartupMessages", "/Out", $log) + $ExtraArgs
  $p = Start-Process -FilePath $DesignerPath -ArgumentList $args -WorkingDirectory $ProjectRoot -PassThru -Wait -NoNewWindow
  Write-Host "BATCH_EXIT=$($p.ExitCode) LOG=$log"
  if (Test-Path -LiteralPath $log) {
    Get-Content -LiteralPath $log -Encoding Default -EA SilentlyContinue | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }
  }
  if ($p.ExitCode -ne 0) { throw "Designer batch exit $($p.ExitCode)" }
}

function Build-LoadListFromGit {
  param([string]$ProjectRoot, [string]$SrcRel, [string]$Base, [string]$Head, [string]$ListPath)
  $gitExe = Resolve-Git
  $diffLines = & $gitExe -C $ProjectRoot diff --name-only --diff-filter=ACMR $Base $Head
  if ($LASTEXITCODE -ne 0) { throw "git diff failed" }
  $files = @()
  $prefix = "$SrcRel/"
  foreach ($line in @($diffLines)) {
    if (-not $line) { continue }
    $fn = ($line.ToString().Trim() -replace "\\", "/")
    if ($fn.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      $rel = $fn.Substring($prefix.Length)
      if ($rel) { $files += $rel }
    }
  }
  $files = @($files | Select-Object -Unique)
  if ($files.Count -eq 0) { throw "no changed files under $SrcRel" }
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllLines($ListPath, $files, $utf8NoBom)
  Write-Host "LIST_FILE=$ListPath ($($files.Count))"
  return $files
}

function Write-LoadListFile {
  param([string]$ListPath, [string[]]$RelPaths)
  $files = @($RelPaths | ForEach-Object { ($_ -replace "\\", "/").Trim() } | Where-Object { $_ } | Select-Object -Unique)
  if ($files.Count -eq 0) { throw "empty load list" }
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllLines($ListPath, $files, $utf8NoBom)
  Write-Host "LIST_FILE=$ListPath ($($files.Count))"
  return $files
}

# Agent cwd = AgentBaseDir\<userDir> (часто 0\ по agentbasedir.json).
# Пути к репо — на уровень выше: ../src, ../.1c/...
function Get-AgentRepoRel {
  param([string]$ProjectRel)
  $p = ($ProjectRel -replace "\\", "/")
  while ($p.StartsWith("./")) { $p = $p.Substring(2) }
  $p = $p.TrimEnd("/")
  if (-not $p) { return ".." }
  return "../$p"
}

# --- main ---
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfgPath = Join-Path $ProjectRoot ".1c\project.json"
$localPath = Join-Path $ProjectRoot ".1c\project.local.json"
if (-not (Test-Path -LiteralPath $cfgPath)) { throw "Missing $cfgPath" }

$cfg = Merge-Config (Read-JsonFile $cfgPath) (Read-JsonFile $localPath)
$designerPath = Resolve-Designer ([string]$cfg.designer) ([string]$cfg.platformVersion)
$srcRel = Get-SrcRel $cfg
$transport = Get-Transport $cfg
$da = $cfg.designerAgent
$format = "hierarchical"
if ($da -and $da.format) { $format = [string]$da.format }

Write-Host "project=$ProjectRoot"
Write-Host "designer=$designerPath"
Write-Host "src=$srcRel"
Write-Host "transport=$transport"
Write-Host "action=$Action"

if ($ClearAgentPort -or ($transport -eq "agent" -and $Action -eq "start")) {
  $port = 1543
  if ($da -and $da.port) { $port = [int]$da.port }
  Clear-AgentPort -Port $port
}

switch ($Action) {
  "start" {
    if ($transport -ne "agent") { throw "start requires transport=agent" }
    Start-DesignerAgent $cfg $designerPath $ProjectRoot
  }
  "stop" {
    if ($transport -ne "agent") { throw "stop requires transport=agent" }
    Ensure-AgentReady $cfg $designerPath $ProjectRoot
    Invoke-AgentCommands $cfg @("common shutdown") "stop"
  }
  "ping" {
    if ($transport -eq "agent") {
      try {
        Ensure-AgentReady $cfg $designerPath $ProjectRoot
        Invoke-AgentCommands $cfg @("common connect-ib", "help --version", "common disconnect-ib") "ping"
      } finally {
        Stop-DesignerAgentAfterOp $cfg "ping"
      }
    } else {
      $null = Get-AgentAuth $cfg
      Write-Host "batch ping: designer+auth OK"
    }
  }
  "dump-full" {
    $dumpRel = $srcRel
    if ($env:1C_AGENT_DUMP_DIR) { $dumpRel = $env:1C_AGENT_DUMP_DIR }
    $srcAbs = Join-Path $ProjectRoot ($dumpRel -replace "/", "\")
    New-Item -ItemType Directory -Force -Path $srcAbs | Out-Null
    $marker = Join-Path $srcAbs "Configuration.xml"

    if ($transport -eq "agent") {
      try {
        Ensure-AgentReady $cfg $designerPath $ProjectRoot
        $agentDir = Get-AgentRepoRel $dumpRel
        Write-Host "agent --dir=$agentDir (cwd=AgentBaseDir/<user>)"
        Invoke-AgentCommands $cfg @(
          "common connect-ib",
          "config dump-config-to-files --dir=$agentDir --format=$format",
          "common disconnect-ib"
        ) "dump-full" -SuccessMarkerFile $marker
      } finally {
        Stop-DesignerAgentAfterOp $cfg "dump-full"
      }
    } else {
      Invoke-DesignerBatch -DesignerPath $designerPath -Cfg $cfg -ProjectRoot $ProjectRoot -LogName "dump-full.log" -ExtraArgs @(
        "/DumpConfigToFiles", $srcAbs
      )
    }
    if (-not (Test-Path -LiteralPath $marker)) { throw "dump-full: missing $marker" }
    Write-Host "DUMP_DIR=$srcAbs"
    Write-Host "DUMP_MTIME=$((Get-Item $marker).LastWriteTime)"
  }
  "dump-update" {
    $srcAbs = Join-Path $ProjectRoot $srcRel
    $cdi = Join-Path $srcAbs "ConfigDumpInfo.xml"
    if (-not (Test-Path -LiteralPath $cdi)) { throw "need ConfigDumpInfo.xml - run dump-full first" }
    $marker = Join-Path $srcAbs "Configuration.xml"
    if ($transport -eq "agent") {
      try {
        Ensure-AgentReady $cfg $designerPath $ProjectRoot
        $agentDir = Get-AgentRepoRel $srcRel
        Write-Host "agent --dir=$agentDir (cwd=AgentBaseDir/<user>)"
        Invoke-AgentCommands $cfg @(
          "common connect-ib",
          "config dump-config-to-files --dir=$agentDir --format=$format --update --force",
          "common disconnect-ib"
        ) "dump-update" -SuccessMarkerFile $marker
      } finally {
        Stop-DesignerAgentAfterOp $cfg "dump-update"
      }
    } else {
      Invoke-DesignerBatch -DesignerPath $designerPath -Cfg $cfg -ProjectRoot $ProjectRoot -LogName "dump-update.log" -ExtraArgs @(
        "/DumpConfigToFiles", $srcAbs, "-update", "-force"
      )
    }
    Write-Host "DUMP_DIR=$srcAbs"
  }
  "load-changed" {
    $base = $BaseRef
    if (-not $base -and $da -and $da.delta -and $da.delta.baseRef) { $base = [string]$da.delta.baseRef }
    if (-not $base) { $base = "main" }
    $head = $HeadRef
    if (-not $head -and $da -and $da.delta -and $da.delta.headRef) { $head = [string]$da.delta.headRef }
    if (-not $head) { $head = "HEAD" }

    $srcAbs = Join-Path $ProjectRoot $srcRel
    $listPath = Join-Path $ProjectRoot ".1c\load-changed-list.txt"
    New-Item -ItemType Directory -Force -Path (Split-Path $listPath) | Out-Null
    if ($ListFile) {
      $srcList = (Resolve-Path -LiteralPath $ListFile).Path
      $lines = Get-Content -LiteralPath $srcList -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and ($_ -notmatch '^\s*#') }
      Write-LoadListFile -ListPath $listPath -RelPaths $lines | Out-Null
      Write-Host "Loaded from ListFile=$srcList"
    } else {
      Build-LoadListFromGit -ProjectRoot $ProjectRoot -SrcRel $srcRel -Base $base -Head $head -ListPath $listPath | Out-Null
      Write-Host "Loaded git $base..$head"
    }

    if ($transport -eq "agent") {
      try {
        Ensure-AgentReady $cfg $designerPath $ProjectRoot
        $agentDir = Get-AgentRepoRel $srcRel
        $listRel = Get-AgentRepoRel ".1c/load-changed-list.txt"
        Write-Host "agent --dir=$agentDir --list-file=$listRel"
        Write-Host "update-db-cfg: never (main config only)"
        $cmds = @(
          "common connect-ib",
          "config load-config-from-files --dir=$agentDir --format=$format --list-file=$listRel --update-config-dump-info"
        )
        $cmds += "common disconnect-ib"
        Invoke-AgentCommands $cfg $cmds "load-changed"
      } finally {
        Stop-DesignerAgentAfterOp $cfg "load-changed"
      }
    } else {
      Write-Host "UpdateDBCfg: never (main config only)"
      $extra = @("/LoadConfigFromFiles", $srcAbs, "-listFile", $listPath, "-updateConfigDumpInfo")
      Invoke-DesignerBatch -DesignerPath $designerPath -Cfg $cfg -ProjectRoot $ProjectRoot -LogName "load-changed.log" -ExtraArgs $extra
    }
  }
}

Write-Host "OK action=$Action"
exit 0
