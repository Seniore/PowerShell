$startDate = (Get-Date -Year 2015 -Month 11 -Day 12 -Hour 12 -Minute 0 -Second 0).AddMinutes(-1)
$endDate = (Get-Date -Year 2015 -Month 11 -Day 12 -Hour 15 -Minute 0 -Second 0).AddMinutes(-1)

$vm_list = ('vm_name_1', 'vm_name_2')
#if you wish to have the stats for all VMs in a datastore uncomment the line below
#$vm_list = Get-VM -Datastore datastore_name
$results = @()
$vm_list | % {
	$vm = $_
	$stats = get-stat -Entity (Get-VM $vm) -Stat disk.maxTotalLatency.latest -Start $startDate -Finish $endDate
	$groups = $stats | Group-Object -Property {$_.Timestamp.Day, $_.Instance}
	$report = $groups | % {
	New-Object PSObject -Property @{
		Description = $_.Group[0].Description
		Entity = $_.Group[0].Entity
		EntityId = $_.Group[0].EntityId
		Instance = $_.Group[0].Instance
		MetricId = $_.Group[0].MetricId
		Timestamp = $_.Group[0].Timestamp.Date.AddHours($_.Group[0].Timestamp.Hour)
		Unit = $_.Group[0].Unit
		Value = ($_.Group | Measure-Object -Property Value -Max).Maximum
	}
}
	$results += $report
}
$results | Export-Csv "report-disk.csv" -NoTypeInformation -UseCulture
