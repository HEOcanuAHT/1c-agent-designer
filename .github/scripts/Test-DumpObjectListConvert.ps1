#Requires -Version 5.1
# UTF-8 BOM required. ASCII punctuation only.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path -LiteralPath (Join-Path $here "..\..")).Path
$lib = Join-Path $repo ".cursor\skills\1c-ibcmd-pack\scripts\Convert-1cDumpObjectList.ps1"
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

Write-Host "SUMMARY fail=0"
exit 0
