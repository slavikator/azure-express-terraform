# Week 8 practice: "No passwords left"

**Goal:** remove every long-lived secret from the project: CI signs in to Azure with OIDC instead of a client secret, the VM reads a secret from Key Vault with its managed identity, the state backend uses Entra auth instead of storage keys, and an Azure Policy enforces where resources may be created.

**Topics:** workload identity federation, federated credentials, managed identity, IMDS, Key Vault with RBAC, Azure Policy, secrets in the state, Entra auth for the state backend.

**Time:** 3 hours, best split into three sessions (Steps 1, 2–3, 4–5). **Cost:** about $0.05 per hour while the VM runs; Key Vault and Policy cost practically nothing.

**Notes:** [`08-security-identity.md`](08-security-identity.md)

---

## Rules for this practice

1. **Your "main root"** below means wherever your main configuration lives: the repo root, or `envs/dev` if you've done practice 06.
2. **Order matters in Steps 1 and 5.** Each removes a credential; doing a step before its prerequisite locks you or CI out. Follow the steps in order and check after each one.
3. **Never paste a real token or secret value into a website** (like jwt.io) or into a chat.

---

## Step 0. Preparation

Bring the main environment up and check that `plan` shows `No changes`. Find your CI identity:

```
az ad app list --display-name github-actions-terraform --query "[].{name:displayName, appId:appId}" -o table
az ad app credential list --id <appId> -o table
```

The second command shows the client secret CI uses today, and when it expires.

> ❓ **1.** Where is this secret stored, who can read it, and what would an attacker who stole it be able to do, from where, and for how long?

---

## Step 1. CI with OIDC instead of a client secret

**1. Create a federated credential** for pushes to `main`:

