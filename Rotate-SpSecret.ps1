#Requires -Version 7
<#
Rotates a service principal (app registration) client secret and stores the new value in Key Vault.
Prereqs: `az login` as an identity that can manage the app registration (Application Administrator
or app owner) and has "Key Vault Secrets Officer" on the vault.
Example:
  ./Rotate-SpSecret.ps1 -AppId <client-id> -VaultName my-kv -SecretName sp-client-secret
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $AppId,
    [Parameter(Mandatory)] [string] $VaultName,
    [Parameter(Mandatory)] [string] $SecretName,
    [int] $ValidityDays = 90,
    [switch] $RemoveOldSecrets
)

$ErrorActionPreference = 'Stop'

function Invoke-Az {
    $out = & az @args
    if ($LASTEXITCODE -ne 0) { throw "az $($args -join ' ') failed" }
    $out
}

$startTime = (Get-Date).ToUniversalTime()
$endTime   = $startTime.AddDays($ValidityDays)
$credName  = "auto-rotated-$($startTime.ToString('yyyyMMddHHmmss'))"

if (-not $PSCmdlet.ShouldProcess($AppId, "Create new secret and update $VaultName/$SecretName")) { return }

# Add a new secret (append keeps the old one valid until the vault is updated)
$cred = Invoke-Az ad app credential reset --id $AppId --append `
    --display-name $credName `
    --end-date $endTime.ToString('yyyy-MM-ddTHH:mm:ssZ') `
    --query '{secret:password, keyId:keyId}' -o json | ConvertFrom-Json

try {
    Invoke-Az keyvault secret set --vault-name $VaultName --name $SecretName `
        --value $cred.secret --expires $endTime.ToString('yyyy-MM-ddTHH:mm:ssZ') `
        --query id -o tsv | Out-Null
}
catch {
    # Vault update failed: remove the new credential so no orphan secret remains
    az ad app credential delete --id $AppId --key-id $cred.keyId | Out-Null
    throw
}
finally {
    $cred.secret = $null
}

Write-Host "Rotated secret for app $AppId; stored in $VaultName/$SecretName (expires $endTime)."

if ($RemoveOldSecrets) {
    $old = Invoke-Az ad app credential list --id $AppId --query "[?keyId!='$($cred.keyId)'].keyId" -o tsv
    foreach ($id in $old) {
        Invoke-Az ad app credential delete --id $AppId --key-id $id | Out-Null
        Write-Host "Removed old credential $id"
    }
}
