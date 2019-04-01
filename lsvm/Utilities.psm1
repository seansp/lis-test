Write-Host "Utilities Loaded."


function Cleanup-VM ([string]$vmName)
{
    $vm = Get-VM -Name $vmName
    if( $vm )
    {
        Write-Host "VM $vmName -- exists."
        $hd = $vm.HardDrives[0].Path
        Write-Host "Hard Drive Location -- $hd"
        Write-Host "Stopping VM"
        Stop-VM $vm -TurnOff -ErrorAction SilentlyContinue
        Remove-VM $vm -Confirm:$false -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $hd -Force
    }
}




function FindVM( [string] $vmName )
{
    $vm = Get-VM -Name $vmName
    if( $vm )
    {
        $vmNic = $vm | Get-VMNetworkAdapter
        if( $vmNic )
        {
            $vmNic.IpAddresses[0]
        }
    }
}
