#Requires -Version 5.1
# UTF-8 BOM required. ASCII punctuation only.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path -LiteralPath (Join-Path $here "..\..")).Path
$lib = Join-Path $repo "skills\1c-ibcmd-pack\scripts\Convert-1cDumpObjectList.ps1"
. $lib

function Assert-Eq([string]$Actual, [string]$Expected, [string]$Label) {
  if ($Actual -cne $Expected) {
    throw "FAIL $Label : got '$Actual' expected '$Expected'"
  }
  Write-Host "OK $Label"
}

Assert-Eq (Convert-1cSrcRelToDumpObject "Catalogs/Foo/Ext/ObjectModule.bsl") "Catalog.Foo" "module"
Assert-Eq (Reduce-1cDumpAnchor "Catalog.Foo.ObjectModule") "Catalog.Foo" "reduce-module"
Assert-Eq (Convert-1cSrcRelToDumpObject "Catalogs/Foo/Forms/Bar/Ext/Form/Module.bsl") "Catalog.Foo.Form.Bar" "form-module"
Assert-Eq (Convert-1cSrcRelToDumpObject "Catalogs/Foo/Forms/Bar/Ext/Form.xml") "Catalog.Foo.Form.Bar" "form-xml"
Assert-Eq (Convert-1cSrcRelToDumpObject "AccountingRegisters/X/Forms/F.xml") "AccountingRegister.X.Form.F" "acc-form"
Assert-Eq (Convert-1cSrcRelToDumpObject "CommonModules/M/Ext/Module.bsl") "CommonModule.M" "common-module"
Assert-Eq (Convert-1cSrcRelToDumpObject "Subsystems/A/Subsystems/B.xml") "Subsystem.A.Subsystem.B" "subsystem"
Assert-Eq (Convert-1cSrcRelToDumpObject "Configuration.xml") "Configuration" "cfg-xml"
Assert-Eq (Reduce-1cDumpAnchor "Catalog.Foo.Form.Bar.Form") "Catalog.Foo.Form.Bar" "reduce-form-child"

$cdi = @'
<ConfigDumpInfo>
<Metadata name="Catalog.Foo" id="1" configVersion="a000000000000000000000000000000000000000"/>
<Metadata name="Catalog.Foo.ObjectModule" id="1.7" configVersion="b000000000000000000000000000000000000000"/>
<Metadata name="Catalog.FooBar" id="2" configVersion="c000000000000000000000000000000000000000"/>
</ConfigDumpInfo>
'@
$tmp = Join-Path $env:TEMP "cdi-dump-objects-test.xml"
[IO.File]::WriteAllText($tmp, $cdi, (New-Object System.Text.UTF8Encoding $false))
[void](Invalidate-1cConfigDumpInfoVersions -CdiPath $tmp -Anchors @("Catalog.Foo"))
$after = [IO.File]::ReadAllText($tmp)
if ($after -notmatch 'name="Catalog.Foo"[^>]*configVersion="0') { throw "FAIL invalidate parent" }
if ($after -notmatch 'name="Catalog.Foo.ObjectModule"[^>]*configVersion="0') { throw "FAIL invalidate child" }
if ($after -notmatch 'name="Catalog.FooBar"[^>]*configVersion="c') { throw "FAIL sibling must stay" }
Remove-Item -LiteralPath $tmp -Force
Write-Host "OK invalidate"

Assert-Eq (Convert-1cDumpAnchorToSrcRel "Catalog.Foo") "Catalogs/Foo.xml" "anchor-catalog"
Assert-Eq (Convert-1cDumpAnchorToSrcRel "Catalog.Foo.Form.Bar") "Catalogs/Foo/Forms/Bar.xml" "anchor-form"
Assert-Eq (Convert-1cDumpAnchorToSrcRel "Catalog.Foo.Template.T") "Catalogs/Foo/Templates/T.xml" "anchor-template"
Assert-Eq (Convert-1cDumpAnchorToSrcRel "Catalog.Foo.Command.C") "Catalogs/Foo/Commands/C.xml" "anchor-command"
Assert-Eq (Convert-1cDumpAnchorToSrcRel "CommonModule.M") "CommonModules/M.xml" "anchor-common-module"
Assert-Eq (Convert-1cDumpAnchorToSrcRel "CommonForm.F") "CommonForms/F.xml" "anchor-common-form"
Assert-Eq (Convert-1cDumpAnchorToSrcRel "Subsystem.A.Subsystem.B") "Subsystems/A/Subsystems/B.xml" "anchor-subsystem"
Assert-Eq (Convert-1cDumpAnchorToSrcRel "AccountingRegister.X.Form.F") "AccountingRegisters/X/Forms/F.xml" "anchor-acc-form"

if (Test-1cDumpRelIsExtPayload "Catalogs/Foo/Ext/ObjectModule.bsl") { Write-Host "OK ext-payload-module" } else { throw "FAIL ext-payload-module" }
if (Test-1cDumpRelIsExtPayload "Catalogs/Foo/Forms/Bar/Ext/Form.xml") { Write-Host "OK ext-payload-form" } else { throw "FAIL ext-payload-form" }
if (Test-1cDumpRelIsExtPayload "Catalogs/Foo/Forms/Bar.xml") { throw "FAIL form-xml must not be Ext payload" } else { Write-Host "OK form-xml-not-ext" }
if (Test-1cDumpRelIsExtPayload "Catalogs/Ext/Forms/Bar.xml") { throw "FAIL catalog named Ext is not Ext payload" } else { Write-Host "OK catalog-named-ext" }

