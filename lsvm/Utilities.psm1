Write-Host "Utilities Loaded."

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
