Add-PSSnapin VMware.VimAutomation.Core
Connect-Viserver 10.0.0.3 -User administrator@vsphere.local -Password 'VMware1!'

$VM = "testVM"
$ESXiPass = "VMWare1!"
$ESXiHost = "esxi01.seniore.internal"
$VMUser = "Administrator"
$VMPass = "VMware1!"
#===== IR Config
$IR_IP = "192.168.200.32"
$IR_GW = "192.168.200.1"
$IR_Mask = "26"
$IR_DNS ='“10.0.0.1”,”10.0.0.2”'
$DNS_Suffix = '"seniore.internal","lab.seniore.internal"'
$Specific_Suffix = 'seniore.internal'
#=====IBR Config
$IBR_IP = "172.16.0.32"
$IBR_Mask = "26"
$IBR_Specific_Suffix = 'lab.seniore.internal'

#=====functions
Function WaitForVM ($VMName) {
do {
$VM = Get-VM $VMName
$Toolsstatus = $VM.ExtensionData.Guest.ToolsRunningStatus
Write-Host "Waiting for $VM to start, tools status is $Toolsstatus"
Sleep 7
} until ($Toolsstatus -eq "guestToolsRunning")
}

#=====main code
#Pre-check
$gvm = Get-VM $VM
#Check hostname
if($gvm.Guest.HostName -notmatch '^WIN-.*') { Write-Warning "Suspissious hostname... Exiting here..."; 
    #exit(1)
   }
else { Write-Host "VM name OK: " $gvm.Guest.HostName }
#check IP address
$nonAPIPA = $gvm.Guest.IPAddress | Where {$_ -notmatch '::' -and $_ -notmatch "^169.254"}
$APIPA = $gvm.Guest.IPAddress | Where {$_ -notmatch '::' -and $_ -match "^169.254"}
if($nonAPIPA.Count -ne 0 -and $APIPA -ne 2) { Write-Warning "Somethings wrong with the IPs... Exiting here..." ;
    Write-Host $gvm.Guest.IPAddress | Where {$_ -notmatch '::'}
    #exit(1)
}
#Sysprep
$script = 'C:\Windows\System32\Sysprep\sysprep.exe /quiet /oobe /generalize /reboot'
Invoke-VMScript -VM $VM -HostUser root -HostPassword $ESXiPass -GuestUser $VMUser -GuestPassword $VMPass -ScriptType bat -ScriptText $script -ErrorAction "SilentlyContinue"
Start-Sleep 30
WaitForVM $VM

#Set new hostname
$script = "Rename-Computer -NewName $VM"
Invoke-VMScript -VM $VM -HostUser root -HostPassword $ESXiPass -GuestUser $VMUser -GuestPassword $VMPass -ScriptType PowerShell -ScriptText $script -ErrorAction "SilentlyContinue"

#Network Adapter Config
$adapterCount = (Get-NetworkAdapter $VM).Count
if($adapterCount -eq 2) {
    #Find adapters
    $IBRAdapter = Get-NetworkAdapter $VM | Where {$_.NetworkName -like "*IBR*"}
	$IRAdapter = Get-NetworkAdapter $VM | Where {$_.NetworkName -notlike "*IBR*"}
    #Configure IR
	$script =  'Get-NetAdapter | Where {$_.MacAddress -eq "' + $IRAdapter.MacAddress.Replace(':','-') + '" } | %{
        New-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 –IPAddress ' + "$IR_IP -PrefixLength $IR_Mask -DefaultGateway $IR_GW" + '
        Rename-NetAdapter -Name $_.Name -NewName "IR"
        Set-NetIPInterface -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -InterfaceMetric 1
        Set-DNSClientServerAddress –interfaceIndex $_.ifIndex –ServerAddresses ('+$IR_DNS+')
        Set-DnsClient –interfaceIndex $_.ifIndex -RegisterThisConnectionsAddress $False -ConnectionSpecificSuffix ' + $Specific_Suffix +"
        Set-DnsClientGlobalSetting -SuffixSearchList @(" + $DNS_Suffix + ')
        Disable-NetAdapterBinding -Name IR -DisplayName "Internet Protocol Version 6 (TCP/IPv6)"
         }'
    #$script
    Invoke-VMScript -VM $VM -HostUser root -HostPassword $ESXiPass -GuestUser $VMUser -GuestPassword $VMPass -ScriptType PowerShell -ScriptText $script
    #Configure IBR
    $script =  'Get-NetAdapter | Where {$_.MacAddress -eq "' + $IBRAdapter.MacAddress.Replace(':','-') + '" } | %{
        New-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 –IPAddress ' + "$IBR_IP -PrefixLength $IBR_Mask" + '
        Rename-NetAdapter -Name $_.Name -NewName "IBR"
        Set-DnsClient –interfaceIndex $_.ifIndex –RegisterThisConnectionsAddress $False -ConnectionSpecificSuffix ' + $IBR_Specific_Suffix +'
        Disable-NetAdapterBinding -Name IBR -DisplayName "Internet Protocol Version 6 (TCP/IPv6)"
         }'
    
    Invoke-VMScript -VM $VM -HostUser root -HostPassword $ESXiPass -GuestUser $VMUser -GuestPassword $VMPass -ScriptType PowerShell -ScriptText $script
}



