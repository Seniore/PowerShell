add-type -TypeDefinition  @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[System.Net.ServicePointManager]::Expect100Continue = $false; 
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Set-UseUnsafeHeaderParsing
{
    param(
        [Parameter(Mandatory,ParameterSetName='Enable')]
        [switch]$Enable,

        [Parameter(Mandatory,ParameterSetName='Disable')]
        [switch]$Disable
    )

    $ShouldEnable = $PSCmdlet.ParameterSetName -eq 'Enable'

    $netAssembly = [Reflection.Assembly]::GetAssembly([System.Net.Configuration.SettingsSection])

    if($netAssembly)
    {
        $bindingFlags = [Reflection.BindingFlags] 'Static,GetProperty,NonPublic'
        $settingsType = $netAssembly.GetType('System.Net.Configuration.SettingsSectionInternal')

        $instance = $settingsType.InvokeMember('Section', $bindingFlags, $null, $null, @())

        if($instance)
        {
            $bindingFlags = 'NonPublic','Instance'
            $useUnsafeHeaderParsingField = $settingsType.GetField('useUnsafeHeaderParsing', $bindingFlags)

            if($useUnsafeHeaderParsingField)
            {
              $useUnsafeHeaderParsingField.SetValue($instance, $ShouldEnable)
            }
        }
    }
}

Set-UseUnsafeHeaderParsing -Enable

<##################### Main code ###################>

$updateISOPath = '[Crucial] ISO\VMware-vCenter-Server-Appliance-6.5.0.23000-10964411-patch-FP.iso'
$vCenter = '192.168.0.18'
$user = 'root'
$password = 'VMware1!'
$rebootWithoutAsking = $true

#$vCenterVM = 'vcenter65-1'
#$vcsaFQDN = 'vcenter65-1.seniore.internal'
$vCenterVM = 'vcenter6'
$vcsaFQDN = 'vcenter.seniore.internal'
$manageUpdateURL = 'https://'+$vcsaFQDN+':5480/vami/backend/manage-update.py'
$manageActionsURL = 'https://'+$vcsaFQDN+':5480/vami/backend/manage-actions.py'
$summaryURL = 'https://'+$vcsaFQDN+':5480/vami/backend/summary.py'

Write-Host 'Connecting to managing vCenter'
Connect-VIServer $vCenter -user $user -password $password
Write-Host 'Mounting ISO'
$CD = Get-VM -Name $vCenterVM | Get-CDDrive
Set-CDDrive -CD $CD -IsoPath $updateISOPath -Connected $true -Confirm:$false

#Get credentials and set auth header
$Credential = Get-Credential
$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Credential.UserName+':'+$Credential.GetNetworkCredential().Password))
$authHead = @{
'Authorization' = "Basic $auth"
}

#Authenticate against vCenter
$vCenterURL = 'https://vcenter65-1.seniore.internal:5480/vami/backend/administration-page.py'
$data = '<?xml version="1.0" encoding="utf-8"?><request><locale>en-US</locale><action>query</action><requestid>authenticate</requestid></request>'
$r = Invoke-WebRequest -Uri $vCenterURL -Method Post -Headers $authHead -Body $data -SessionVariable websession
$cookies = $websession.Cookies.GetCookies($vCenterURL) 
$cookie = New-Object System.Net.Cookie 
$cookie.Name = "vami-session-token"
$cookie.Value = "0.07339520582454873"
$cookie.Domain = ($cookies | Where {$_.Name -eq 'appliance-ui-sessionid'}).Domain
$websession.Cookies.Add($cookie);

$head = @{
'appliance-ui-sessionid' = ($cookies | Where {$_.Name -eq 'appliance-ui-sessionid'}).Value;
'X-XSRF-TOKEN' = ($cookies | Where {$_.Name -eq 'XSRF-TOKEN'}).Value;
}

## Get current version
$data = '<?xml version="1.0" encoding="utf-8"?><request><locale>en-US</locale><action>query</action><requestid>summaryInfo</requestid></request>'
$r = Invoke-WebRequest -Uri $summaryURL -Method Post -Headers $head -Body $data -WebSession $websession
$healthStatus = (([xml]$r.Content).response.value | Where {$_.id -eq 'healthStatus'}).'#text'
$vcsaVersion = (([xml]$r.Content).response.value | Where {$_.id -eq 'version'}).'#text'
Write-Host "VCSA status is $healthStatus. Current version: $vcsaVersion"


