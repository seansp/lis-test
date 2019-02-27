########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################
#
# Linux Shielded VMs PRE-TDC automation functions
#

# Import TCUtils.ps1
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
}
else {
    "ERROR: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Import NET_Utils.ps1
if (Test-Path ".\setupScripts\NET_UTILS.ps1") {
    . .\setupScripts\NET_UTILS.ps1
}
else {
    "ERROR: Could not find setupScripts\NET_UTILS.ps1"
    return $false
}

# Import Shielded_TDC.ps1
if (Test-Path ".\setupScripts\Shielded_TDC.ps1") {
    . .\setupScripts\Shielded_TDC.ps1
}
else {
    "ERROR: Could not find setupScripts\Shielded_TDC.ps1"
    return $false
}

# Import Shielded_PRO.ps1
if (Test-Path ".\setupScripts\Shielded_PRO.ps1") {
    . .\setupScripts\Shielded_PRO.ps1
}
else {
    "ERROR: Could not find setupScripts\Shielded_PRO.ps1"
    return $false
}

# Import Shielded_DEP.ps1
if (Test-Path ".\setupScripts\Shielded_DEP.ps1") {
    . .\setupScripts\Shielded_DEP.ps1
}
else {
    "ERROR: Could not find setupScripts\Shielded_DEP.ps1"
    return $false
}

# Copy template from share to default VHDx path
function Create_Test_VM ([string] $encrypted_vhd)
{
    Write-Host ">> Create_Test_VM : $([DateTime]::Now)"
    # Test dependency VHDx path
    Test-Path $encrypted_vhd
    if (-not $?) {
        return $false
    }

    # Make a copy of the encypted VHDx for testing only
    $destinationVHD = $defaultVhdPath + "PRE-TDC_test.vhdx"
    Set-Variable -Name 'destinationVHD' -Value $destinationVHD -Scope Global
    Copy-Item -Path $(Get-ChildItem $encrypted_vhd -Filter *.vhdx).FullName -Destination $destinationVHD -Force
    if (-not $?) {
        return $false
    }

    # Make a new VM
    New-VM -Name 'Shielded_PRE-TDC' -Generation 2 -VHDPath $destinationVHD -MemoryStartupBytes 4096MB -SwitchName 'External'
    if (-not $?) {
        return $false
    }
    Set-VMProcessor 'Shielded_PRE-TDC' -Count 4 -CompatibilityForMigrationEnabled $False
	Set-VMFirmware -VMName 'Shielded_PRE-TDC' -EnableSecureBoot Off
    return $true
}

# Attach decryption drive to the test VM
function AttachDecryptVHDx ([string] $decrypt)
{
    Write-Host ">> AttachDecryptVHDx ( $decrypt ) : $([DateTime]::Now)"
    $rootDir = $pwd.Path
    # Use script to attach decryption VHDx
    $sts = ./setupScripts/Shielded_Add_DecryptVHD.ps1 -vmName 'Shielded_PRE-TDC' -hvServer 'localhost' -testParams "rootDir=${rootDir}; decrypt_vhd_folder=${decrypt}"
    if (-not $sts[-1]) {
        return $false
    }

    # Start VM and get IP
    $ipv4 = StartVM 'Shielded_PRE-TDC' 'localhost'
    if (-not (isValidIPv4 $ipv4)) {
        return $false
    }

    return $ipv4
}

# Install lsvm
function Install_lsvm ([string]$sshKey, [string]$ipv4, [string]$lsvm_folder_path)
{
    Write-Host ">> Install_lsvm ( $sshKey, $ipv4, $lsvm_folder_path ) : $([DateTime]::Now)"
    $rootDir = $pwd.Path

    Write-Host "##rootDir = $rootDir##"

    # Get KVP data
    $Vm = Get-WmiObject -ComputerName 'localhost' -Namespace root\virtualization\v2 -Query "Select * From Msvm_ComputerSystem Where ElementName='Shielded_PRE-TDC'"
	$Kvp = Get-WmiObject -ComputerName 'localhost' -Namespace root\virtualization\v2 -Query "Associators of {$Vm} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent"
	$kvpData = $Kvp.GuestIntrinsicExchangeItems
	$kvpDict = KvpToDict $kvpData
	$kvpDict | Export-CliXml kvp_results.xml -Force
	
    # Install LSVM script
    Write-Host "##"
    Write-Host "##Shielded_install_psvm.ps1 ::Shielded_PRE-TDC hvServer=localhost .. $testParams";
    Write-Host "##"
    $testParams = "rootDir=${rootDir}; lsvm_folder_path=${lsvm_folder_path}; ipv4=${ipv4}; sshKey=${sshKey}; snapshotName=ICABase"
    ##$sts = ./setupScripts/Shielded_install_lsvm.ps1 -vmName 'Shielded_PRE-TDC' -hvServer 'localhost' -testParams $testParams
    $sts = Actual_Shielded_Install -vmName 'Shielded_PRE-TDC' -hvServer 'localhost' -testParams $testParams
    if (-not $sts[-1]) {
        Write-Host "##ReturningFALSE -- $sts"
        return $false
    }
    foreach( $element in $sts )
    {
        Write-Host "##STS: $element"
    }
    return $sts[-1]
}



function UploadFileToIP( [string] $ipv4, [string] $ssh, [string] $localPath, [string] $remotePath )
{
    $remote = $(Write-Output "n" | .\bin\pscp.exe -i .\ssh\${ssh} ${localPath} root@${ipv4}:${remotePath})
    $remote
}
function ExecuteCommandOnIP( [string] $ipv4, [string] $ssh, [string] $command )
{
    $remote = $(Write-Output "n" | .\bin\plink.exe -i .\ssh\${ssh} root@${ipv4} "$command")
    $remote
}

function Actual_Shielded_Install ([String] $vmName, [String] $hvServer, [String] $testParams)
{
    #############################################################
    #
    # Main script body
    #
    #############################################################
    
    $retVal = $false
    if ($vmName -eq $null) {
        "Error: VM name is null"
        return $retVal
    }
    
    if ($hvServer -eq $null) {
        "Error: hvServer is null"
        return $retVal
    }
    
    $params = $testParams.Split(";")
    foreach ($p in $params) {
        $fields = $p.Split("=")
        
        switch ($fields[0].Trim()) {
            "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
            "rootDir"   { $rootDir = $fields[1].Trim() }
            "sshKey" { $sshKey  = $fields[1].Trim() }
            "ipv4"   {$ipv4 = $fields[1].Trim()}
            "lsvm_folder_path"   {$lsvm_folder = $fields[1].Trim()}
            "snapshotName" { $snapshot = $fields[1].Trim() }
            default  {}
        }
    }
    
    if ($null -eq $sshKey) {
        "Error: Test parameter sshKey was not specified"
        return $False
    }
    
    if ($null -eq $ipv4) {
        "Error: Test parameter ipv4 was not specified"
        return $False
    }
    
    if (-not $rootDir) {
        "Warn : rootdir was not specified"
    }
    else {
        Set-Location $rootDir
    }
    
    # Source TCUitls.ps1 for getipv4 and other functions
    if (Test-Path ".\setupScripts\TCUtils.ps1") {
        . .\setupScripts\TCUtils.ps1
    }
    else {
        "ERROR: Could not find setupScripts\TCUtils.ps1"
        return $false
    }
    
    Write-Host "This script covers test case: ${TC_COVERED} : $([DateTime]::Now)"
    # Copy lsvmtools to root folder
    Test-Path $lsvm_folder
    if (-not $?) {
        Write-Host "Error: Folder $lsvm_folder does not exist! : $([DateTime]::Now)"
        return $false
    }
    
    $rpm = Get-ChildItem $lsvm_folder -Filter *.rpm
    $deb = Get-ChildItem $lsvm_folder -Filter *.deb

    
    Write-Host "$rpm <-- RPM"
    Write-Host "$deb <-- DEB"

    Copy-Item -Path $rpm.FullName -Destination . -Force
    if (-not $?) {
        Write-Host "Error: Failed to copy rpm from $lsvm_folder to $rootDir : $([DateTime]::Now)"
        return $false
    }
    
    Copy-Item -Path $deb.FullName -Destination . -Force
    if (-not $?) {
        Write-Host "Error: Failed to copy deb from $lsvm_folder to $rootDir : $([DateTime]::Now)"
        return $false
    }
    
    # Send lsvmtools to VM
    

    Write-Host "Try mine."
    $ext = ExecuteCommandOnIP -ipv4 $ipv4 -ssh $sshKey -command ". utils.sh && GetOSVersion && echo `$os_PACKAGE"



    $fileExtension = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "dos2unix utils.sh && . utils.sh && GetOSVersion && echo `$os_PACKAGE"
    Write-Host "$fileExtension file will be sent to VM : $([DateTime]::Now)"

    Write-Host "$rpm <-- RPM"
    UploadFileToIP -ipv4 $ipv4 -ssh $ssh -localPath $rpm -remotePath "/tmp/lsvm1.deb"

    $filePath = Get-ChildItem * -Filter *.$fileExtension
    Write-Host "##RelativeSend .\${$filePath.Name}"
    SendFileToVM $ipv4 $sshKey ".\${$filePath.Name}" "/tmp/"
    
    # Install lsvmtools
    if ($fileExtension -eq "deb") {
        SendCommandToVM $ipv4 $sshKey "cd /tmp && dpkg -i lsvm*"    
    }
    if ($fileExtension -eq "rpm") {
        SendCommandToVM $ipv4 $sshKey "cd /tmp && rpm -ivh lsvm*"    
    }
    
    if (-not $?) {
        Write-Host "Error: Failed to install $fileExtension file : $([DateTime]::Now)"
        return $false
    } 
    else {
        Write-Host "lsvmtools was successfully installed! : $([DateTime]::Now)"
    }
    
    Start-sleep -s 3
    
    # Stopping VM to take a checkpoint
    Write-Host "Waiting for VM $vmName to stop... : $([DateTime]::Now)"
    if ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
        Write-Host "Turning off... Server: $hvServer VM: $vmName : $([DateTime]::Now)"
        Stop-VM -ComputerName $hvServer -Name $vmName -Force -Confirm:$false
    }
    
    # Waiting until the VM is off
    if (-not (WaitForVmToStop $vmName $hvServer 300)) {
        Write-Host "Error: Unable to stop VM : $([DateTime]::Now)"
        return $False
    }
    
    Write-Host "Removing passthough disk. : $([DateTime]::Now)"
    # Remove Passthrough disk
    Remove-VMHardDiskDrive -ComputerName $hvServer -VMName $vmName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1
    
    # Take checkpoint
    Checkpoint-VM -Name $vmName -SnapshotName $snapshot -ComputerName $hvServer
    if (-not $?) {
        Write-Host "Error taking snapshot! : $([DateTime]::Now)"
        return $False
    }
    else {
        Write-Host "Checkpoint was created : $([DateTime]::Now)"
        return $true
    }    
}


