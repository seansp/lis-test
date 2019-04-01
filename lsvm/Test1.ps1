Write-Host "Test1"
Import-Module .\Utilities.psm1


$testVMName = "LSVM_PRE-TDC"
$testSwitchName = 'External'
$testMemory = 2048MB


#Delete old test.
CleanUp-VM $testVMName

#Add drive to mount encrypted drive.
$decryptSource = "D:\WSSCFS\TestContent\Shielded\DecryptVHD\decrypt_drive.vhdx"
$pathToDecryptionVHD = "..\decyptionDrive.vhdx"
Copy-Item -Destination $pathToDecryptionVHD -Path $decryptSource -Force

#Copy the test drive.
$testDriveSource = "D:\WSSCFS\VHD\Cloudbase\Shielded_Encrypted_VHDs\ubuntu1604_encrypted.vhdx"
$pathToTestVHD = "..\testVHD.vhdx"
Copy-Item -Destination $pathToTestVHD -Path $testDriveSource -Force

#Create the Test VM
New-VM -Name $testVMName -Generation 2 -VHDPath $pathToTestVHD -MemoryStartupBytes $testMemory -SwitchName $testSwitchName
Set-VMFirmware -VMName $testVMName -EnableSecureBoot Off
