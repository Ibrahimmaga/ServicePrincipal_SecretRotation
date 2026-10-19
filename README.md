# ServicePrincipal_SecretRotation

Rotates the client secrets of all tagged service principals (app registrations) in a subscription and updates the matching Key Vault secrets. Runs monthly through GitHub Actions.

## Organization

| Item | Value |
|------|-------|
| Entra tenant (organization) ID | `<TENANT_ID>` |

## How it works

1. Lists every Key Vault in the subscription.
2. Picks each secret that has the tag `appId=<app registration client id>`.
3. Creates a new client secret on that app, writes it to the Key Vault secret (new version), then optionally deletes older client secrets.

To onboard a service principal, tag its Key Vault secret:

```powershell
az keyvault secret set-attributes --vault-name <kv> --name <secret> --tags appId=<client-id>
```

## Files

- `Rotate-AllSpSecrets.ps1`: subscription-wide discovery and rotation.
- `Rotate-SpSecret.ps1`: rotates one app and one Key Vault secret.
- `.github/workflows/rotate-all-sp-secrets.yml`: monthly schedule plus manual run (with dry-run option), signs in with OIDC.

## Setup

Repository secrets:

| Name | Value |
|------|-------|
| `AZURE_CLIENT_ID` | Client ID of the automation identity |
| `AZURE_TENANT_ID` | Organization (tenant) ID above |
| `AZURE_SUBSCRIPTION_ID` | Subscription to process |

The automation identity needs:

- A federated credential for this repo.
- Permission to manage the apps: `Application.ReadWrite.All` (Graph), or ownership of each app.
- "Reader" on the subscription and "Key Vault Secrets Officer" on each vault. Vaults using access policies instead of RBAC are skipped with a warning.

## Run locally

```powershell
az login --tenant <TENANT_ID>
./Rotate-AllSpSecrets.ps1 -SubscriptionId <id> -RemoveOldSecrets -WhatIf   # preview
./Rotate-AllSpSecrets.ps1 -SubscriptionId <id> -RemoveOldSecrets
```
