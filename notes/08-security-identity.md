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

## Going deeper

### 9. Where Key Vault lives

A regional PaaS resource in a resource group, like any other. Contents are stored on Microsoft-managed, HSM-backed infrastructure in that region, replicated to the paired region for read-only failover. It's reached at a **globally unique public URL** (`https://<name>.vault.azure.net`); for private access, add a private endpoint and disable public access. Two gates: the **network**, and **identity** (Entra ID + RBAC).

Tiers: **Standard** (software-protected keys), **Premium** (HSM-protected keys), **Managed HSM** (a dedicated HSM pool, a separate service).

### 10. Managed identity + Key Vault: the full flow

```
app on the VM ──① "token for Key Vault"──► IMDS 169.254.169.254 (only reachable from inside the VM)
              ◄─② token signed by Entra ID: "this is the VM's identity"
              ──③ GET secret + token ─────► Key Vault
                                            ④ valid token? RBAC role on this vault?
              ◄─⑤ the secret ──────────────
```

This removes **"secret zero"**: no credential is needed to get the other credentials. Terraform: an `identity` block on the VM + `azurerm_role_assignment` (`Key Vault Secrets User`, scoped to the vault). In code, the SDK's `DefaultAzureCredential` does steps ①–③: managed identity in Azure, `az login` locally.

**System-assigned vs user-assigned, the pitfalls:** role assignments take minutes to propagate, so first access right after creation can fail; recreating a resource with a system-assigned identity creates a **new** identity (anything granted outside Terraform is lost); with several identities on one resource, the code must name one by client ID; a VMSS's system-assigned identity is shared by all instances.

### 11. OpenID Connect in detail

OIDC is an identity layer on top of **OAuth 2.0** (authorization). An **identity provider** (issuer) issues signed **JWTs**; a **relying party** verifies them.

- A JWT is `header.payload.signature`, base64-encoded. The payload's **claims**: `iss` (issuer), `sub` (subject), `aud` (audience), `exp` (expiry). It's encoded, **not encrypted**: anyone holding it can read it.
- The issuer signs with its **private key** (RS256). It publishes the matching **public keys** (JWKS), found through `https://<issuer>/.well-known/openid-configuration`. The token header's `kid` names the key used.
- The relying party verifies the signature, then `iss`, `aud`, `exp` and `sub`. A token can't be forged without the private key, and changing any claim breaks the signature. HTTPS and the issuer's TLS certificate prove the keys really come from that issuer.

### 12. Workload Identity Federation (WIF)

Entra ID trusts tokens from an **external** OIDC issuer instead of a password. Configured as a **federated credential** on an app registration or a **user-assigned managed identity**:

| Field | Meaning | Example |
|---|---|---|
| Issuer | who must have issued the token | `https://token.actions.githubusercontent.com` |
| Subject | whom it's about: matched **exactly** | `repo:slavikator/azure-express-terraform:ref:refs/heads/main` |
| Audience | for whom it's intended | `api://AzureADTokenExchange` |

It holds **no secret**. One identity can have about 20, one per branch, PR or environment pattern.

**The audience** prevents replay: a token issued for one service is rejected by another. In the GitHub flow there are two tokens: GitHub's (audience `api://AzureADTokenExchange`, for Entra's exchange) and Entra's (audience `https://management.azure.com/`, for ARM).

**Each workflow run** (one execution, triggered by a push, PR or dispatch) requests its own token while it runs, valid for minutes, describing that repo, branch, commit and run. A **job** with `environment: production` gets the subject `repo:<owner>/<repo>:environment:production`. The classic error is `AADSTS70021`: no federated credential matches the subject.

