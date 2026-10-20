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

$vaults = @(az keyvault list --subscription $SubscriptionId --query '[].name' -o tsv | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($LASTEXITCODE -ne 0) { throw 'Failed to list key vaults' }
Write-Host "Found $($vaults.Count) Key Vault(s) in subscription $SubscriptionId."

$failures = @()
$count = 0

foreach ($vault in $vaults) {
    $listedItems = az keyvault secret list --vault-name $vault --query '[].{name:name,tags:tags}' -o json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Skipping vault $vault (cannot list secrets): $($listedItems -join [Environment]::NewLine)"
        $failures += "$vault (list failed)"
        continue
    }
    $taggedItems = @(
        foreach ($secret in ($listedItems | ConvertFrom-Json)) {
            $tag = if ($null -ne $secret.tags) { $secret.tags.PSObject.Properties[$TagName] }
            if ($null -ne $tag -and -not [string]::IsNullOrWhiteSpace([string]$tag.Value)) {
                [pscustomobject]@{ name = $secret.name; appId = [string]$tag.Value }
            }
        }
    )
    Write-Host "Vault ${vault}: found $($taggedItems.Count) secret(s) tagged with '$TagName'."
    foreach ($item in $taggedItems) {
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
if ($count -eq 0) {
    Write-Warning "No secrets were selected. Confirm the subscription contains Key Vaults and each target secret has a non-empty '$TagName' tag (for example, appId=<application-client-id>)."
    exit 1
}
if ($failures.Count) { exit 1 }
exit 0