$threw = $false
try { [void](Convert-1cDumpAnchorToSrcRel "Configuration") } catch {
  if ($_.Exception.Message -match 'too broad') { $threw = $true }
}
if (-not $threw) { throw "FAIL configuration-anchor-throw" }
Write-Host "OK configuration-anchor-throw"

function Get-DumpRel([string]$Abs, [string]$DumpAbs) {
  $a = [IO.Path]::GetFullPath($Abs)
  $d = [IO.Path]::GetFullPath($DumpAbs)
  if (-not $a.StartsWith($d, [StringComparison]::OrdinalIgnoreCase)) {
    throw "path outside dump: $Abs"
  }
  return ($a.Substring($d.Length).TrimStart('\', '/') -replace '\\', '/')
}

$dump = Join-Path $env:TEMP "ibcmd-load-reduce-test"
if (Test-Path -LiteralPath $dump) { Remove-Item -LiteralPath $dump -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dump | Out-Null
function Touch-DumpRel([string]$Rel) {
  $p = Join-Path $dump ($Rel -replace '/', '\')
  $dir = Split-Path -Parent $p
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  [IO.File]::WriteAllText($p, "<xml/>", (New-Object System.Text.UTF8Encoding $false))
}
Touch-DumpRel "Catalogs/Foo.xml"
Touch-DumpRel "Catalogs/Foo/Forms/Bar.xml"
Touch-DumpRel "Catalogs/Foo/Templates/T.xml"
Touch-DumpRel "Catalogs/Foo/Commands/C.xml"
Touch-DumpRel "Catalogs/Ext.xml"
Touch-DumpRel "Catalogs/Ext/Forms/Bar.xml"
Touch-DumpRel "CommonForms/F.xml"
Touch-DumpRel "CommonModules/M.xml"
Touch-DumpRel "Subsystems/A/Subsystems/B.xml"

function Invoke-LoadRels {
  param([string[]]$Lines, [string]$Objects = "")
  $list = Join-Path $dump "list.txt"
  [IO.File]::WriteAllLines($list, @($Lines), (New-Object System.Text.UTF8Encoding $true))
  $files = @(Convert-1cLoadFileList -ListFile $list -Objects $Objects -SrcRel "src" -DumpAbs $dump -ProjectRoot $dump)
  foreach ($f in $files) {
    $r = Get-DumpRel $f $dump
    if (Test-1cDumpRelIsExtPayload $r) { throw "FAIL argv Ext payload: $r" }
  }
  return @($files | ForEach-Object { Get-DumpRel $_ $dump })
}

$rels = @(Invoke-LoadRels @(
    "Catalogs/Foo/Forms/Bar.xml",
    "Catalogs/Foo/Forms/Bar/Ext/Form.xml",
    "Catalogs/Foo/Forms/Bar/Ext/Form/Module.bsl"
  ))
Assert-Eq ($rels -join '|') "Catalogs/Foo/Forms/Bar.xml" "load-form-three"

$rels = @(Invoke-LoadRels @("Catalogs/Foo/Forms/Bar/Ext/Form/Module.bsl"))
Assert-Eq ($rels -join '|') "Catalogs/Foo/Forms/Bar.xml" "load-form-module-only"

$rels = @(Invoke-LoadRels @("# comment") -Objects "Catalog.Foo.Form.Bar")
Assert-Eq ($rels -join '|') "Catalogs/Foo/Forms/Bar.xml" "load-form-anchor-name"

$rels = @(Invoke-LoadRels @("Catalogs/Foo/Ext/ObjectModule.bsl"))
Assert-Eq ($rels -join '|') "Catalogs/Foo.xml" "load-object-module"

$rels = @(Invoke-LoadRels @(
    "Catalogs/Foo/Ext/ObjectModule.bsl",
    "Catalogs/Foo/Forms/Bar/Ext/Form/Module.bsl"
  ))
Assert-Eq ($rels -join '|') "Catalogs/Foo.xml|Catalogs/Foo/Forms/Bar.xml" "load-object-and-form-not-collapsed"

$rels = @(Invoke-LoadRels @("CommonForms/F/Ext/Form.xml"))
Assert-Eq ($rels -join '|') "CommonForms/F.xml" "load-common-form"

$rels = @(Invoke-LoadRels @("Catalog.Ext.Form.Bar"))
Assert-Eq ($rels -join '|') "Catalogs/Ext/Forms/Bar.xml" "load-catalog-named-ext"

$threw = $false
try { [void](Invoke-LoadRels @("Configuration.xml")) } catch {
  if ($_.Exception.Message -match 'too broad') { $threw = $true }
}
if (-not $threw) { throw "FAIL load-configuration-throw" }
Write-Host "OK load-configuration-throw"

$hintLib = Join-Path $repo "skills\1c-runtime\scripts\Common-IbcmdConnection.ps1"
. $hintLib
$hint = Get-IbcmdFailureHint "Unknown metadata object Catalog.Foo.Form.Bar.Ext" 1
if ($hint -notmatch 'Forms/Name.xml') { throw "FAIL hint-ext: $hint" }
Write-Host "OK hint-ext"

Remove-Item -LiteralPath $dump -Recurse -Force
Write-Host "SUMMARY fail=0"
exit 0