## Check if VCSA needs to be rebooted after last update
Write-Host 'Checking if a reboot is pending'
$data = '<?xml version="1.0" encoding="utf-8" ?><request>    <locale>en-US</locale>    <action>query</action>    <requestid>rebootAfterUpdate</requestid></request>'
$r = Invoke-WebRequest -Uri $manageUpdateURL -Method Post -Headers $head -Body $data -WebSession $websession
$statusCode = (([xml]$r.Content).response.value | Where {$_.ID -eq 'rebootrequired'}).'#text'
if($statusCode -eq 'True') {
    if($rebootWithoutAsking -eq $false) {
        Write-Host 'A reboot of VCSA is required. Please confirm'
        $confirmation = Read-Host -Prompt "Continue? [y/n]"
        while($confirmation -notmatch "[yY]") {
            if ($confirmation -eq 'n') {exit}
            $confirmation = Read-Host "Continue? [y/n]"
        }   
    }
    ## Rebooting VCSA
    Write-Host 'Rebooting VCSA'
    $data = '<?xml version="1.0" encoding="utf-8"?><request><locale>en-US</locale><action>query</action><requestid>reboot</requestid></request>'
    try {
        $r = Invoke-WebRequest -Uri $manageActionsURL -Method Post -Headers $head -Body $data -WebSession $websession
    }
    catch {}
    #exit
}
else {
    Write-Host 'No reboot pending'
}

## Check if update is available

$data = '<?xml version="1.0" encoding="utf-8"?><request><locale>en-US</locale>   <action>query</action>   <requestid>checkUpdateCDROM</requestid></request>'
$r = Invoke-WebRequest -Uri $manageUpdateURL -Method Post -Headers $head -Body $data -WebSession $websession
$statusCode = ([xml]$r.Content).response.status.statusCode
if($statusCode -eq 'failure') {
    Write-Warning 'Please check if update ISO is mounted to VCSA'
    #exit
}


## Accept EULA
$data = '<?xml version="1.0" encoding="utf-8"?><request><locale>en-US</locale>   <action>query</action>   <requestid>AcceptEULA</requestid><value id="EULAAccepted">true</value></request>'
$r = Invoke-WebRequest -Uri $manageUpdateURL -Method Post -Headers $head -Body $data -WebSession $websession

## Skip CEIP
$data = '<?xml version="1.0" encoding="utf-8"?><request><locale>en-US</locale><action>submit</action><requestid>set_ceip_status</requestid><value id="ceip.status">False</value></request>'
$r = Invoke-WebRequest -Uri $summaryURL -Method Post -Headers $head -Body $data -WebSession $websession

## Perform the update
$data = '<?xml version="1.0" encoding="utf-8"?><request><locale>en-US</locale>   <action>query</action>   <requestid>installUpdateCDROM</requestid>   <value id="thirdParty">false</value></request>'
$r = Invoke-WebRequest -Uri $manageUpdateURL -Method Post -Headers $head -Body $data -WebSession $websession


## Check update progress
do {
    $data ='<?xml version="1.0" encoding="utf-8"?><request><locale>en-US</locale>   <action>query</action>   <requestid>getActiveUpdate</requestid></request>'
    try {
    $r = Invoke-WebRequest -Uri $manageUpdateURL -Method Post -Headers $head -Body $data -WebSession $websession
    }
    catch {

    }
    $sx = [xml]$r.Content
    $status = (([xml]$r.Content).response.value.value | Where {$_.id -eq 'status'}).'#text'
    $percentComplete = (([xml]$r.Content).response.value.value | Where {$_.id -eq 'percentComplete'}).'#text'
    if($status) { Write-Host $status $percentComplete"%" }
    sleep 30
}while($status -eq 'running') 

##Final progress check
$data = '<?xml version="1.0" encoding="utf-8"?><request><locale>en-US</locale>   <action>query</action>   <requestid>getLastUpdate</requestid></request>'
$r = Invoke-WebRequest -Uri $manageUpdateURL -Method Post -Headers $head -Body $data -WebSession $websession
$status = (([xml]$r.Content).response.value.value | Where {$_.id -eq 'status'}).'#text'
$percentComplete = (([xml]$r.Content).response.value.value | Where {$_.id -eq 'percentComplete'}).'#text'
Write-Host $status $percentComplete "%"

