if(-not (Get-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) {    Add-PSSnapin VMware.VimAutomation.Core  }
if ($Global:DefaultVIServers.count -lt 1) { Write-Host "Please connect to a vCenter"; exit; }

$is_error = $false
$esxiCount = (Get-VMhost).Count
$ds = Get-Datastore
foreach ($datastore in $ds) {
	if ($datastore.ExtensionData.Host.Count -ne $esxiCount) {
		$error = $true
		write-warning "$datastore is not connected to all ESXi hosts"
		}
	}
if (!$is_error) { write-host "All datastores are connected to all hosts" }
