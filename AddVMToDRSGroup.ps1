Add-PSSnapin VMware.VimAutomation.Core
$user = 'administrator@vsphere.local'
$pass = 'VMware1!'
Connect-viserver 10.0.0.3 -user $user -Password $pass


Function AddVMToDRSGRoup
{
  param(
    [Parameter(Mandatory = $True, Position = 0, ValueFromPipelineByPropertyName=$True)]
    [ValidateNotNullOrEmpty()]
    [string]${Name},
    [PSObject[]]${Cluster},
    [PSObject[]]${VM}
)
Process{

$oCluster = Get-Cluster $Cluster
#Refresh view
$oCluster.ExtensionData.UpdateViewData("ConfigurationEx")
$vmGroup = $oCluster.ExtensionData.ConfigurationEx.Group | Where-Object -FilterScript {($_ -is [VMware.Vim.ClusterVmGroup]) -and ($_.Name -like ${Name})}

Write-Host "Currently the group ${vmGroupName} contains" $vmGroup.Vm.Count "VM(s)"
$vmid = (get-view -ViewType "VirtualMachine" | Where-Object -FilterScript {($_.Name -eq ${VM_to_add})}).MoRef

$spec = New-Object VMware.Vim.ClusterConfigSpecEx
$groupSpec = New-Object VMware.Vim.ClusterGroupSpec
$groupSpec.Operation = [VMware.Vim.ArrayUpdateOperation]::edit
$groupSpec.Info = $vmGroup
$groupSpec.Info.VM += $vmid
$spec.GroupSpec += $groupSpec
$oCluster.ExtensionData.ReconfigureComputeResource($spec,$True)
    }
}


$ClusteName = 'Cluster'
$vmGroupName = 'VM_GROUP_A'
$VM_to_add = 'vum'

AddVMToDRSGRoup -Cluster $ClusteName -Name $vmGroupName -VM $VM_to_add -Append