## Check if VCSA needs to be rebooted after last update
Write-Host 'Checking if a reboot is pending'
$data = '<?xml version="1.0" encoding="utf-8" ?><request>    <locale>en-US</locale>    <action>query</action>    <requestid>rebootAfterUpdate</requestid></request>'
$r = Invoke-WebRequest -Uri $manageUpdateURL -Method Post -Headers $head -Body $data -WebSession $websession
$statusCode = (([xml]$r.Content).response.value | Where {$_.ID -eq 'rebootrequired'}).'#text'
if($statusCode -eq 'True') {
    if($rebootWithoutAsking -eq $false) {
        Write-Host 'A reboot of VCSA is required. Please confirm'
        $confirmation = Read-Host -Prompt "Continue? [y/n]"
        while($confirmation -notmatch "[yY]") {
            if ($confirmation -eq 'n') {exit}
            $confirmation = Read-Host "Continue? [y/n]"
        }   
    }
    ## Rebooting VCSA
    Write-Host 'Rebooting VCSA'
    $data = '<?xml version="1.0" encoding="utf-8"?><request><locale>en-US</locale><action>query</action><requestid>reboot</requestid></request>'
    try {
        $r = Invoke-WebRequest -Uri $manageActionsURL -Method Post -Headers $head -Body $data -WebSession $websession
    }
    catch {}
    #exit
}
else {
    Write-Host 'No reboot pending'
}




<#

####################
$healthURL = 'https://vcenter65-1.seniore.internal:5480/rest/com/vmware/appliance/health/system?~action=get'
Invoke-WebRequest -Uri $healthURL -Method Post -WebSession $websession

$lastCheckURL = 'https://vcenter65-1.seniore.internal:5480/rest/com/vmware/appliance/health/system?~action=lastcheck'
$r = Invoke-WebRequest -Uri $lastCheckURL -Method Post -WebSession $websession

####################
$summaryURL = 'https://vcenter65-1.seniore.internal:5480/vami/backend/summary.py'
$head = @{
'Accept' = 'application/json, text/plain, */*';
'Accept-Encoding' = 'gzip, deflate, br';
'Accept-Language' = 'en-US,en;q=0.96,pl-PL;q=0.91,pl;q=0.87,de-DE;q=0.83,de;q=0.78,fr-FR;q=0.74,fr;q=0.7,en-GB;q=0.65,en-NZ;q=0.61,ru-RU;q=0.57,ru;q=0.52,en-EN;q=0.48,cs-CZ;q=0.43,cs;q=0.39,nb-NO;q=0.35,nb;q=0.3,en-AU;q=0.26,ar-AE;q=0.22,ar;q=0.17,nl-NL;q=0.13,nl;q=0.09,de-DE-sie;q=0.04';
'appliance-ui-sessionid' = ($cookies | Where {$_.Name -eq 'appliance-ui-sessionid'}).Value;
'Content-Type' = 'application/json;charset=utf-8';
'X-XSRF-TOKEN' = ($cookies | Where {$_.Name -eq 'XSRF-TOKEN'}).Value;
'Authorization' = '';
'Host' = 'vcenter65-1.seniore.internal:5480';
'Origin' = 'https://vcenter65-1.seniore.internal:5480';
'Referer' = 'https://vcenter65-1.seniore.internal:5480/';
}

$data = '<?xml version="1.0" encoding="utf-8"?><request><locale>en-US</locale><action>query</action><requestid>summaryInfo</requestid></request>'
#$data = '<?xml version="1.0" encoding="utf-8"?><request><locale>en-US</locale><action>query</action><requestid>ssoInfo</requestid></request>'

Invoke-WebRequest -Uri $summaryURL -Method Put -Body $data -Headers $head -WebSession $websession
$r = Invoke-WebRequest -Uri $summaryURL -Method Post -Body $data -Headers $head -WebSession $websession 


###
$TestURL = 'https://vcenter65-1.seniore.internal:5480/vami/backend/manage-update.py'
$data = '<?xml version="1.0" encoding="utf-8" ?><request>    <locale>en-US</locale>    <action>query</action>    <requestid>rebootAfterUpdate</requestid></request>'
Invoke-WebRequest -Uri $TestURL -Method Post -Body $data -Headers $head -SessionVariable $websession

$myURL = 'https://vcenter65-1.seniore.internal:5480/partials/appliance.html'
Invoke-WebRequest -Uri $myURL -Method Post  -Headers $head -SessionVariable $websession
$myURL = 'https://vcenter65-1.seniore.internal:5480/app/views/tabs/Summary.html'
Invoke-WebRequest -Uri $myURL -Method Post  -Headers $head -SessionVariable $websession

$myURL = 'https://vcenter65-1.seniore.internal:5480/'
Invoke-WebRequest -Uri $myURL -Method Get 

#>