Beyond GitHub: **Azure DevOps** service connections, **AKS workload identity** (a pod's Kubernetes service account, subject `system:serviceaccount:<ns>:<sa>`), GitLab, Terraform Cloud, other clouds.

**The rule:** code on Azure resources → managed identity; code outside Azure on an OIDC-capable platform → federation; secrets only as a last resort.

### 13. How the access token is used

After the exchange, Entra issues an access token for the service principal, valid about an hour, for **one API** (`aud`). Terraform sends it on every request as `Authorization: Bearer <token>`. For each request, ARM validates the token, identifies the principal by its object ID (`oid`), checks **RBAC** for that action on that scope, forwards to the resource provider, and logs it in the activity log. Other APIs need their own tokens: `https://storage.azure.com/` (the state blob with `use_azuread_auth`), `https://vault.azure.net`, `https://graph.microsoft.com/`.

### 14. Entra authentication vs local auth

"Local auth" is a service's own credentials: storage keys and SAS, SQL passwords, Service Bus SAS keys, Cosmos DB keys. **Entra authentication** replaces them with tokens: the identity gets a token for the service's audience, and the service maps it to permissions (data-plane RBAC, or database users created `FROM EXTERNAL PROVIDER` in Azure SQL).

| Service | Turn off local auth |
|---|---|
| Storage | `shared_access_key_enabled = false` |
| Azure SQL | "Microsoft Entra-only authentication" |
| Service Bus, Event Hubs | `local_auth_enabled = false` |
| Cosmos DB | `local_authentication_disabled = true` |

Turning off local auth is the important second step: leaked keys stop working. Often enforced by Azure Policy.

### 15. Keeping secrets out of the state, in full

1. **Make the secret unnecessary:** managed identity + Entra auth; disable local auth so exported keys in the state are useless.
2. **Keep it outside Terraform:** create it directly in Key Vault; the app reads it at runtime.
3. **`ephemeral` values** (1.10+) and **write-only arguments** (1.11+; per resource in newer providers, e.g. azurerm 4.x).
4. `sensitive` doesn't protect the state.
5. **Protect the state** for whatever remains.

OIDC removes the CI credential, which is never stored in the state anyway.

### 16. Privileged Identity Management (PIM)

Just-in-time admin access: people are **eligible** for a role and **activate** it when needed, with MFA, a justification, optionally an approval, for a limited time (e.g. 2 hours). Covers Entra roles, Azure RBAC roles and group membership (PIM for Groups); adds audit history and **access reviews**. Keep 1–2 **break-glass** accounts outside PIM for emergencies. Requires **Entra ID P2** (or ID Governance). Not for pipelines: they get narrowly scoped roles. Terraform: `azurerm_pim_eligible_role_assignment`.

### 17. Customer-managed keys (CMK)

All data at rest is encrypted by default with **platform-managed keys**. With CMK, the key is yours, in Key Vault or Managed HSM. **Envelope encryption:** data is encrypted with a data key (DEK), which is wrapped by your key (the KEK); the service unwraps it through Key Vault with its managed identity (role **Key Vault Crypto Service Encryption User**).

- Gives control, rotation on your schedule, an audit of every key use, and revocation (disable the key → data unreadable, "crypto-shredding"). Often a compliance requirement.
- Risks: losing the key means losing the data (soft delete and **purge protection are required**); an unreachable vault means an outage.
- Usually needs a **user-assigned** identity, so the role exists before the resource.
- Related: **BYOK** (import your own key), double encryption, client-side encryption.

### 18. Azure Policy in detail

**Definition** (`if` + `then` effect) → **initiative** (a set) → **assignment** to a management group, subscription or RG, inherited downwards; **parameters**; **exemptions**. Hundreds of built-ins.

| Effect | Behavior |
|---|---|
| Deny | rejects the request |
| Audit | allows it, marks non-compliant |
| Modify / Append | changes the request (e.g. adds a tag) |
| DeployIfNotExists | deploys something related afterwards |

- Classic guardrails: **Allowed locations** (data residency), **required tags** (cost allocation), **no public IPs** (access through Bastion).
- Deny is checked by ARM when the request arrives: **`plan` doesn't see policies, only `apply` fails** (`RequestDisallowedByPolicy`). Catch it earlier with checkov or OPA in CI.
- **Modify policies cause Terraform drift** unless the code contains the same values (or `ignore_changes`).
- Existing resources are evaluated about every 24 hours and reported; **remediation tasks** fix them, using a managed identity.
- Roll out in **Audit** before **Deny**.

## Check yourself

Move your workflow to OIDC and delete `AZURE_CLIENT_SECRET` from GitHub. Create a Key Vault, give the VM a managed identity with the `Key Vault Secrets User` role, and read a secret from the VM without any password. The hands-on exercise is in [`practice-08-security.md`](practice-08-security.md).

## Interview answers

**Managed identity and Key Vault: how does it work?**
> A managed identity gives an Azure resource its own identity in Entra ID, with no password. Code on the VM gets a token from the local metadata endpoint (IMDS) and calls Key Vault with it; Key Vault validates the token and checks the RBAC role assignment, like `Key Vault Secrets User` on that vault, and returns the secret. That removes "secret zero". In Terraform it's an `identity` block plus an `azurerm_role_assignment` scoped to the vault.

**System-assigned or user-assigned identity?**
> Both are secretless; the difference is lifecycle. A system-assigned identity lives and dies with one resource: simple, nothing left behind. A user-assigned identity is a standalone resource that can be shared, granted roles before the resources exist, and survives when they're recreated, so it fits shared access, customer-managed keys, frequently replaced resources and federated credentials.

**Why is OIDC better than a client secret, and how does Azure trust GitHub's token?**
> There's no long-lived secret: each run gets a GitHub token valid for minutes, signed with GitHub's private key. Entra knows the issuer from the federated credential, fetches GitHub's public keys from its well-known JWKS endpoint, verifies the signature, then the issuer, audience, expiry and subject (repo plus branch or environment). Only then does it issue a short-lived access token for the service principal. A token can't be forged without GitHub's key, and a stolen one is useless after minutes or from another repo.

**What is Workload Identity Federation?**
> It lets an external workload get Azure access without a secret. A federated credential on an app registration or user-assigned managed identity tells Entra to trust tokens with a specific issuer, subject and audience. GitHub Actions, Azure DevOps, AKS pods through workload identity and other platforms use it. Managed identity for code on Azure, federation for external platforms, secrets as a last resort.

**What is the audience?**
> The intended recipient of a token, in its `aud` claim. Services reject tokens with another audience, so a token issued for one service can't be replayed against another. The GitHub token's audience is `api://AzureADTokenExchange`; the resulting Entra token's audience is the API, like `https://management.azure.com/`.

**How do you keep a secret out of the Terraform state?**
> Avoid the secret: managed identities and Entra auth for databases, storage and Key Vault, with local auth disabled so exported keys are useless. Keep necessary secrets outside Terraform, created in Key Vault and read by the app at runtime. Use ephemeral values and write-only arguments in newer Terraform versions. `sensitive` only hides output, and whatever remains is covered by protecting the state itself.

**What is Entra authentication?**
> A service accepting Entra ID tokens instead of its own local credentials, like storage keys, SQL passwords or SAS keys. The service maps the identity to data-plane roles or database users, so there's no shared secret, every access is attributable, and access is revoked per identity. The key follow-up is disabling local auth, often enforced with Azure Policy.

**What is PIM?**
> Just-in-time privileged access: admins are eligible for a role and activate it when needed, with MFA, a justification, optionally an approval, for a limited time. It covers Entra roles, Azure RBAC roles and groups, with audit history and access reviews, and removes standing admin privileges. Pipelines don't use it; break-glass accounts stay outside it.

**What are customer-managed keys?**
> Azure encrypts all data at rest by default with platform-managed keys. With CMK, the key lives in my Key Vault or Managed HSM; services use envelope encryption, wrapping their data key with my key through Key Vault and their managed identity. That gives control over rotation, an audit of every use, and revocation by disabling the key. The risk is that losing the key loses the data, so soft delete and purge protection are mandatory.

**What is Azure Policy?**
> It enforces rules on resource configuration regardless of who makes the request, while RBAC controls who can act. A definition has a condition and an effect (Deny, Audit, Modify, DeployIfNotExists), is grouped into initiatives and assigned to a scope where it's inherited. Typical guardrails are allowed locations, required tags and no public IPs. Deny is checked by ARM at apply time, so Terraform's plan won't show it, and Modify policies can cause drift unless the code matches.

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
- How does Azure verify that a GitHub OIDC token is genuine?
- What is a federated credential, and what is the audience for?
- How is the Azure access token used by Terraform?
- What is Entra authentication, and why disable local auth?
- What is PIM?
- What are customer-managed keys, and what are the risks?
- Why doesn't `terraform plan` catch a Deny policy?