# Attach decryption drive to the test VM
function DettachDecryptVHDx
{
    Write-Host ">> DettachDecryptVHDx : $([DateTime]::Now)"
    $rootDir = $pwd.Path
    # Use script to attach decryption VHDx
    $sts = ./setupScripts/Shielded_Remove_DecryptVHD.ps1 -vmName 'Shielded_PRE-TDC' -hvServer 'localhost' -testParams "rootDir=${rootDir}; decrypt_vhd_folder=${decrypt}"
    if (-not $sts[-1]) {
        return $false
    }

    return $sts[-1]
}

function Verify_script ([string] $ipv4, [string] $sshKey, [string] $scriptName)
{
    Write-Host ">> Verify_script( $ipv4, $sshKey, $scriptName ) : $([DateTime]::Now)"
    # Run test script
    $retVal = SendCommandToVM $ipv4 $sshKey "bash ${scriptName} && cat state.txt"
    if (-not $retVal) {
        return $false
    }
    # Check status
    $state = .\bin\plink.exe -i ssh\$sshKey root@$ipv4 "cat state.txt"
    if ($state -ne "TestCompleted") {
        return $false
    }

    # Stop VM
    StopVM 'Shielded_PRE-TDC' "localhost"

    return $true
}

function Verify_not_encrypted ([string]$ipv4, [string]$sshKey, [string]$rhel_folder_path, [string]$sles_folder_path, [string]$ubuntu_folder_path, [string]$lsvm_folder_path)
{
    Write-Host ">> Verify_not_encrypted( $ipv4, $sshKey, $rhel_folder_path, $sles_folder_path, $ubuntu_folder_path, $lsvm_folder_path ) : $([DateTime]::Now)"
    $rootDir = $pwd.Path
    # Run test script
    $sts = ./setupScripts/Shielded_not_encrypted_vhd.ps1 -vmName 'Shielded_PRE-TDC' -hvServer 'localhost' `
        -testParams "rootDir=${rootDir}; lsvm_folder_path=${lsvm_folder_path}; ipv4=${ipv4}; sshKey=${sshKey}; sles_folder_path=${sles_folder_path}; ubuntu_folder_path=${ubuntu_folder_path}; rhel_folder_path=${rhel_folder_path}"
    if (-not $sts[-1]) {
        return $false
    }

    return $sts[-1]    
}

function Verify_passphrase_noSpace ([string] $ipv4, [string] $sshKey, [string] $scriptName, [string] $change_passphrase, [string] $fill_disk)
{
    Write-Host ">> Verify_passphrase_noSpace ( $ipv4, $sshKey, $scriptName, $change_passphrase, $fill_disk ) : $([DateTime]::Now)"
    # Append data to constants.sh
    $retVal = SendCommandToVM $ipv4 $sshKey "echo 'change_passphrase=${change_passphrase}' >> constants.sh"
    $retVal = SendCommandToVM $ipv4 $sshKey "echo 'fill_disk=${fill_disk}' >> constants.sh "

    # Run test script
    $retVal = SendCommandToVM $ipv4 $sshKey "bash ${scriptName} && cat state.txt"
    if (-not $retVal) {
        return $false
    }
    # Check status
    $state = .\bin\plink.exe -i ssh\$sshKey root@$ipv4 "cat state.txt"
    if ($state -ne "TestCompleted") {
        return $false
    }

    # Stop VM
    StopVM 'Shielded_PRE-TDC' "localhost"

    return $true
}

function Prepare_VM ([string] $ipv4, [string] $sshKey)
{
    Write-Host ">> Prepare_VM ( $ipv4, $sshKey ) : $([DateTime]::Now)"
	$rootDir = $pwd.Path
	
    # Run test script
    $sts = ./setupScripts/Shielded_template_prepare.ps1 -vmName 'Shielded_PRE-TDC' -hvServer 'localhost' `
        -testParams "rootDir=${rootDir}; sshKey=${sshKey}; snapshotName=ICABase"
    if (-not $sts[-1]) {
        return $false
    }

    return $sts[-1]    
}