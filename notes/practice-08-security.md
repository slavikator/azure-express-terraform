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

1.
2.
3.
4.
5.
6.
7.
8.
9.
10.
11.
12.
