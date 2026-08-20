#Requires -Version 5.1
# Plugin root: каталог с .cursor-plugin/plugin.json (skills/rules/scaffold).
# ProjectRoot — другой путь: workspace конфигурации.

function Get-1cPluginRoot {
  param(
    [string]$ProjectRoot = ""
  )

  $candidates = [System.Collections.Generic.List[string]]::new()

  if ($env:1C_PLUGIN_ROOT) { [void]$candidates.Add($env:1C_PLUGIN_ROOT) }

  $here = $PSScriptRoot
  for ($i = 0; $i -lt 8 -and $here; $i++) {
    [void]$candidates.Add($here)
    $parent = Split-Path -Parent $here
    if (-not $parent -or $parent -eq $here) { break }
    $here = $parent
  }

  if ($ProjectRoot) { [void]$candidates.Add($ProjectRoot) }

  $localPlugin = Join-Path $env:USERPROFILE ".cursor\plugins\local\1c-agent-designer"
  [void]$candidates.Add($localPlugin)

  $pluginsRoot = Join-Path $env:USERPROFILE ".cursor\plugins"
  if (Test-Path -LiteralPath $pluginsRoot) {
    Get-ChildItem -LiteralPath $pluginsRoot -Directory -EA SilentlyContinue | ForEach-Object {
      [void]$candidates.Add($_.FullName)
    }
  }

  foreach ($c in $candidates) {
    if (-not $c) { continue }
    $manifest = Join-Path $c ".cursor-plugin\plugin.json"
    if (Test-Path -LiteralPath $manifest) {
      return (Resolve-Path -LiteralPath $c).Path
    }
  }

  foreach ($c in $candidates) {
    if (-not $c) { continue }
    $legacy = Join-Path $c ".cursor\skills\1c-project-bootstrap\SKILL.md"
    if (Test-Path -LiteralPath $legacy) {
      return (Resolve-Path -LiteralPath $c).Path
    }
  }

  throw "1c-agent-designer plugin root not found. Set 1C_PLUGIN_ROOT or install to ~/.cursor/plugins/local/1c-agent-designer"
}

if ($MyInvocation.InvocationName -ne '.') {
  $pr = if ($args.Count -ge 1) { [string]$args[0] } else { "" }
  Write-Output (Get-1cPluginRoot -ProjectRoot $pr)
}
