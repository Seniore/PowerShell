Add-PSSnapin vmware.vimautomation.core
Connect-Viserver localhost
#####################################  
 ## http://kunaludapi.blogspot.com  
 ## Version: 1  
 ## Tested this script on  
 ##  1) Powershell v3  
 ##  2) Powercli v5.5  
 ##  3) Vsphere 5.x  
 ####################################
 function Get-VMinventory {  
 function Get-RDMDisk {  
   [CmdletBinding()]  
   param (  
     [Parameter(Mandatory=$True)]  
     [string[]]$VMName  
     )  
         $RDMInfo = Get-VM -Name $VMName | Get-HardDisk -DiskType RawPhysical, RawVirtual  
         $Result = foreach ($RDM in $RDMInfo) {  
          "{0}/{1}/{2}/{3}"-f ($RDM.Name), ($RDM.DiskType),($RDM.Filename), ($RDM.ScsiCanonicalName)     
         }  
         $Result -join (", ")  
 }  
 function Get-vNicInfo {  
   [CmdletBinding()]  
   param (  
     [Parameter(Mandatory=$True)]  
     [string[]]$VMName  
     )  
         $vNicInfo = Get-VM -Name $VMName | Get-NetworkAdapter  
         $Result = foreach ($vNic in $VnicInfo) {  
           "{0}={1}"-f ($vnic.Name.split("")[2]), ($vNic.Type)  
         }  
         $Result -join (", ")  
 }  
 function Get-InternalHDD {  
   [CmdletBinding()]  
   param (  
     [Parameter(Mandatory=$True)]  
     [string[]]$VMName  
     )  
         $VMInfo = Get-VMGuest -VM $VMName # (get-vm $VMName).extensiondata  
         $InternalHDD = $VMInfo.ExtensionData.disk   
         $result = foreach ($vdisk in $InternalHDD) {  
           "{0}={1}GB/{2}GB"-f ($vdisk.DiskPath), ($vdisk.FreeSpace /1GB -as [int]),($vdisk.Capacity /1GB -as [int])  
         }  
         $result -join (", ")  
 }  
   foreach ($vm in (get-vm)) {  
     $props = @{'VMName'=$vm.Name;  
           'IP Address'= $vm.Guest.IPAddress[0]; #$VM.ExtensionData.Summary.Guest.IpAddress  
           'PowerState'= $vm.PowerState;  
           'Domain Name'= ($vm.ExtensionData.Guest.Hostname -split '\.')[1,2] -join '.';            
           'vCPU'= $vm.NumCpu;  
           'RAM(GB)'= $vm.MemoryGB;  
           'Total-HDD(GB)'= $vm.ProvisionedSpaceGB -as [int];  
           'HDDs(GB)'= ($vm | get-harddisk | select-object -ExpandProperty CapacityGB) -join " + "            
           'Datastore'= (Get-Datastore -vm $vm) -split ", " -join ", ";  
           'Partition/Size' = Get-InternalHDD -VMName $vm.Name  
           'Real-OS'= $vm.guest.OSFullName;  
           'Setting-OS' = $VM.ExtensionData.summary.config.guestfullname;  
           'EsxiHost'= $vm.VMHost;  
           'vCenter Server' = ($vm).ExtensionData.Client.ServiceUrl.Split('/')[2].trimend(":443")  
           'Hardware Version'= $vm.Version;  
           'Folder'= $vm.folder;  
           'MacAddress' = ($vm | Get-NetworkAdapter).MacAddress -join ", ";  
           'VMX' = $vm.ExtensionData.config.files.VMpathname;  
           'VMDK' = ($vm | Get-HardDisk).filename -join ", ";  
           'VMTools Status' = $vm.ExtensionData.Guest.ToolsStatus;  
           'VMTools Version' = $vm.ExtensionData.Guest.ToolsVersion;  
           'VMTools Version Status' = $vm.ExtensionData.Guest.ToolsVersionStatus;  
           'VMTools Running Status' = $vm.ExtensionData.Guest.ToolsRunningStatus;  
           'SnapShots' = ($vm | get-snapshot).count;  
           'DataCenter' = $vm | Get-Datacenter;  
           'vNic' = Get-VNICinfo -VMName $vm.name;  
           'PortGroup' = ($vm | Get-NetworkAdapter).NetworkName -join ", ";  
           'RDMs' = Get-RDMDisk -VMName $VM.name  
           #'Department'= ($vm | Get-Annotation)[0].value;  
           #'Environment'= ($vm | Get-Annotation)[1].value;  
           #'Project'= ($vm | Get-Annotation)[2].value;  
           #'Role'= ($vm | Get-Annotation)[3].value;  
           }  
     $obj = New-Object -TypeName PSObject -Property $Props  
     Write-Output $obj | select-object -Property 'VMName', 'IP Address', 'Domain Name', 'Real-OS', 'vCPU', 'RAM(GB)', 'Total-HDD(GB)' ,'HDDs(GB)', 'Datastore', 'Partition/Size', 'Hardware Version', 'PowerState', 'Setting-OS', 'EsxiHost', 'vCenter Server', 'Folder', 'MacAddress', 'VMX', 'VMDK', 'VMTools Status', 'VMTools Version', 'VMTools Version Status', 'VMTools Running Status', 'SnapShots', 'DataCenter', 'vNic', 'PortGroup', 'RDMs' # 'Folder', 'Department', 'Environment' 'Environment'  
   }  
 }  
 Get-VMinventory   