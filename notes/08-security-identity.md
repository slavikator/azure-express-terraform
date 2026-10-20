# Week 8. Security and identity

How to remove secrets from the pipeline and give each component only the permissions it needs.

## Terms

| Abbreviation / term | Stands for | What it is, in one sentence |
|---|---|---|
| **KV** | Key Vault | Storage for secrets, keys and certificates |
| **MI** | Managed Identity | An identity for an Azure resource, with no secrets |
| **OIDC** | OpenID Connect | The protocol GitHub uses to issue a token that Azure trusts |
| **WIF** | Workload Identity Federation | Entra ID's mechanism to "trust an external token" instead of a password |
| **Federated credential** | | A setting on an app registration: which external token to trust |
| **PoLP** | Principle of Least Privilege | Grant only the minimum permissions needed |
| **Azure Policy** | | Rules that forbid or audit resource configuration |
| **CMK** | Customer-Managed Key | Encryption with your own key from Key Vault instead of Microsoft's key |
| **PIM** | Privileged Identity Management | Granting admin roles for a limited time, on request |

## Concepts you need to explain in your own words

### 1. Managed identity

| | System-assigned | User-assigned |
|---|---|---|
| Created | together with the resource | as a separate resource |
| Lives | as long as the resource | independently |
| How many resources | one | can be attached to many |
| When | one VM reads one Key Vault | several resources with the same permissions, or permissions are needed before the resource exists |

```hcl
resource "azurerm_linux_virtual_machine" "vm" {
  ...
  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "vm_kv" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.vm.identity[0].principal_id
}
```

### 2. Key Vault

- Stores **secrets** (passwords, connection strings), **keys** (cryptographic keys), **certificates**.
- Access model: **Azure RBAC** (recommended) or the older **access policies**. Roles: `Key Vault Administrator`, `Key Vault Secrets Officer` (write), `Key Vault Secrets User` (read).
- **Soft delete** (always on): a deleted vault and its secrets can be restored within 7–90 days. Because of this, a deleted vault's name can't be reused right away.
- **Purge protection:** forbids permanent deletion until the retention period ends. Required for prod.
- Network: firewall and private endpoint.

### 3. Secrets in Terraform

The problem: everything Terraform knows about a resource is stored in the state in plain text.

| Method | What it gives you |
|---|---|
| `sensitive = true` | hides the value from `plan` output and logs. **It stays in the state** |
| Don't generate secrets in Terraform | the secret is created outside it; Terraform only refers to Key Vault |
| `data "azurerm_key_vault_secret"` | reads a secret from KV, but the value still ends up in the state |
| **Ephemeral resources** (Terraform 1.10+) | the value is used during the run and **isn't written** to the state or plan |
| **Write-only arguments** (Terraform 1.11+) | the argument is passed to the resource and isn't stored in the state |
| Managed identity | there's no secret at all. The best option |

Plus protecting the state itself: a private storage account, RBAC, minimal access.

### 4. OIDC for GitHub Actions

**How my project works right now:** `AZURE_CLIENT_SECRET` is stored in GitHub Secrets. The password expires, can be stolen, and has to be rotated.

**With OIDC:**
1. For each run, GitHub issues a short-lived token with data: repository, branch, environment.
2. Azure checks the token against the configured federated credential.
3. If the subject matches, Azure issues its own access token. There's no password anywhere.

A federated credential on the app registration:
```
Issuer:   https://token.actions.githubusercontent.com
Subject:  repo:slavikator/azure-express-terraform:ref:refs/heads/main
Audience: api://AzureADTokenExchange
```

Other subject options: `repo:<owner>/<repo>:environment:production`, `repo:<owner>/<repo>:pull_request`.

Workflow:
```yaml
permissions:
  id-token: write     # allow GitHub to issue an OIDC token
  contents: read

env:
  ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  ARM_USE_OIDC: true
  # ARM_CLIENT_SECRET is no longer needed
```

For `az` in the workflow: `azure/login` with `client-id`, `tenant-id`, `subscription-id`, without `creds`.

The `azurerm` backend also needs `use_oidc = true` (or `ARM_USE_OIDC`), and the SP needs access to the storage account holding the state.

### 5. Least privilege for Terraform

