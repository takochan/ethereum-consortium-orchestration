<#
.SYNOPSIS
    Script to deploy an Ethereum consortium blockchain
.DESCRIPTION
    Script to deploy participants of an Ethereum consortium blockchain
     - A new consortium (initial member plus dashboard / bootnode)
     - A minimal consortium (mainly for testing as a full deployment is lengthy)
     - Add a new member to an existing consortium
.PARAMETER rgName
    The name of a resource group to deploy to. This resource group will be created.
.PARAMETER location
    The Azure location in which to create the resource group.
.PARAMETER subName
    If provided, the subscription name to switch to before deployment.
.PARAMETER sqlAdminLogin
    The Sql Database Admin username
.PARAMETER databaseName
    The SQL Database database name
.PARAMETER chosenDeploymentType
    The type of deployment required:
     - founder: The deployment of a founder node including Ethereum components with boot node, web components and Dev VM / jump box
      - A founder deployment depends on the "template.consortium.params.json" parameters file
     - newmember: An additional member node with Ethereum components (no boot node) and web components
      - A newmember deployment depends on the "template.consortium.params.participant1.json" parameters file
     - minimal: Minimal deployment of Ethereum components only, mainly for testing purposes
      - A minimal deployment depends on the "template.consortium.params.json" parameters file
.PARAMETER contentRoot
    The contentRootOverride URL from the template parameters
.PARAMETER devVmDnsLabelPrefix
    The DNS label prefix for the Dev VM / Jump Box. Must be unqiue.
.PARAMETER devVmPassword
    The Dev VM / Jump Box password.
.PARAMETER devVmAdminUsername
    The Dev VM / Jump Box admin username.
.PARAMETER devVmVnetName
    The vnet name to which the Dev VM / Jump Box should be joined.
.PARAMETER devVmNicName
    The Dev VM / Jump Box NIC name.
.PARAMETER devVmSubnetName
    The subnet name to which the Dev VM / Jump Box should be added.
.PARAMETER devVmIpAddressName
    The name to be assigned to the Dev VM / Jump Box public IP.
.PARAMETER devVmVmName
    The name name to be assigned to the Dev VM / Jump Box VM.
.PARAMETER dashboardIp
    The IP address of the consortium dashboard node (which is also the registrar node)
.PARAMETER sqlAdminPassword
    The admin password of the SQL Database.
.PARAMETER hostingPlanName
    The name of the hosting plan for the App Services deployed.
.PARAMETER skuName
    The SKU name for the hosting plan (must be Standard tier or above to support VNet integration)
.EXAMPLE
    C:\PS> deploy.consortium.ps1 -rgName "MyResourceGroup" -location "westeurope" -chosenDeploymentType "founder"
.NOTES
    Make sure to update the template parameters file, for example with consortium name, genesis details, member details etc
    
    For details on how to do this and a walkthrough see:
        https://github.com/mormond/ethereum-arm-templates/
        https://github.com/mormond/ethereum-arm-templates/blob/master/ethereum-consortium/README.md
        
    NOTE: The template parameters file may contain sensitive data. Be careful before committing to a repository.
#>

Param(
    # For All Deployments
    [Parameter(Mandatory = $True)]
    [string]$rgName,
    [string]$location = "WestEurope",
    [string]$subName,
    [string]$sqlAdminLogin = "dbadmin",
    [string]$databaseName = "accounts",
    [Parameter(Mandatory = $True)]   
    [ValidateSet("Founder", "NewMember", "Minimal", IgnoreCase = $True)]
    [string]$chosenDeploymentType,
    [Parameter(Mandatory = $True)]   
    [string]$contentRoot,

    # Only for founder deployment
    [string]$devVmDnsLabelPrefix,
    [securestring]$devVmPassword,
    [string]$devVmAdminUsername = "azureuser",
    [string]$devVmVnetName = "dx-founder-vnet",
    [string]$devVmNicName = "DevVMNic",
    [string]$devVmSubnetName = "subnet-txnodes",
    [string]$devVmIpAddressName = "DevVMPublicIP",
    [string]$devVmVmName = "DevVM",
    
    # Only for newmember deployment
    [string]$dashboardIp, 

    # Only for founder / new member deployment
    [securestring]$sqlAdminPassword,
    [string]$hostingPlanName = "AppServicesHostingPlan",
    [string]$skuName = "S1"
)

function CheckAndAuthenticateIfRequired {
    Try {
        $a = Get-AzureRmContext
    }
    Catch {
        login-azurermaccount 
    }
}

Set-Variable minimalDeployment "minimal" -Option Constant
Set-Variable founderDeployment "founder" -Option Constant
Set-Variable newMemberDeployment "newmember" -Option Constant
Set-VAriable githubRepo "https://github.com/mormond" -Option Constant
Set-Variable ethereumDevVm "ethereum-dev-vm" -Option Constant
Set-Variable ethereumMemberServices "ethereum-consortium-member-services" -Option Constant

$invocationPath = Split-Path $MyInvocation.MyCommand.Path

#
# What type of deployment are we doing - check we have the required parameters
#

$chosenDeploymentType = $chosenDeploymentType.ToLowerInvariant()

