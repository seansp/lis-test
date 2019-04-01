Write-Host "Test1"
Import-Module .\Utilities.psm1

CleanUp-VM "Shielded_PRE-TDC"

$decryptSource = "D:\WSSCFS\TestContent\Shielded\DecryptVHD\decrypt_drive.vhdx"
$pathToDecryptionVHD = "..\decyptionDrive.vhdx"

Copy-Item -Path $pathToDecryptionVHD -Source $decryptSource


