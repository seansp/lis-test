Write-Host "Test1"
Import-Module .\Utilities.psm1

$r1 = FindVM "Shielded_PRE-TDC"

Write-Host "R1 == $r1"

$r2 = FindVM "Foo" 

Write-Host "R2 = $r2"