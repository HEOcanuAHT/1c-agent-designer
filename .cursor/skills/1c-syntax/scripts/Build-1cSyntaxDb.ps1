<#
.SYNOPSIS
  Build bsl-ctx SQLite from platform shcntx_ru.hbk (no HTML dump).

.DESCRIPTION
  Sets UTF-8 for Python, points BSL_CTX_PSEUDO_TYPES at a local overlay, and
  retries `build` when bsl-ctx hits an unknown type name (rule 1).
#>
[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$PlatformVersion = "",
  [switch]$Rebuild,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Common-Syntax.ps1")

function Invoke-UvxCapture {
  param(
    [string]$Uvx,
    [string[]]$ArgList
  )
  $lines = New-Object System.Collections.Generic.List[string]
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $Uvx @ArgList 2>&1 | ForEach-Object {
      $s = $_.ToString()
      [void]$lines.Add($s)
      Write-Host $s
    }
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $prev
  }
  return @{ Code = $code; Lines = @($lines) }
}

Set-BslCtxUtf8Env
$yaml = Initialize-PseudoTypesFile
Write-Host "BSL_CTX_PSEUDO_TYPES=$yaml"

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfg = Read-SyntaxProjectCfg $ProjectRoot
$ver = $PlatformVersion
if (-not $ver) { $ver = Get-SyntaxPlatformVersion $cfg }
if (-not $ver) { throw "platformVersion missing. Set .1c/project.json platformVersion or pass -PlatformVersion." }

$binDir = $null
try {
  $binDir = Resolve-SyntaxBinDir $cfg
} catch {
  throw "1cv8.exe not found for platformVersion=$ver. Install the platform or fix platformVersion."
}
if (-not (Test-SyntaxHbk $binDir)) {
  throw "shcntx_ru.hbk not found in $binDir"
}

$uvx = Find-UvxExe
if (-not $uvx) {
  throw "uvx not found. Install uv (https://docs.astral.sh/uv/) then retry."
}

$spec = Get-BslCtxSpec
$dataDir = Get-SyntaxDataDir
$corpus = Join-Path $dataDir "corpus.sqlite"
$dbPath = Join-Path $dataDir ("bsl-context-{0}.sqlite" -f $ver)
$learned = New-Object System.Collections.Generic.List[string]
$buildArgs = @(
  "--from", $spec, "bsl-ctx", "build",
  "--corpus", $corpus,
  "--db", $dbPath
)

function Invoke-BslBuildRetry {
  $max = 40
  for ($i = 0; $i -lt $max; $i++) {
    Write-Host ("uvx {0}" -f ($buildArgs -join " "))
    $run = Invoke-UvxCapture -Uvx $uvx -ArgList $buildArgs
    if ($run.Code -eq 0) { return }
    $unknown = Get-UnknownTypeFromBslOutput $run.Lines
    if (-not $unknown) {
      throw ("bsl-ctx build failed exit={0}" -f $run.Code)
    }
    Write-Host ("skip unknown type: {0}" -f $unknown)
    Add-PseudoTypeName $unknown
    [void]$learned.Add($unknown)
  }
  throw "bsl-ctx: too many unknown types ($max)"
}

$needCapture = $Rebuild -or -not (Test-Path -LiteralPath $corpus)
if ($needCapture) {
  $setupArgs = @(
    "--from", $spec, "bsl-ctx", "setup",
    "--platform", $ver, "--no-ir", "--keep-corpus"
  )
  if ($Rebuild) { $setupArgs += "--rebuild" }
  Write-Host "bsl-ctx setup platform=$ver hbk=$binDir\shcntx_ru.hbk"
  Write-Host ("uvx {0}" -f ($setupArgs -join " "))
  $setup = Invoke-UvxCapture -Uvx $uvx -ArgList $setupArgs
  if ($setup.Code -ne 0) {
    $unknown = Get-UnknownTypeFromBslOutput $setup.Lines
    if (-not $unknown) {
      throw ("bsl-ctx setup failed exit={0}" -f $setup.Code)
    }
    Write-Host ("skip unknown type: {0}" -f $unknown)
    Add-PseudoTypeName $unknown
    [void]$learned.Add($unknown)
  }
}

if (-not (Test-SyntaxDbOk -DbPath $dbPath -Uvx $uvx -Spec $spec)) {
  if (Test-Path -LiteralPath $dbPath) {
    Write-Host "remove broken db=$dbPath"
    Remove-Item -LiteralPath $dbPath -Force
  }
  if (-not (Test-Path -LiteralPath $corpus)) {
    throw "corpus.sqlite missing after setup: $corpus"
  }
  Write-Host "reuse corpus=$corpus"
  Invoke-BslBuildRetry
}

$db = Find-SyntaxDb $ver
$compat = Get-SyntaxCompatTarget $ProjectRoot $cfg
$result = [ordered]@{
  ok               = [bool]($db -and (Test-Path -LiteralPath $db))
  platformVersion  = $ver
  binDir           = $binDir
  db               = $db
  dataDir          = $dataDir
  compatTarget     = $compat
  skippedTypes     = @($learned)
  pseudoTypes      = $env:BSL_CTX_PSEUDO_TYPES
}
if (-not $result.ok) { throw "bsl-ctx finished but db not found: $dbPath" }
if ($Json) {
  $result | ConvertTo-Json -Depth 5
} else {
  Write-Host ("OK db={0}" -f $db)
  if ($compat) { Write-Host "compatTarget=$compat" }
  if ($learned.Count) { Write-Host ("skippedTypes: {0}" -f ($learned -join ", ")) }
}
exit 0
