##########################
# SRM network mappings
#Version: 0.3
#Author: github.com/Seniore
#Description:
#	Script to create SRM Network Mapping using API call AddNetworkMapping
#	It creates the mapping for one or both sides (variable: CreateReverse)
#	If required it can also create missing port groups on the recovery site (variable: CreateMissingPortGroups)
#
#script is based on: http://www.wolowicz.info/2013/10/site-recovery-manager-configuration-export-with-srm-api-5-0/
##########################
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
##########################
# Set basic variables
$srmServerLocal = "10.0.55.102"
$srmServerRemote = "10.0.55.101"

$vCenterLocal = "10.0.55.102"
$vCenterRemote = "10.0.55.101"

$local_dvs = 'dvSwitch'
$remote_dvs = 'dvSwitch-Prod'

$User = "administrator@vsphere.local"
$Password = 'Pa$$w0rd'

$CreateReverse = $True
$CreateMissingPortGroups = $True		#Creates the missing port groups only on the recovery site; If you have more port groups on the recovery site you could run the script from the recovery site (the site that has more port groups)

##########################
#Connect to vCenter servers
Write-Host -ForegroundColor Yellow "Connecting to vCenter servers..."
Try {
	Connect-VIServer $vCenterLocal -User $User -Password $Password -WarningAction SilentlyContinue
}
Catch [Exception] {
	Write-Host -BackgroundColor Red "Unable to connect to local vCenter $vCenterLocal"
	Write-Host -BackgroundColor Red $_.Exception.Message
	Write-Host -BackgroundColor Red "Stopping here..."
	Exit
}

Try {
	Connect-VIServer $vCenterRemote -User $User -Password $Password -WarningAction SilentlyContinue
}
Catch [Exception] {
	Write-Host -BackgroundColor Red "Unable to connect to remote vCenter $vCenterRemote"
	Write-Host -BackgroundColor Red $_.Exception.Message
	Write-Host -BackgroundColor Red "Stopping here..."
	Exit
}

##########################
# Check if VDSwitches are available
Write-Host -ForegroundColor Yellow "Veryfing existance of VDSwitches..."
$vds = Get-VDSwitch -Name $local_dvs -Server $vCenterLocal -ErrorAction SilentlyContinue
if(!$vds) {
	Write-Host -BackgroundColor Red "Unable to find local DVS $local_dvs"
	Write-Host -BackgroundColor Red $_.Exception.Message
	Write-Host -BackgroundColor Red "Stopping here..."
	Exit
}

$vds = Get-VDSwitch -Name $remote_dvs -Server $vCenterRemote -ErrorAction SilentlyContinue
if(!$vds) {
	Write-Host -BackgroundColor Red "Unable to find remote DVS $remote_dvs"
	Write-Host -BackgroundColor Red $_.Exception.Message
	Write-Host -BackgroundColor Red "Stopping here..."
	Exit
}
##########################
#Connect to local site
##########################
Write-Host -ForegroundColor Yellow "Connecting to local SRM ${srmServerAddr}..."
$web01 = New-WebServiceProxy("http://" + $srmServerLocal + ":9085/srm.wsdl") -Namespace SRM01

$srm01 = New-Object SRM01.Srmbinding
$srm01.url = "https://" + $srmServerLocal + ":9007"
$srm01.CookieContainer = New-Object System.Net.CookieContainer

$mof01 = New-Object SRM01.ManagedObjectReference
$mof01.type = "SrmServiceInstance"
$mof01.value = $mof01.type

$srmApi01 = ($srm01.RetrieveContent($mof01)).srmApi
$inventory01 =  ($srm01.RetrieveContent($mof01)).inventoryMapping

Try {
	$srm01.SRMLogin($srmApi01, $User, $Password)
	$srm01.SRMLoginRemoteSite($mof01, $User, $Password, "en_EN")	
}
Catch [Exception] {
	Write-Host -BackgroundColor Red "Unable to connect to remote SRM $srmServerAddr"
	Write-Host -BackgroundColor Red $_.Exception.Message
	Return
}
Write-Host -ForegroundColor Green "Connected to local SRM $srmServerAddr"