- Don't give Contributor on the whole subscription if the project lives in one RG. Contributor on just the RG is better.
- If Terraform creates `azurerm_role_assignment`, it needs a role that can assign roles: **User Access Administrator**, or **Role Based Access Control Administrator** with conditions (limiting which roles can be assigned).
- Separate SPs for dev and prod.
- A separate SP with permission only to `plan` (Reader + access to the state) for PRs, and another with permission to `apply` for main.

**In my project:** two SPs with Contributor on the whole subscription, one of which is no longer used.

### 6. Azure Policy

- **Definition**: a rule (e.g. "only these regions are allowed").
- **Initiative**: a set of rules.
- **Assignment**: applying it to a scope (management group, subscription, RG).
- Effects: `Deny` (forbid creation), `Audit` (just flag it), `Modify` / `DeployIfNotExists` (fix automatically), `Append`.

Examples: allowed locations, a required `owner` tag, banning public IPs, required encryption.

A policy with the `Deny` effect also stops `terraform apply`. The error is `RequestDisallowedByPolicy`.

### 7. Protecting the state storage

Week 3 covered backups and the lock. What's left is **who** can read the state, and **from where**.

**Who: RBAC instead of access keys.** By default the `azurerm` backend reads the storage account key through `listKeys`. Anyone with Contributor or Owner on the account can do the same and read everything, bypassing RBAC. Entra ID auth replaces the key with data-plane roles:

| Role | Who gets it |
|---|---|
| Storage Blob Data Contributor | the CI identity (it writes the state) |
| Storage Blob Data Reader | people who only need to read, or nobody: changes go through CI |

```hcl
backend "azurerm" {
  ...
  use_azuread_auth = true
}
```

The safe order, checking `terraform init` locally and in CI after each step:
1. Assign Storage Blob Data Contributor to yourself and the CI identity on `sttfstate1791293035`.
2. Set `use_azuread_auth = true` and run `terraform init -reconfigure`.
3. Only then disable shared key access: `az storage account update -n sttfstate1791293035 -g rg-tfstate --allow-shared-key-access false`.

If step 3 comes first, `init` fails everywhere that still uses the key.

**From where: no public network access.** My storage account accepts connections from the whole internet (`defaultAction: Allow`), protected only by authentication. Closing it with a firewall breaks GitHub-hosted runners, whose IPs change. The options:
- a **self-hosted runner** in a VNet, plus a service endpoint or private endpoint to the storage account;
- a **private endpoint** and `publicNetworkAccess = Disabled`, with all access from inside the VNet.

**Current state of my account:** TLS 1.2, versioning, soft delete, `CanNotDelete` lock: done. Entra ID auth, shared key disabled, network closed: to do this week.

### 8. Principles

- **Least privilege:** minimal permissions at the smallest scope.
- **No secrets in code:** no passwords in `.tf`, in `.tfvars` in git, or in workflow variables.
- **Short-lived credentials:** OIDC and managed identity instead of long-lived passwords.
- **Defense in depth:** several layers of protection (network, identity, encryption, monitoring).

## Commands to know by heart

```
az ad app federated-credential create --id <appId> --parameters cred.json
az ad app federated-credential list --id <appId> -o table
az ad app credential list --id <appId> -o table      # client secrets and expiry dates
az role assignment create --assignee <id> --role "Key Vault Secrets User" --scope <kv id>
az keyvault secret set --vault-name <kv> -n app-password --value ...
az keyvault secret show --vault-name <kv> -n app-password --query value -o tsv
az policy assignment list -o table
```

## Check yourself

Move your workflow to OIDC and delete `AZURE_CLIENT_SECRET` from GitHub. Create a Key Vault, give the VM a managed identity with the `Key Vault Secrets User` role, and read a secret from the VM without any password.

## Interview questions

- Why is OIDC better than a client secret?
- How does workload identity federation work for GitHub Actions?
- System-assigned or user-assigned identity: when to use which?
- How do you keep a secret out of the Terraform state?
- Which permissions does the Terraform SP really need, and how do you limit them?
- Key Vault: RBAC or access policies?
- Who can read your Terraform state, and how do you limit it?
- Why soft delete and purge protection?
- What is Azure Policy, and how does it differ from RBAC?
