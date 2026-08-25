#Requires -Version 5.1
# UTF-8 BOM + ASCII punctuation + Parser::ParseFile (Windows PowerShell 5.1).
param(
  [string]$RepoRoot = ""
)
$ErrorActionPreference = "Stop"
if (-not $RepoRoot) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$forbidden = @(
  [char]0x2014, [char]0x2013, [char]0x2012, [char]0x2015, [char]0x2212, [char]0x2011,
  [char]0x2026, [char]0x00AB, [char]0x00BB, [char]0x201C, [char]0x201D, [char]0x2018, [char]0x2019
)

$files = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -Filter *.ps1 |
  Where-Object { $_.FullName -notmatch '\\(\.git|node_modules)\\' })

$fail = 0
foreach ($f in $files) {
  $rel = $f.FullName.Substring($RepoRoot.Length).TrimStart('\', '/')
  $bytes = [IO.File]::ReadAllBytes($f.FullName)
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $start = 0
  if ($hasBom) { $start = 3 }
  $hasHigh = $false
  for ($i = $start; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -ge 0x80) { $hasHigh = $true; break }
  }
  if (-not $hasBom) {
    Write-Host "FAIL $rel : no UTF-8 BOM (EF BB BF)"
    $fail++
    if ($hasHigh) {
      Write-Host "FAIL $rel : byte >= 0x80 without BOM (PS 5.1 will misparse)"
    }
  }
  $text = [Text.Encoding]::UTF8.GetString($bytes, $start, $bytes.Length - $start)
  foreach ($ch in $forbidden) {
    if ($text.IndexOf([string]$ch) -ge 0) {
      Write-Host ("FAIL {0} : typographic U+{1:X4}" -f $rel, [int]$ch)
      $fail++
      break
    }
  }
  $tokens = $null
  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs)
  if ($errs -and $errs.Count -gt 0) {
    Write-Host "FAIL $rel : ParserError count=$($errs.Count)"
    foreach ($e in @($errs | Select-Object -First 5)) {
      Write-Host ("  L{0}: {1}" -f $e.Extent.StartLineNumber, $e.Message)
    }
    $fail++
  }
}

if ($fail -gt 0) {
  Write-Host "SUMMARY fail=$fail files=$($files.Count)"
  exit 1
}
Write-Host "SUMMARY fail=0 files=$($files.Count)"
exit 0