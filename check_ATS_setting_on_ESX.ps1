<#
This script checks the ATS setting on a ESXi hosts
http://kb.vmware.com/selfservice/microsites/search.do?language=en_US&cmd=displayKC&externalId=2113956

http://blogs.vmware.com/vsphere/2012/05/vmfs-locking-uncovered.html

#>

$sx_hosts = Get-VMHost 
$sx_results = @()
foreach ($sx_host in $sx_hosts) {
	$result = Get-AdvancedSetting -Entity $sx_host -Name VMFS3.UseATSForHBOnVMFS5
	$output = "" | select Host, Setting, Value
    $output.Host = $sx_host.Name
    $output.Setting = $result.Name
    $output.Value = $result.Value
	$sx_results += $output
    }
$sx_results | Export-Csv "ATS.csv" -NoTypeInformation -UseCulture
