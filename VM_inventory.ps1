@"
===============================================================================
Title:         VM_Inventory.ps1
Description:   Exports VM Information from vCenter into a .CSV file for importing into anything
Usage:         .\VM_Inventory.ps1
Date:          01/Oct/2014
===============================================================================
"@


Write-Host ""
Write-Host ""
Write-Host "Script Started at - $(Get-date -format "dd-MMM-yyyy HH:mm:ss")" -foregroundcolor white -backgroundcolor Green


if(-not (Get-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue))
{
   Add-PSSnapin VMware.VimAutomation.Core 
}

$SCRIPT_PARENT   = Split-Path -Parent $MyInvocation.MyCommand.Definition 
 

$VCs= Get-Content ($SCRIPT_PARENT + "\VC_List.txt") -ErrorAction SilentlyContinue # mention vcenter name where you want to check resources.

Foreach($VC in $VCs){

If(Test-Connection $VC -Quiet -Count 1  ){


Write-Host "..Connecting to VC >> $VC"
$VC_Connect = Connect-VIServer $VC -WarningAction 0
}

Else {
    Write-Host ">>> VC is not available " -NoNewline -ForegroundColor Red ;Write-Host ": $($VC) " -ForegroundColor Yellow 

}

If($VC_Connect.IsConnected){


$VMFolder = "*"

 #"
 
$Report = @()
$VMs = Get-Folder $VMFolder | Get-VM

Write-Host "...Counting Total VMs." 
 $i = 0
 $E = 0
 $count = $vms.Count
 $E = $count

 Write-Host ""
 Write-Host "-----------------------------"
 Write-Host "Total Count of VMs - $count"
 Write-Host "-----------------------------"


$Datastores = Get-Datastore | select Name, Id
$VMHosts = Get-VMHost | select Name, Parent
 
#ForEach($Datastores in Get-Datastore | select Name, Id){
ForEach ($VM in $VMs) {

$i++

Write-Progress -activity "Listing VMs from VC > $VC" 1 -status "Checking for VM: ($i of $E) >> $VM" -perc (($i / $E)*100)


      $VMView = $VM # | Get-View
      #Write-Host "1" # to check the flow
      $VMInfo = {} | Select VC_Name,VMName,Powerstate,OS,IPAddress,ToolVersion,ToolsStatus,VMVersion, Host,Cluster,Datastore,Num_CPU,CPUSocket, CorePerSocker, Mem_GB,TotalDisk,DiskGb, DiskFree, DiskUsed
      # Write-Host "2" # to check the flow
      $VMInfo.VC_Name = $vc
      $VMInfo.VMName = $vm.name
      $VMInfo.Powerstate = $vm.Powerstate
      $VMInfo.OS = $vm.Guest.OSFullName
      #$VMInfo.Folder = ($vm | Get-Folder).Name
      $VMInfo.IPAddress = $vm.Guest.IPAddress[0]
      $VMInfo.ToolVersion = ($VM | % { get-view $_.id }).Guest.ToolsVersion
      $VMInfo.ToolsStatus = ($VM | % { get-view $_.id }).Guest.ToolsStatus
      $VMInfo.VMVersion = $vm.Version
      $VMInfo.Host = $vm.vmhost.name
      $VMInfo.Cluster = $vm.vmhost.Parent.Name
      #$VMInfo.Datastore = ($Datastores | where {$_.ID -match (($vmview.Datastore | Select -First 1) | Select Value).Value} | Select Name).Name
      $VMInfo.Datastore = ($VM | Get-Datastore).Name
     #  Write-Host "3" # to check the flow
      $VMInfo.Num_CPU = $vm.NumCPU
	  $VMInfo.CPUSocket = $vm.ExtensionData.config.hardware.NumCPU/$vm.ExtensionData.Config.Hardware.NumCoresPerSocket
	  $VMInfo.CorePerSocker = $vm.ExtensionData.Config.Hardware.NumCoresPerSocket
      $VMInfo.Mem_GB = [Math]::Round(($vm.MemoryMB/1024),2)
      $VMInfo.TotalDisk = [Int]($vm.HardDisks).Count 
      $VMInfo.DiskGb = [Math]::Round((($vm.HardDisks | Measure-Object -Property CapacityKB -Sum).Sum * 1KB / 1GB),2)
      $VMInfo.DiskFree = [Math]::Round((($vm.Guest.Disks | Measure-Object -Property FreeSpace -Sum).Sum / 1GB),2)
      $VMInfo.DiskUsed = $VMInfo.DiskGb - $VMInfo.DiskFree
      $Report += $VMInfo
     # Write-Host "4..COllected all properties.." # to check the flow
}
#}
        $Date = Get-Date -Format "dd-MM-yyyy"
        $outputfile = ($SCRIPT_PARENT + "\VM_Inventory_Report_$($date).csv")
      
      $Report = $Report | Sort-Object VMName
      $report | Export-Csv -path $outputfile -NoTypeInformation -Append
 



Disconnect-VIServer $VC -Confirm:$False
}
Else {
    Write-Host ">>> Connection to " -NoNewline -ForegroundColor Red ;Write-Host ": $($VC) " -nonewline -ForegroundColor Yellow ;Write-Host " Failed." -ForegroundColor Red

}

}

Write-Host "................................................."
Write-Host "__ JOB DONE __" -ForegroundColor Green

Write-Host "Script Ended at - $(Get-date -format "dd-MMM-yyyy HH:mm:ss")" -foregroundcolor white -backgroundcolor red

Write-Host "===============================================================================" # 80 * =