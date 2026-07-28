<#
.SYNOPSIS
  Sync template tooling into a 1C config project without touching src/ or IB secrets.

.PARAMETER Action
  check  — compare local vs template version (no writes)
  sync   — copy allowlisted paths from template
  status — show local template version / url

.PARAMETER ProjectRoot
  Target config repo (default: current directory).

.PARAMETER TemplateRoot
  Local clone of the template. If empty, uses -TemplateUrl shallow clone to temp.

.PARAMETER TemplateUrl
  Git URL of the template (default from local/project manifest).

.PARAMETER Ref
  Git ref to sync from (default: main / manifest.ref).

.PARAMETER IncludeOptional
  Also copy optionalPaths (.gitignore, README.md).

.PARAMETER DryRun
  Show planned copies; do not write.
#>
[CmdletBinding()]
param(
  [ValidateSet("check", "sync", "status")]
  [string]$Action = "check",
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$TemplateRoot = "",
  [string]$TemplateUrl = "",
  [string]$Ref = "",
  [switch]$IncludeOptional,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Read-JsonFile([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-ManifestPath([string]$Root) {
  return (Join-Path $Root ".1c\template-manifest.json")
}

function Resolve-Git {
  foreach ($c in @(
      "C:\Program Files\Git\bin\git.exe",
      "C:\Program Files (x86)\Git\bin\git.exe",
      "$env:LOCALAPPDATA\Programs\Git\bin\git.exe"
    )) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  $cmd = Get-Command git -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw "git.exe not found."
}

function Assert-SafeRel([string]$Rel) {
  $r = ($Rel -replace "\\", "/").Trim().TrimStart("/")
  if (-not $r) { throw "empty path in manifest" }
  if ($r.Contains("..")) { throw "path must not contain ..: $Rel" }
  if ([System.IO.Path]::IsPathRooted($Rel)) { throw "path must be relative: $Rel" }
  $blocked = @("src", ".1c/project.json", ".1c/project.local.json")
  foreach ($b in $blocked) {
    if ($r -eq $b -or $r.StartsWith("$b/", [StringComparison]::OrdinalIgnoreCase)) {
      throw "refusing to sync blocked path: $Rel"
    }
  }
  return $r
}

function Get-ChildSkillDirs([string]$SkillsRoot) {
  if (-not (Test-Path -LiteralPath $SkillsRoot)) { return @() }
  return @(Get-ChildItem -LiteralPath $SkillsRoot -Directory | Select-Object -ExpandProperty Name)
}

function Normalize-Rel([string]$Rel) {
  return (($Rel -replace "\\", "/").Trim().TrimStart("/"))
}

function Compare-TemplateVersion([string]$Left, [string]$Right) {
  if (-not $Left -and $Right) { return -1 }
  if ($Left -and -not $Right) { return 1 }
  if (-not $Left -and -not $Right) { return 0 }
  $pa = @($Left -split '\.' | ForEach-Object { [int]$_ })
  $pb = @($Right -split '\.' | ForEach-Object { [int]$_ })
  $n = [Math]::Max($pa.Count, $pb.Count)
  for ($i = 0; $i -lt $n; $i++) {
    $va = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
    $vb = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
    if ($va -lt $vb) { return -1 }
    if ($va -gt $vb) { return 1 }
  }
  return 0
}

function Write-UpgradeNotes {
  param(
    [string]$FromVersion,
    [string]$ToVersion,
    [object]$Manifest,
    [string]$ProjectRoot
  )
  if (-not $FromVersion) {
    Write-Host "UPGRADE first-sync: read docs/TEMPLATE_UPGRADE.md and align .1c/project.json with .1c/project.json.example"
    return
  }
  if ((Compare-TemplateVersion $FromVersion $ToVersion) -ge 0) { return }

  Write-Host "UPGRADE from=$FromVersion to=$ToVersion"
  $notes = @()
  if ($Manifest.upgradeNotes) { $notes = @($Manifest.upgradeNotes) }
  foreach ($note in $notes) {
    $since = [string]$note.since
    if (-not $since) { continue }
    if ((Compare-TemplateVersion $FromVersion $since) -lt 0 -and (Compare-TemplateVersion $since $ToVersion) -le 0) {
      Write-Host "UPGRADE [$since] $($note.summary)"
    }
  }
  $doc = Join-Path $ProjectRoot "docs\TEMPLATE_UPGRADE.md"
  if (Test-Path -LiteralPath $doc) {
    Write-Host "UPGRADE details: docs/TEMPLATE_UPGRADE.md"
  } else {
    Write-Host "UPGRADE details: will appear after sync (docs/TEMPLATE_UPGRADE.md)"
  }
  Write-Host "UPGRADE project.json is manual — sync does not rewrite infobase/auth"
}

function Test-ProjectSkip([string]$Rel, [string[]]$Skip) {
  $r = Normalize-Rel $Rel
  foreach ($s in @($Skip)) {
    $sn = Normalize-Rel $s
    if (-not $sn) { continue }
    if ($r -eq $sn) { return $true }
  }
  return $false
}

function Remove-SkippedFromProject {
  param([string]$DstRoot, [string[]]$Skip, [switch]$DryRun)
  foreach ($s in @($Skip)) {
    $rel = Normalize-Rel $s
    if (-not $rel) { continue }
    $path = Join-Path $DstRoot ($rel -replace "/", "\")
    if (-not (Test-Path -LiteralPath $path)) { continue }
    if ($DryRun) {
      Write-Host "DRYRUN remove-skip $rel"
      continue
    }
    Write-Host "REMOVE (template-only) $rel"
    Remove-Item -LiteralPath $path -Force -Recurse -ErrorAction SilentlyContinue
  }
}

function Copy-TemplatePath {
  param(
    [string]$SrcRoot,
    [string]$DstRoot,
    [string]$Rel,
    [string[]]$SkipPaths,
    [switch]$DryRun
  )
  $relNorm = Assert-SafeRel $Rel
  if (Test-ProjectSkip $relNorm $SkipPaths) {
    Write-Host "SKIP (template-only) $relNorm"
    return
  }
  $src = Join-Path $SrcRoot ($relNorm -replace "/", "\")
  $dst = Join-Path $DstRoot ($relNorm -replace "/", "\")

  if (-not (Test-Path -LiteralPath $src)) {
    Write-Warning "Skip missing in template: $relNorm"
    return
  }

  # .cursor/skills — dirs; .cursor/rules — files. Keep project-only extras.
  $leaf = Split-Path $relNorm -Leaf
  $parent = Split-Path $relNorm -Parent
  if ($leaf -eq "skills" -and $parent -eq ".cursor") {
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    foreach ($name in (Get-ChildSkillDirs $src)) {
      $childRel = "$relNorm/$name"
      if (Test-ProjectSkip $childRel $SkipPaths) {
        Write-Host "SKIP (template-only) $childRel"
        continue
      }
      $from = Join-Path $src $name
      $to = Join-Path $dst $name
      if ($DryRun) {
        Write-Host "DRYRUN mirror $childRel"
        continue
      }
      Write-Host "SYNC $childRel"
      if (Test-Path -LiteralPath $to) { Remove-Item -LiteralPath $to -Recurse -Force }
      Copy-Item -LiteralPath $from -Destination $to -Recurse -Force
    }
    return
  }
  if ($leaf -eq "rules" -and $parent -eq ".cursor") {
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    $files = @(Get-ChildItem -LiteralPath $src -File -Force)
    foreach ($f in $files) {
      $childRel = "$relNorm/$($f.Name)"
      if (Test-ProjectSkip $childRel $SkipPaths) {
        Write-Host "SKIP (template-only) $childRel"
        continue
      }
      $to = Join-Path $dst $f.Name
      if ($DryRun) {
        Write-Host "DRYRUN file $childRel"
        continue
      }
      Write-Host "SYNC $childRel"
      Copy-Item -LiteralPath $f.FullName -Destination $to -Force
    }
    return
  }

  if ($DryRun) {
    Write-Host "DRYRUN copy $relNorm"
    return
  }

  $dstParent = Split-Path $dst -Parent
  if ($dstParent) { New-Item -ItemType Directory -Force -Path $dstParent | Out-Null }

  if (Test-Path -LiteralPath $src -PathType Container) {
    Write-Host "SYNC dir $relNorm"
    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
    Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
  } else {
    Write-Host "SYNC file $relNorm"
    Copy-Item -LiteralPath $src -Destination $dst -Force
  }
}

function Get-TemplateSource {
  param(
    [string]$TemplateRoot,
    [string]$TemplateUrl,
    [string]$Ref,
    [object]$LocalHint
  )

  if ($TemplateRoot) {
    $root = (Resolve-Path -LiteralPath $TemplateRoot).Path
    $m = Read-JsonFile (Get-ManifestPath $root)
    if ($null -eq $m) { throw "No template-manifest.json in $root" }
    return @{ Root = $root; Manifest = $m; Temp = $false }
  }

  $url = $TemplateUrl
  if (-not $url -and $LocalHint -and $LocalHint.url) { $url = [string]$LocalHint.url }
  if (-not $url) { $url = "https://github.com/HEOcanuAHT/1c-agent-designer.git" }

  $refName = $Ref
  if (-not $refName -and $LocalHint -and $LocalHint.ref) { $refName = [string]$LocalHint.ref }
  if (-not $refName) { $refName = "main" }

  $git = Resolve-Git
  $tmp = Join-Path $env:TEMP ("1c-template-sync-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  Write-Host "CLONE $url ($refName) -> $tmp"
  & $git clone --depth 1 --branch $refName $url $tmp
  if ($LASTEXITCODE -ne 0) {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    throw "git clone failed"
  }
  $m = Read-JsonFile (Get-ManifestPath $tmp)
  if ($null -eq $m) {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    throw "Cloned repo has no .1c/template-manifest.json"
  }
  return @{ Root = $tmp; Manifest = $m; Temp = $true }
}

function Update-ProjectTemplateMeta {
  param([string]$ProjectRoot, [object]$Manifest)
  $cfgPath = Join-Path $ProjectRoot ".1c\project.json"
  if (-not (Test-Path -LiteralPath $cfgPath)) { return }
  $cfg = Read-JsonFile $cfgPath
  if ($null -eq $cfg) { return }
  $tpl = [pscustomobject]@{
    name    = [string]$Manifest.name
    version = [string]$Manifest.version
    url     = [string]$Manifest.url
    ref     = [string]$Manifest.ref
  }
  $cfg | Add-Member -NotePropertyName template -NotePropertyValue $tpl -Force
  $json = $cfg | ConvertTo-Json -Depth 20
  [System.IO.File]::WriteAllText($cfgPath, $json + "`n", (New-Object System.Text.UTF8Encoding $false))
  Write-Host "Updated .1c/project.json template.version=$($Manifest.version)"
}

# --- main ---
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$localManifest = Read-JsonFile (Get-ManifestPath $ProjectRoot)
$projectCfg = Read-JsonFile (Join-Path $ProjectRoot ".1c\project.json")

$localVersion = $null
$localUrl = $null
if ($localManifest) {
  $localVersion = [string]$localManifest.version
  $localUrl = [string]$localManifest.url
} elseif ($projectCfg -and $projectCfg.template) {
  $localVersion = [string]$projectCfg.template.version
  $localUrl = [string]$projectCfg.template.url
}

Write-Host "project=$ProjectRoot"
Write-Host "action=$Action"
Write-Host "localVersion=$(if ($localVersion) { $localVersion } else { '(none)' })"

if ($Action -eq "status") {
  Write-Host "localUrl=$(if ($localUrl) { $localUrl } else { '(none)' })"
  if ($projectCfg -and $projectCfg.template) {
    Write-Host "project.json.template=$($projectCfg.template | ConvertTo-Json -Compress)"
  }
  exit 0
}

$hint = $localManifest
if ($null -eq $hint -and $projectCfg -and $projectCfg.template) { $hint = $projectCfg.template }

$src = $null
try {
  $src = Get-TemplateSource -TemplateRoot $TemplateRoot -TemplateUrl $TemplateUrl -Ref $Ref -LocalHint $hint
  $remote = $src.Manifest
  Write-Host "templateRoot=$($src.Root)"
  Write-Host "remoteVersion=$($remote.version)"

  if ($Action -eq "check") {
    if (-not $localVersion) {
      Write-Host "RESULT=missing-local (project has no template version; sync recommended)"
      exit 2
    }
    if ($localVersion -eq [string]$remote.version) {
      Write-Host "RESULT=up-to-date version=$localVersion"
      exit 0
    }
    Write-Host "RESULT=outdated local=$localVersion remote=$($remote.version)"
    exit 3
  }

  if ($Action -eq "sync") {
    $fromVersion = $localVersion
    $paths = @($remote.paths)
    if ($IncludeOptional -and $remote.optionalPaths) {
      $paths += @($remote.optionalPaths)
    }
    $skip = @()
    if ($remote.projectSkipPaths) { $skip = @($remote.projectSkipPaths | ForEach-Object { [string]$_ }) }
    Write-Host "script=$PSCommandPath"
    foreach ($p in $paths) {
      Copy-TemplatePath -SrcRoot $src.Root -DstRoot $ProjectRoot -Rel ([string]$p) -SkipPaths $skip -DryRun:$DryRun
    }
    # Do not strip template-only files when syncing the template repo onto itself.
    $sameRoot = ((Resolve-Path -LiteralPath $src.Root).Path -eq $ProjectRoot)
    if (-not $sameRoot) {
      Remove-SkippedFromProject -DstRoot $ProjectRoot -Skip $skip -DryRun:$DryRun
    }
    if (-not $DryRun) {
      # Ensure manifest landed; rewrite project.json template block if present.
      Update-ProjectTemplateMeta -ProjectRoot $ProjectRoot -Manifest $remote
      Write-Host "OK sync version=$($remote.version)"
      Write-UpgradeNotes -FromVersion $fromVersion -ToVersion ([string]$remote.version) -Manifest $remote -ProjectRoot $ProjectRoot
    } else {
      Write-Host "OK dry-run version=$($remote.version)"
      Write-UpgradeNotes -FromVersion $fromVersion -ToVersion ([string]$remote.version) -Manifest $remote -ProjectRoot $ProjectRoot
    }
    Write-Host "SUMMARY version=$($remote.version) src=untouched secrets=untouched template-only=skipped"
    Write-Host "NEXT: review git status; commit tooling in the config project if desired"
    exit 0
  }
}
finally {
  if ($src -and $src.Temp -and $src.Root -and (Test-Path -LiteralPath $src.Root)) {
    Remove-Item -LiteralPath $src.Root -Recurse -Force -ErrorAction SilentlyContinue
  }
}
