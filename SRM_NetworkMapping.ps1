#################
#Script to create SRM network mappings
#Author: Marcin@Raubal.pl
#script is based on: http://www.wolowicz.info/2013/10/site-recovery-manager-configuration-export-with-srm-api-5-0/
#################
# Set variables
$srmServerLocal = "10.0.55.102"
$srmServerRemote = "10.0.55.101"

$User = "administrator@vsphere.local"
$Password = 'Pa$$w0rd'

##########################
#Connect to local site
##########################
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
Write-Host -ForegroundColor Yellow "Connected to local SRM $srmServerAddr"

##########################
#Connect to remote site
##########################
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
Write-Host -ForegroundColor Yellow "Connected to remote SRM $srmServerAddr"
	
#-----------------
# Set variables for local site
$pg01 = New-Object SRM01.ManagedObjectReference
$pg01.type = $pg1.ExtensionData.MoRef.type
$pg01.value = $pg1.ExtensionData.MoRef.value
$pg02 = New-Object SRM01.ManagedObjectReference
$pg02.type = $pg2.ExtensionData.MoRef.type
$pg02.value = $pg2.ExtensionData.MoRef.value

#---------------
# Set variables for remote site
$rev_pg01 = New-Object SRM02.ManagedObjectReference
$rev_pg01.type = $pg1.ExtensionData.MoRef.type
$rev_pg01.value = $pg1.ExtensionData.MoRef.value
$rev_pg02 = New-Object SRM02.ManagedObjectReference
$rev_pg02.type = $pg2.ExtensionData.MoRef.type
$rev_pg02.value = $pg2.ExtensionData.MoRef.value 

#-------------------------
# Start the show
$local_dvs = 'dvSwitch'
$remote_dvs = 'dvSwitch-Prod'
$pGroups = Get-VDPortgroup -VDSwitch $local_dvs | Where {$_.Name -match "^dvPortGroup-.*"}
foreach ($portGroup in $pGroups) {
	$remotePG = Get-VDPortGroup -Name $portGroup.Name -VDSwitch $remote_dvs
	if ($remotePG) {
		Write-Host "Creating mapping for $PortGroup"
		$pg01.value = $portGroup.ExtensionData.MoRef.value
		$pg02.value = $remotePG.ExtensionData.MoRef.value
		$rev_pg01.value = $portGroup.ExtensionData.MoRef.value
		$rev_pg02.value = $remotePG.ExtensionData.MoRef.value
		$srm01.AddNetworkMapping($inventory01, $pg01 , $pg02)
		$srm02.AddNetworkMapping($inventory02, $rev_pg02, $rev_pg01)
	}
}

###
#$protection01 = ($srm01.RetrieveContent($mof01)).protection
#$recovery01 = ($srm01.RetrieveContent($mof01)).recovery
#$srm01.AddNetworkMapping($inventory01, $pg01, $pg02)
#$srm01.ListInventoryMappings($protection01)
#$srm01.ListInventoryMappings($protection01).networks
