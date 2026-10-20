#Requires -Version 7
<#
Rotates the client secret of every service principal referenced by a Key Vault secret in a subscription.
Discovery: a Key Vault secret is in scope when it has the tag `appId=<app registration client id>`.
Prereqs: `az login`; Graph rights on the apps; "Key Vault Secrets Officer" on the vaults; Reader on the subscription.
Example:
  ./Rotate-AllSpSecrets.ps1 -SubscriptionId <id> -RemoveOldSecrets -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [string] $TagName = 'appId',
    [int] $ValidityDays = 90,
    [switch] $RemoveOldSecrets
)

$ErrorActionPreference = 'Stop'

$vaults = az keyvault list --subscription $SubscriptionId --query '[].name' -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Failed to list key vaults' }

$failures = @()
$count = 0

foreach ($vault in $vaults) {
    $items = az keyvault secret list --vault-name $vault --query "[?tags.$TagName!=null].{name:name, appId:tags.$TagName}" -o json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Skipping vault $vault (cannot list secrets): $($items -join [Environment]::NewLine)"
        $failures += "$vault (list failed)"
        continue
    }
    foreach ($item in ($items | ConvertFrom-Json)) {
        $count++
        try {
            & "$PSScriptRoot/Rotate-SpSecret.ps1" -AppId $item.appId -VaultName $vault -SecretName $item.name `
                -ValidityDays $ValidityDays -RemoveOldSecrets:$RemoveOldSecrets -WhatIf:$WhatIfPreference
        }
        catch {
            $failures += "$vault/$($item.name) (app $($item.appId)): $($_.Exception.Message)"
            Write-Warning $failures[-1]
        }
    }
}

Write-Host "Processed $count secret(s); $($failures.Count) failed."
if ($failures.Count) { exit 1 }
exit 0