```
az ad app federated-credential create --id <appId> --parameters '{
  "name": "github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:slavikator/azure-express-terraform:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

**2. Change the workflow** (`.github/workflows/deploy.yml`):

- add a top-level `permissions` block with `id-token: write` and `contents: read`;
- add `ARM_USE_OIDC: true` to `env`;
- remove `ARM_CLIENT_SECRET` from `env`.

The backend reads the same `ARM_*` variables, so the state access switches to OIDC too.

**3. Push to `main`,** and check that the **Terraform Plan** step still shows `No changes`.

> ❓ **2.** No secret is sent anymore. How did the job prove to Azure who it is? Name the two tokens involved and the audience of each.

**4. Test a pull request.** Create a branch with a harmless change (e.g. a comment), open a PR, and look at the CI run.

> ❓ **3.** What error did the PR run get, and why? Look at the subject a PR job presents. Fix it with a second federated credential, and explain the fix.

**5. Remove the old secret,** only after both runs are green:

```
gh secret delete AZURE_CLIENT_SECRET
az ad app credential list --id <appId> --query "[].keyId" -o tsv
az ad app credential delete --id <appId> --key-id <keyId>
```

Push once more and check CI is still green.

> ❓ **4.** What does GitHub store now, and is any of it secret?

---

## Step 2. A Key Vault, read by the VM's managed identity

Work in a new file in your main root, `kv.tf`. It's an experiment and gets deleted at the end.

**1. Code:**

- `azurerm_key_vault`: a globally unique name, e.g. `"kv-demo-${substr(data.azurerm_client_config.current.subscription_id, 0, 8)}"`; `sku_name = "standard"`; `enable_rbac_authorization = true`; `soft_delete_retention_days = 7`; `purge_protection_enabled = false` (lab only: in production it would be `true`);
- a role assignment **for yourself**, `Key Vault Secrets Officer` on the vault, so you can create secrets. Use `data.azurerm_client_config.current.object_id`;
- on the main VM: an `identity { type = "SystemAssigned" }` block;
- a role assignment for the VM's identity: `Key Vault Secrets User` on the vault.

**Predict** the plan: what happens to the VM when you add the `identity` block? Then apply.

**2. Create the secret by hand,** not in Terraform:

```
az keyvault secret set --vault-name <kv name> -n db-password --value "not-a-real-password-123"
```

> ❓ **5.** Why create the secret with `az` instead of an `azurerm_key_vault_secret` resource?

**3. Read it from the VM, step by step.** SSH to the VM and run:

```
TOKEN=$(curl -s -H "Metadata: true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" | jq -r .access_token)
curl -s -H "Authorization: Bearer $TOKEN" "https://<kv name>.vault.azure.net/secrets/db-password?api-version=7.4" | jq -r .value
```

If `jq` is missing on the VM, install it with `sudo apt-get install -y jq`. If the second call returns `Forbidden`, wait a few minutes: role assignments take time to propagate.

> ❓ **6.** Walk through what happened in each of the two `curl` calls. Why can't someone on the internet get the first token?
>
> ❓ **7.** Remove the VM's role assignment from the code, apply, and run the second `curl` again. What happens, and what does it show about the identity and the role?

---

## Step 3. Azure Policy: allowed locations

Add to your main root:

- a data source `azurerm_policy_definition` looking up the built-in **"Allowed locations"** by `display_name`;
- `azurerm_resource_group_policy_assignment` on your main resource group, with the parameter `listOfAllowedLocations = ["swedencentral"]`.

Apply it. Then test it from the CLI:

```
az network nsg create -g <your main RG> -n nsg-policy-test -l northeurope
```

Then test it from Terraform: add a temporary `azurerm_network_security_group` with `location = "northeurope"` to your main root, and run `plan`, then `apply`.

> ❓ **8.** What did `plan` show, and what did `apply` show? Why does the policy only appear at `apply`?
>
> ❓ **9.** Your `variables.tf` already validates `location`. What does the policy add that the `validation` doesn't?

Remove the temporary NSG from the code. Keep or remove the policy assignment, your choice.

---

## Step 4. A secret in the state

Add a temporary file `tls.tf`:

```hcl
resource "tls_private_key" "demo" {
  algorithm = "ED25519"
}
```

Run `terraform init` (a new provider), `apply`, then search the state:

```
terraform state pull | jq -r '.resources[] | select(.type=="tls_private_key") | .instances[0].attributes.private_key_openssh' | head -3
```

> ❓ **10.** What did you find? Write down the conclusion, and name two ways to give the VM an SSH key or a password without it ending up in the state.

Delete `tls.tf`, then `apply` to remove the key from the state.

---

## Step 5. The state backend with Entra auth instead of storage keys

This finishes the state protection started in week 3. **Follow the order exactly**: disabling keys before Entra auth works would lock you and CI out of the state.

**1. Give data-plane access** to yourself and to the CI identity:

```
SA_ID=$(az storage account show -n sttfstate1791293035 -g rg-tfstate --query id -o tsv)
az role assignment create --assignee <your user object id> --role "Storage Blob Data Contributor" --scope $SA_ID
az role assignment create --assignee 3f1c5543-cbe3-4240-8003-00e28bfe3670 --role "Storage Blob Data Contributor" --scope $SA_ID
```

Your object ID: `az ad signed-in-user show --query id -o tsv`.

**2. Switch the backend** to Entra auth: add `use_azuread_auth = true` to the `backend "azurerm"` block, then:

```
terraform init -reconfigure
terraform plan          # No changes, now reading the state with your Entra token
```

If you get a 403, wait a few minutes for the role to propagate.

**3. Push,** and check that CI's `init` and `plan` still work.

**4. Only now, disable shared key access:**

```
az storage account update -n sttfstate1791293035 -g rg-tfstate --allow-shared-key-access false
```

**5. Prove it:**

```
az storage blob list --account-name sttfstate1791293035 -c tfstate --auth-mode key -o table     # should fail
az storage blob list --account-name sttfstate1791293035 -c tfstate --auth-mode login -o table   # should work
terraform plan                                                                                  # should work
```

> ❓ **11.** Who could read your state before this step, and who can now? Why was the order (roles → backend → CI → disable keys) important?

---

## Step 6. Cleanup

```
# in your main root: delete kv.tf, remove the VM's identity block if you want, then
terraform plan          # predict!
terraform apply
az keyvault list-deleted -o table               # the vault is soft-deleted, its name is still reserved
az keyvault purge -n <kv name>                  # free the name (works because purge protection was off)
terraform destroy       # if you're stopping for the day
git status
```

> ❓ **12.** Which long-lived secrets are left in this project now, if any? Which would you remove next, and how?

---

## Outcome

After this practice you should be able to, without looking:

- switch a pipeline from a client secret to OIDC federation, and debug a subject mismatch;
- explain both tokens in the GitHub → Azure flow and their audiences;
- give a VM access to Key Vault with a managed identity, and walk through the IMDS flow;
- show why `plan` doesn't catch a Deny policy;
- explain why generated secrets end up in the state, and how to avoid it;
- move a state backend from storage keys to Entra auth without locking anyone out.

## My answers

1. The client secret was stored as a GitHub Actions secret (encrypted, injected into jobs), plus in Entra as a credential on the app. Anyone who can change workflows in the repo can get it out, through a job that uses it. With it, an attacker could act as the CI app (Contributor on the whole subscription) from anywhere on the internet, until the secret expires (months or years) or is deleted. **Correction:** I said "make changes to the state"; the bigger risk is direct access to every resource in the subscription, not only through Terraform.
2. The job asked GitHub for an OIDC token (`id-token: write`). GitHub signed it with issuer `token.actions.githubusercontent.com`, subject `repo:...:ref:refs/heads/main` and audience `api://AzureADTokenExchange`. Entra checked it against the federated credential (issuer, subject and audience must match) and gave back an Azure access token (audience `https://management.azure.com/`, ~1 hour). Two tokens: GitHub's (proves who the job is, for Entra) and Entra's (for the Azure API). **Correction:** I described the audience as "the API that provides short-lived tokens"; it's the intended receiver of the token (here, Entra's token exchange). `id-token: write` lets the job request that OIDC token; a listed `permissions` block sets every other permission to none.
3. `AADSTS700213`: no federated credential matches the subject. A PR job presents subject `...:pull_request`, not `...:ref:refs/heads/main`. The repo also uses the immutable subject format `repo:owner@ownerId/repo@repoId:...`. Fixed with a second credential, `github-pr`, for the `pull_request` subject. The federated credential is a trust rule in Entra (tenant): "tokens from this issuer with this exact subject may log in as this app".
4. Only identifiers: `AZURE_CLIENT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, and `SSH_PUBLIC_KEY`. None of them gives access by itself (the public key is meant to be shared), so they could be plain GitHub variables. The client secret is deleted in both GitHub and Entra.
5. An `azurerm_key_vault_secret` resource would store the secret value in the Terraform state in plain text. Created with `az`, Terraform manages only the vault and the role assignments, never the value. (Newer option: write-only `value_wo`, TF 1.11+ / azurerm 4.x.)
6. Call 1 asked IMDS (`169.254.169.254`, link-local, reachable only from inside the VM; `Metadata: true` guards against SSRF) for a token for the VM's managed identity, audience `https://vault.azure.net`. Call 2 sent it as a Bearer token to Key Vault, which checked the token (authentication) and the role assignment `Key Vault Secrets User` (authorization), and returned the secret. Nobody on the internet can reach the VM's IMDS, so only code running on the VM can get the token. **Correction:** I said "the request must be verified"; the real reason is that IMDS isn't reachable from outside, and the Azure host itself knows which VM is asking.
7. 403 `ForbiddenByRbac`, "Assignment: (not found)". Call 1 still gave a token: the error names the caller's `oid`, so authentication worked. The identity is **who**, the role assignment is **what it may do**; a token carries no permissions, Key Vault checks RBAC on every request, so an old token fails too. **Correction:** I first thought IMDS gave no token; `jq -r .value` printed `null` and hid the real error. 401 = authentication failed, 403 = authorization failed.
8. `plan` showed `+ create` and succeeded; `apply` failed with 403 `RequestDisallowedByPolicy`. Plan only compares code and state locally and never sends the create request. Azure Resource Manager evaluates policy on each write request, from any tool (the `az` test failed the same way). **Correction:** I said Terraform checks the policy at apply; Azure does, Terraform just sends the request. A clean plan doesn't guarantee a successful apply.
9. `validation` is a client-side check, in this root only, on `var.location` only. My temporary NSG had `location = "northeurope"` hard-coded, so it was never validated (and the validation even allows northeurope). Policy is enforced server-side for everyone: portal, az, other roots, Owners. **Correction:** I said the policy has "higher priority"; they run in different places. Validation is fast feedback; policy is the real guardrail.
10. The generated private key was in the state in plain text (`-----BEGIN OPENSSH PRIVATE KEY-----`, no passphrase). Anyone who can read the state (or old state versions) has it; `sensitive` only hides it on screen. Ways to avoid: generate the key outside Terraform and pass only the **public** key; create secrets with `az` in Key Vault and read them at runtime with a managed identity. Others: write-only arguments (`value_wo`), Entra ID login for VMs (no keys at all). **Correction:** I said "save the key in a gitignored variable"; any value passed to a resource attribute ends up in state. What makes the SSH key safe is that only the public half goes through Terraform.
11. Before: anyone who could call `listKeys` (Owner, Contributor, Storage Account Contributor at the account, RG or subscription), meaning me and the CI app, plus anyone holding a copy of the key or a SAS signed with it. Keys never expire, aren't per person, and copies can't be revoked without rotating. Now: only identities with a blob data role (me and the CI app, `Storage Blob Data Contributor` on the account), using short-lived Entra tokens logged per identity. Contributor has `Actions` but no `DataActions`, so it can't read blobs with a token. Order: add the new path and verify it (roles → local backend → CI), then remove the old one (keys off). **Correction:** I said disabling keys first would stop me assigning roles; role assignments go through ARM and would still work, but Terraform and CI would be broken until everything was switched.
12. CI has no long-lived secrets left (OIDC; the IDs and the public key aren't secrets). Left: the SSH private key on my laptop (next: Entra ID login for VMs, `az ssh vm`), the storage account keys (disabled, then rotated both with `az storage account keys renew`), and the local `az`/git credentials (MFA, passphrase). **Correction:** I named `ssh_public_key`; it's public, not a secret.

## Summary

- **OIDC instead of a client secret:** GitHub's OIDC token (audience `api://AzureADTokenExchange`) is exchanged in Entra for a short-lived Azure token. The federated credential matches issuer, subject and audience exactly. This repo uses the immutable subject format; PR jobs present `:pull_request` and need their own credential. The client secret is deleted.
- **Managed identity + Key Vault (RBAC):** the VM gets a token from IMDS (`169.254.169.254`, only reachable from inside the VM) and reads the secret with `Key Vault Secrets User`. Removing the role gives 403 while the token still works: identity = who, role = what. Create secret values with `az`, not Terraform.
- **azurerm 3.x quirk:** adding an identity to an existing VM leaves `principal_id` unknown at plan time, so `apply -target=module.vm` first. Adding the identity was an in-place `~`, not a replacement.
- **Azure Policy:** a definition is a rule template (built-ins looked up with a `data` source by `display_name`); an assignment applies it to a scope with parameters (`jsonencode`, with an extra `value` level). Policy is checked by ARM at `apply`, not at `plan`. Policy limits **what**, RBAC limits **who**.
- **Secrets in state:** `tls_private_key` put a private key into state in plain text. `sensitive` only masks output; old state versions keep it too.
- **Backend with Entra auth:** data-plane roles for me and CI → `use_azuread_auth = true` in all three roots (`init -reconfigure`) → CI verified → `--allow-shared-key-access false` → both keys rotated.
- **Practical lessons:** remove `| jq` to see real errors; `az account show` reads the local cache (use `--refresh`); a disabled subscription is read-only, and `listKeys` counts as a write; budgets live at a scope (billing account vs subscription) and only alert, they don't stop spending.
