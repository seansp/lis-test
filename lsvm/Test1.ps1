Write-Host "Test1"
Import-Module .\Utilities.psm1


#Delete old test.
CleanUp-VM "Shielded_PRE-TDC"

#Add drive to mount encrypted drive.
$decryptSource = "D:\WSSCFS\TestContent\Shielded\DecryptVHD\decrypt_drive.vhdx"
$pathToDecryptionVHD = "..\decyptionDrive.vhdx"
Copy-Item -Destination $pathToDecryptionVHD -Path $decryptSource -Force

#Copy the test drive.
$testDriveSource = "D:\WSSCFS\VHD\Cloudbase\Shielded_Encrypted_VHDs\ubuntu1604_encrypted.vhdx"
$pathToTestVHD = "..\testVHD.vhdx"
Copy-Item -Destination $pathToTestVHD -Path $testDriveSource -Force

dir ..
