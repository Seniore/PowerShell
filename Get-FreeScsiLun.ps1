function Get-FreeScsiLun {
 
<#  
.SYNOPSIS  Find free SCSI LUNs  
.DESCRIPTION The function will find the free SCSI LUNs
  on an ESXi server
.NOTES  Author:  Luc Dekens  
.PARAMETER VMHost
    The VMHost where to look for the free SCSI LUNs  
.EXAMPLE
   PS> Get-FreeScsiLun -VMHost $esx
.EXAMPLE
   PS> Get-VMHost | Get-FreeScsiLun
#>
 
  param (
  [parameter(ValueFromPipeline = $true,Position=1)]
  [ValidateNotNullOrEmpty()]
  [VMware.VimAutomation.Client20.VMHostImpl]
  $VMHost
  )
 
  process{
    $storMgr = Get-View $VMHost.ExtensionData.ConfigManager.DatastoreSystem
 
    $storMgr.QueryAvailableDisksForVmfs($null) | %{
      New-Object PSObject -Property @{
        VMHost = $VMHost.Name
        CanonicalName = $_.CanonicalName
        Uuid = $_.Uuid
        CapacityGB = [Math]::Round($_.Capacity.Block * $_.Capacity.BlockSize / 1GB,2)
      }
    }
  }
}
