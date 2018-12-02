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

$updateISOPath = '[Crucial] ISO\VMware-vCenter-Server-Appliance-6.0.0.30800-9448190-patch-FP.iso'
$vCenter = '192.168.0.18'
$user = 'root'
$password = 'VMware1!'
$rebootWithoutAsking = $true

$vCenterVM = 'psc6'
$vcsaFQDN = 'psc.seniore.internal'
$manageUpdateURL = 'https://'+$vcsaFQDN+':5480/vami/backend/manage-update.py'
$manageActionsURL = 'https://'+$vcsaFQDN+':5480/vami/backend/manage-actions.py'
$summaryURL = 'https://'+$vcsaFQDN+':5480/vami/backend/summary.py'

Write-Host 'Connecting to managing vCenter'
try {
    Connect-VIServer $vCenter -user $user -password $password -ErrorAction Stop
    }
catch [VMware.VimAutomation.ViCore.Types.V1.ErrorHandling.InvalidLogin] {
     Write-Warning "Unable to login to vCenter due to an invalid login. Please check user name and password variables." 
     break
    }
catch [VMware.VimAutomation.Sdk.Types.V1.ErrorHandling.VimException.ViServerConnectionException] {
     Write-Warning "Unable to connect to the managing vCenter. Please verify the URL and check if vCenter is running" 
     Write-Warning $_.Exception.InnerException.Message
     break
     }
catch {
    #$Error[0] | fl * -Force
    #$sxErrpr = $Error[0]
    #$sxException = $_
    Write-Warning "Oops... Unhandled Error"
    Write-Warning $_.Exception.Message
    Write-Host $_.Exception.GetType().FullName
    break
}


Write-Host 'Mounting ISO'
$CD = Get-VM -Name $vCenterVM | Get-CDDrive
Set-CDDrive -CD $CD -IsoPath $updateISOPath -Connected $true -Confirm:$false

#Get credentials and set auth header
$Credential = Get-Credential -Message 'Please provide root password for VAMI' -Username root 
$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Credential.UserName+':'+$Credential.GetNetworkCredential().Password))
$authHead = @{
'Authorization' = "Basic $auth"
}

#Authenticate against vCenter
$vCenterURL = 'https://'+$vcsaFQDN+':5480/vami/backend/administration-page.py'
$data = '<?xml version="1.0" encoding="utf-8"?><request><locale>en-US</locale><action>query</action><requestid>authenticate</requestid></request>'
try {
    $r = Invoke-WebRequest -Uri $vCenterURL -Method Post -Headers $authHead -Body $data -SessionVariable websession
}
catch [System.Net.WebException] {
    Write-Warning $_.Exception.Message
    if($_.Exception.Message -match '.*\(401\) Unauthorized.*') { Write-Warning 'Please verify user name and password for VAMI' }
}   
catch {
    Write-Warning "Oops... Unhandled Error"
    Write-Warning $_.Exception.Message
    Write-Host $_.Exception.GetType().FullName
    break
}
$cookies = $websession.Cookies.GetCookies($vCenterURL) 
$cookie = New-Object System.Net.Cookie 
$cookie.Name = "username"
$Text = 'root' + [Math]::Floor([decimal](Get-Date(Get-Date).ToUniversalTime()-uformat "%s"))
$EncodedText = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text))
$cookie.Value = $EncodedText
$cookie.Domain = ($cookies | Where {$_.Name -eq 'appliance-ui-sessionid'}).Domain
$websession.Cookies.Add($cookie);

$head = @{
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