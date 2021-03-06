#region Var setup
$resourceGroupName = 'CVADaCAutomation'
$region = 'westeurope'
$localVMAdminPw = ConvertTo-SecureString -String 'I like azure.' -AsPlainText -Force ## a single password for demo purposes 
$projectName = 'CVADaC-Automated' ## common term used through set up

$subscriptionName = 'XenBlog MSDN'
$subscriptionId = 'adbd9a10-d215-4156-b35f-6898be0c1e51'
$tenantId = '272445fa-2ffb-4023-aa93-437667ebfec1'
$orgName = 'xenblog'
$gitHubRepoUrl = "https://github.com/$orgName/CVADaCAutomation"

#endregion

#region Login
az login
az account set --subscription $subscriptionName
#endregion

#region Install the Azure CLI DevOps extension
az devops configure --defaults organization=https://dev.azure.com/$orgName
#endregion

#region Create the resource group to put everything in
New-AzResourceGroup -name $resourceGroupName -Location $region
#az group create --location $region --name $resourceGroupName
#endregion

#region Create the service principal
#$sp = New-AzADServicePrincipal -DisplayName $projectName
$spIdUri = "http://$projectName"
$sp = az ad sp create-for-rbac --name $spIdUri | ConvertFrom-Json
#endregion

#region Key vault

## Create the key vault. Enabling for template deployment because we'll be using it during an ARM deployment
## via an Azure DevOps pipeline later
$kvName = "$resourceGroupName-KV"
New-AzKeyVault -Location $region -Name $kvName -ResourceGroupName $resourceGroupName -EnabledForDeployment
#$keyVault = az keyvault create --location $region --name $kvName --resource-group $resourceGroupName --enabled-for-template-deployment true | ConvertFrom-Json
# az keyvault update --name $kvName --resource-group $resourceGroupName --enable-purge-protection true

# ## Create the key vault secrets
#Set-AzKeyVaultSecret -Name "$projectName-AppPw" -SecretValue $sp.password -VaultName $kvName
Set-AzKeyVaultSecret -name StandardVmAdminPassword -SecretValue $localVMAdminPw -VaultName $kvName
az keyvault secret set --name "$projectName-AppPw" --value $sp.password --vault-name $kvName
#az keyvault secret set --name StandardVmAdminPassword --value $localVMAdminPw --vault-name $kvName

## Give service principal created earlier access to secrets. This allows the steps in the pipeline to read the AD application's pw and the default VM password
#$null = Set-AzKeyVaultAccessPolicy -VaultName $kvName -Objectid $sp.id  -PermissionsToSecrets list,get
$null = az keyvault set-policy --name $kvName --spn $spIdUri --secret-permissions get list
#endregion

#region Instal the Pester test runner extension in the org
az devops extension install --extension-id PesterRunner --publisher-id Pester
#endregion

#region Create the Azure DevOps project
az devops project create --name $projectName
az devops configure --defaults project=$projectName
#endregion

#region Create the service connections
## Run $sp.password and copy it to the clipboard
$sp.password 
az devops service-endpoint azurerm create --azure-rm-service-principal-id $sp.appId --azure-rm-subscription-id $subscriptionId --azure-rm-subscription-name $subscriptionName --azure-rm-tenant-id $tenantId --name 'ARM'
## when prompted, use the value of $sp.password for the Azure RM service principal key
#endregion

#region Create the variable group
$varGroup = az pipelines variable-group create --name $projectName --authorize true --variables foo=bar | ConvertFrom-Json ## dummy variable because it won't allow creation without it

Read-Host "Now link the key vault $kvName to the variable group $projectName in the DevOps web portal and create a '$projectName-AppPw' and StandardVmAdminPassword variables with a password of your choosing."
#endregion

## Import GitHub Repo to DevOps
$repo = az repos import create --git-url $gitHubRepoUrl --repository $projectName | ConvertFrom-Json

## Create the pipeline
az pipelines create --name $projectName --repository $repo.repository.webUrl --branch master --yml-path azure-pipelines.yml --skip-first-run

## Replace the application ID generated in YAML
$sp.appId
##   - name: application_id
##    value: "REMEMBERTOFILLTHISIN"
