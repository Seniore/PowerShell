#Version 20160623.1  - Added problematic hosts and verification of only shared storage
if(-not (Get-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) {    Add-PSSnapin VMware.VimAutomation.Core  }
if ($Global:DefaultVIServers.count -lt 1) { Write-Host "Please connect to a vCenter"; exit; }

$is_error = $false
$allEsxi = Get-VMhost
$ds = Get-Datastore | where {$_.Extensiondata.Summary.MultipleHostAccess }
foreach ($datastore in $ds) {
	if ($datastore.ExtensionData.Host.Count -ne $allEsxi.Count) {
		$is_error = $true
		write-warning "$datastore is not connected to all ESXi hosts"
		}
	}
if (!$is_error) { write-host "All datastores are connected to all hosts" }

foreach ($esxi in $allEsxi) {
	if (($esxi | Get-Datastore | where {$_.Extensiondata.Summary.MultipleHostAccess}).Count -ne $ds.Count) {
		write-host "Problematic host: $esxi"
		}
	}