##########################
# Set PortGroup variables for local site
$pg01 = New-Object SRM01.ManagedObjectReference
$pg01.type = "DistributedVirtualPortgroup"
$pg02 = New-Object SRM01.ManagedObjectReference
$pg02.type = "DistributedVirtualPortgroup"

##########################
#Connect to remote site
##########################
Write-Host -ForegroundColor Yellow "Connecting to remote SRM ${srmServerAddr}..."
if ($CreateReverse) {
	$web02 = New-WebServiceProxy("http://" + $srmServerRemote + ":9085/srm.wsdl") -Namespace SRM02

	$srm02 = New-Object SRM02.Srmbinding
	$srm02.url = "https://" + $srmServerRemote + ":9007"
	$srm02.CookieContainer = New-Object System.Net.CookieContainer

	$mof02 = New-Object SRM02.ManagedObjectReference
	$mof02.type = "SrmServiceInstance"
	$mof02.value = $mof02.type

	$srmApi02 = ($srm02.RetrieveContent($mof02)).srmApi
	$inventory02 =  ($srm02.RetrieveContent($mof02)).inventoryMapping

	Try {
		$srm02.SRMLogin($srmApi02, $User, $Password)
		$srm02.SRMLoginRemoteSite($mof02, $User, $Password, "en_EN")
	}
	Catch [Exception] {
		Write-Host -BackgroundColor Red "Unable to connect to remote SRM $srmServerAddr"
		Write-Host -BackgroundColor Red $_.Exception.Message
		Return
	}
	Write-Host -ForegroundColor Green "Connected to remote SRM $srmServerAddr"

	##########################
	# Set PortGroup variables for remote site
	$rev_pg01 = New-Object SRM02.ManagedObjectReference
	$rev_pg01.type = "DistributedVirtualPortgroup"
	$rev_pg02 = New-Object SRM02.ManagedObjectReference
	$rev_pg02.type = "DistributedVirtualPortgroup"

}	


##########################
# Main code
##########################

$pGroups = Get-VDPortgroup -VDSwitch $local_dvs -Server $vCenterLocal | Where {$_.IsUplink -eq $False}
foreach ($portGroup in $pGroups) {
	$remotePG = Get-VDPortGroup -Name $portGroup.Name -VDSwitch $remote_dvs -ErrorAction SilentlyContinue
	if(!$remotePG -and $CreateMissingPortGroups) {
		write-host "Remote port group $portGroup not found... Creating..."
		New-VDPortgroup -VDSwitch $remote_dvs -Name $portGroup.Name -Server $vCenterRemote  -NumPorts $portGroup.NumPorts -VLanId $portGroup.ExtensionData.Config.DefaultPortConfig.Vlan.VlanId
		$remotePG = Get-VDPortGroup -Name $portGroup.Name -VDSwitch $remote_dvs -ErrorAction SilentlyContinue
		}
	if ($remotePG) {
		Write-Host "Creating mapping for $PortGroup"
		$pg01.value = $portGroup.ExtensionData.MoRef.value
		$pg02.value = $remotePG.ExtensionData.MoRef.value
		$srm01.AddNetworkMapping($inventory01, $pg01 , $pg02)
		if ($CreateReverse) {
			$rev_pg01.value = $portGroup.ExtensionData.MoRef.value
			$rev_pg02.value = $remotePG.ExtensionData.MoRef.value
			$srm02.AddNetworkMapping($inventory02, $rev_pg02, $rev_pg01)
		}
	}
}

###
#$protection01 = ($srm01.RetrieveContent($mof01)).protection
#$recovery01 = ($srm01.RetrieveContent($mof01)).recovery
#$srm01.AddNetworkMapping($inventory01, $pg01, $pg02)
#$srm01.ListInventoryMappings($protection01)
#$srm01.ListInventoryMappings($protection01).networks
