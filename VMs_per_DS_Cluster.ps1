Connect-VIServer vcenter_host

$dsClusters = ('DS_CLUSTER_NAME')

##Temp hash array to speed up the script
$sxHashArray = @{}
ForEach ($dsClusterName in $dsClusters) {
	$sxDatastores = Get-DatastoreCluster -Name $dsClusterName | Get-DataStore
	Foreach ($sxDS in $sxDatastores) {
		$sxHashArray[$sxDS.Name] = $dsClusterName
	}
}
	
## Main loop

$VmInfo = ForEach ($dsClusterName in $dsClusters) {
$sxDataStoreCluster = Get-DataStoreCluster -Name $dsClusterName
ForEach ($VM in ($sxDataStoreCluster | Get-VM | Sort-Object -Property Name)) {
	ForEach ($HardDisk in ($VM | Get-HardDisk | Sort-Object -Property Name)) {
        "" | Select-Object -Property @{N="VM";E={$VM.Name}},
          @{N="Hard Disk";E={$HardDisk.Name}},
          @{N="DS Cluster";E={$sxHashArray[$HardDisk.FileName.Split("]")[0].TrimStart("[")]}},
          @{N="Datastore";E={$HardDisk.FileName.Split("]")[0].TrimStart("[")}},
          @{N="VMDKpath";E={$HardDisk.FileName}}
      }
    }
}

#================================================
# HTML Stuff
#================================================
	
	$head = '
		<style>
 		body { 	font: normal 11px auto "Trebuchet MS", Verdana, Arial, Helvetica, sans-serif;  color: #4f6b72; 	background: #E6EAE9; }
		caption { padding: 0 0 5px 0; width: 700px;	font: italic 11px "Trebuchet MS", Verdana, Arial, Helvetica, sans-serif; text-align: right; }
		th { font: bold 11px "Trebuchet MS", Verdana, Arial, Helvetica, sans-serif; color: #4f6b72; border-right: 1px solid #C1DAD7; border-bottom: 1px solid #C1DAD7;
		border-top: 1px solid #C1DAD7; letter-spacing: 2px; text-transform: uppercase; text-align: left; padding: 6px 6px 6px 12px; background: #CAE8EA; }
		td { border-right: 1px solid #C1DAD7; border-bottom: 1px solid #C1DAD7;	background: #fff; padding: 6px 6px 6px 12px; color: #4f6b72; }
		.error {color:red; font-weight:bold;}
		</style>
		'
	$header = "<h1>VM List</h1>"
			   
	$title = "VM List"

$VMInfo | ConvertTo-HTML -Head $head -title $title -Body $header  | foreach {$_.replace("&lt;","<").replace("&gt;",">").replace("&quot;",'"')} |  Set-Content .\VmQuery.html
$VmInfo | Export-Csv -NoTypeInformation -UseCulture -Path "VmQuery.csv"
