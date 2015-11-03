$VC=localhost
Connect-Viserver $VC

$report = @()
$SCRIPT_PARENT = Split-Path -Parent $MyInvocation.MyCommand.Definition 

#Get all Datastore Cluster
$dataStoreClusters = Get-DatastoreCluster
#save characteristics

#get all corresponding datastores:
ForEach ($dataStoreCluster in $dataStoreClusters) {
	ForEach ($child in $dataStoreCluster.ExtensionData.ChildEntity) {
		$info = "" | select DSCName, DSCCapacity, DSCUsedSpace, DSCFreeSpace, DSName, Capacity, Provisioned, Available 
		$info.DSCName = $dataStoreCluster.Name
		$info.DSCCapacity = $dataStoreCluster.CapacityGB
		$info.DSCFreeSpace = [math]::Round($dataStoreCluster.FreeSpaceGB,2)
		$info.DSCUsedSpace = [math]::Round($info.DSCCapacity - $info.DSCFreeSpace,2)
		$dataStore =  Get-Datastore -Id $child
		$info.DSName = $dataStore.Name 
		$info.Capacity = [math]::Round($dataStore.capacityMB/1024,2) 
		$info.Provisioned = [math]::Round(($dataStore.ExtensionData.Summary.Capacity - $dataStore.ExtensionData.Summary.FreeSpace + $dataStore.ExtensionData.Summary.Uncommitted)/1GB,2) 
		$info.Available = [math]::Round($dataStore.ExtensionData.Summary.FreeSpace/1GB,2) 
		$report += $info
		}
	}
	
$Date = Get-Date -Format "dd-MM-yyyy"
$outputfile = ($SCRIPT_PARENT + "\Datastore_Report_$($date).csv")
      
$report = $report | Sort-Object DSCName, DSName
$report | Export-Csv -path $outputfile -NoTypeInformation -Append
 



Disconnect-VIServer $VC -Confirm:$False