switch ($chosenDeploymentType) {
    $founderDeployment {
        if (!($devVmDnsLabelPrefix -and $devVmPassword -and $sqlAdminPassword)) {
            Write-Host
            Write-Host "Missing parameters..."
            if (!$devVmDnsLabelPrefix) { $devVmDnsLabelPrefix = Read-Host "devVmDnsLabelPrefix" }
            if (!$devVmPassword) { $devVmPassword = Read-Host "devVmPassword" -AsSecureString }
            if (!$sqlAdminPassword) { $sqlAdminPassword = Read-Host "sqlAdminPassword" -AsSecureString }
        }
    }
    $newMemberDeployment {   
        if (!($dashboardIp -and $sqlAdminPassword)) {
            Write-Host               
            Write-Host "Missing parameters..."
            if (!$dashboardIp) { $dashboardIp = Read-Host "dashboardIp" }
            if (!$sqlAdminPassword) { $sqlAdminPassword = Read-Host "sqlAdminPassword" -AsSecureString }
        }
    }
}

Write-Host "Logging into Azure"
CheckAndAuthenticateIfRequired

if ($subName) {
    Write-Host "Setting subscription to: $subName"
    Select-AzureRmSubscription -SubscriptionName $subName
}

Write-Host "Creating new resource group: $rgName"
New-AzureRmResourceGroup -Location $location -Name $rgName

Write-host "Deploying template. Wish me luck."

if ($chosenDeploymentType -eq $minimalDeployment -Or 
    $chosenDeploymentType -eq $founderDeployment) {

    $ethOutputs = New-AzureRmResourceGroupDeployment `
        -TemplateUri "$contentRoot/template.consortium.json" `
        -TemplateParameterFile ("$invocationPath\..\ethereum-consortium-params\template.consortium.params.json") `
        -ResourceGroupName $rgName

    $memberName = $ethOutputs.Parameters.members.Value[0].name.value
    $consortiumName = $ethOutputs.Parameters.consortiumName.value

    $vnetName = "$consortiumName-$memberName-vnet"
    $nsgName = "$consortiumName-$memberName-nsg-txnodes"

}
else {
    $ethOutputs = New-AzureRmResourceGroupDeployment `
        -TemplateFile "$contentRoot/template.consortiumMember.json" `
        -TemplateParameterFile ("$invocationPath\..\ethereum-consortium-params\template.consortium.params.participant1.json") `
        -ResourceGroupName $rgName `
        -dashboardIp $dashboardIp `
        -registrarIp $dashboardIp

    $consortiumMemberName = $ethOutputs.Parameters.consortiumMemberName.value
    $vnetName = "$consortiumMemberName-vnet"
}

#
# If this was a minimal deployment, we're done.
#
if ($chosenDeploymentType -eq $minimalDeployment) {
    Write-Host "Done."
    exit
}

#
# IF this is a founder deployment
# Add a DevBox VM
#
if ($chosenDeploymentType -eq $founderDeployment) {

    $nsg = Get-AzureRmNetworkSecurityGroup -Name $nsgName -ResourceGroupName $rgName

    $nsg | Add-AzureRmNetworkSecurityRuleConfig `
        -Name RDPRule `
        -Protocol TCP `
        -SourcePortRange * `
        -DestinationPortRange 3389 `
        -SourceAddressPrefix * `
        -DestinationAddressPrefix * `
        -Access Allow `
        -Direction Inbound `
        -Priority 1001

    $nsg | Set-AzureRmNetworkSecurityGroup

    Write-Host "Deploying Dev VM."

    New-AzureRmResourceGroupDeployment `
        -TemplateUri "$githubRepo/$ethereumDevVm/master/azuredeploy_existingvnet.json" `
        -ResourceGroupName $rgName `
        -adminUsername $devVmAdminUsername `
        -adminPassword $devVmPassword `
        -dnsLabelPrefix $devVmDnsLabelPrefix `
        -virtualNetworkName $devVmVnetName `
        -nicName $devVmNicName `
        -subnetName $devVmSubnetName `
        -publicIPAddressName $devVmIpAddressName `
        -vmName $devVmVmName

}

#
# Add the App Service components (web site + SQL Server)
#
Write-Host "Deploying web site / API components."

$webOutputs = New-AzureRmResourceGroupDeployment `
        -TemplateUri "$githubRepo/$ethereumMemberServices/master/template.web.components.json" `
        -ResourceGroupName $rgName `
        -hostingPlanName $hostingPlanName `
        -skuName $skuName `
        -administratorLogin $sqlAdminLogin `
        -administratorLoginPassword $sqlAdminPassword `
        -databaseName $databaseName 
  
#
# Add the VNET Integration
#

# Start by pulling down the PowerShell script to add the VNet Integration
$tempExists = $True
$tempPath = "$invocationPath\temp-$vnetName"
If (!(Test-Path $tempPath)) { 
    $tempExists = $false
    New-Item -Path $tempPath -ItemType "Directory"
}

$vnetIntegrationScript = "$tempPath\app.service.vnet.integration.ps1"

Invoke-WebRequest -UseBasicParsing `
        -Uri "$githubRepo/$ethereumMemberServices/master/app.service.vnet.integration.ps1" `
        -OutFile $vnetIntegrationScript `
        -Verbose

Write-Host "Adding VNET integration."

& ($vnetIntegrationScript) `
        -rgName $rgName `
        -targetVnetName $vnetName `
        -appName $webOutputs.Outputs.webApiName.Value

Write-Host "VNET integration complete."

Write-Host "Tidying up."
Remove-Item $vnetIntegrationScript
if (!$tempExists) {
    Remove-Item $tempPath
}

Write-Host "Done."
