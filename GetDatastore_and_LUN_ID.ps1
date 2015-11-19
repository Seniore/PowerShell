$esxName = "my_esx_hosts"
Get-VMHost -Name $esxName | Get-Datastore | 
Where-Object {$_.ExtensionData.Info.GetType().Name -eq "VmfsDatastoreInfo"} |
ForEach-Object { 
	if ($_)	{
		$_.ExtensionData.Info.Vmfs.Extent |	Select-Object -Property @{Name="Name";Expression={$Datastore.Name}}, DiskName
	}
}
