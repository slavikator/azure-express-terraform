# Week 3. State

The most important interview topic. What state is, how it breaks, and how to fix it.

## Terms

| Term | What it is, in one sentence |
|---|---|
| **State** | A JSON file where Terraform stores the link "resource in code ↔ real object in Azure" |
| **Backend** | Where the state is stored: locally or remotely (Azure Storage, S3, Terraform Cloud) |
| **Remote state** | State in shared storage, accessible to CI and the team |
| **State lock** | A lock that stops two processes from changing the state at the same time |
| **Lease** | The locking mechanism for a blob in Azure Storage. This is how the `azurerm` backend lock works |
| **Drift** | A mismatch between the state and the real state of Azure (someone changed something by hand) |
| **Refresh** | Re-reading the real state of resources before plan and apply |
| **Import** | Bringing a resource created outside Terraform under its management |
| **Taint / replace** | Marking a resource for recreation |

## Concepts you need to explain in your own words

### 1. Why state exists

Terraform doesn't search Azure for resources by name. It only knows about a resource because the resource is recorded in the state with its ID:

```
azurerm_resource_group.rg  →  /subscriptions/.../resourceGroups/rg-devops-demo-swe
```

`plan` compares three things: the **code** (what should exist), the **state** (what Terraform created) and **real Azure** (what exists now).

What the state stores:
- the ID and all attributes of every resource;
- dependencies between resources;
- output values;
- **secrets**: passwords, keys, connection strings, in plain text.

### 2. Remote backend `azurerm`

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstate1791293035"
    container_name       = "tfstate"
    key                  = "demo-node.terraform.tfstate"
  }
}
```

- The state is stored as a blob in a storage account.
- During `plan` or `apply`, Terraform takes a **lease** on that blob. A second process gets `Error acquiring the state lock` and won't corrupt the state.
- Variables **can't** be used in the `backend` block. So the values are either written explicitly or passed through `-backend-config`.

Partial configuration:

```hcl
backend "azurerm" {}          # empty block
```

```
terraform init -backend-config=backend.hcl
# or
terraform init -backend-config="key=prod.tfstate"
```

**A story from my project:** the block was empty, and CI didn't pass `-backend-config`. `terraform init` waited for interactive input, and CI hung.

### 3. How to protect state

- A separate RG for the state (`rg-tfstate`), so the project's `destroy` doesn't delete it.
- No public access to the storage account; access through RBAC.
- **Blob versioning** or soft delete, to restore a corrupted state.
- As few people with access as possible: whoever reads the state sees the secrets.

### 4. State commands

| Command | What it does | Does it touch Azure |
|---|---|---|
| `state list` | list the resources in the state | no |
| `state show <address>` | a resource's attributes from the state | no |
| `state mv <old> <new>` | rename a resource's address | no |
| `state rm <address>` | forget a resource | no, the resource stays in Azure |
| `import <address> <id>` | write an existing resource into the state | reads only |
| `force-unlock <lock id>` | release a stuck lock | no |
| `destroy` | delete resources | **yes, deletes** |

The key difference: `state rm` removes a resource only from the state, while `destroy` deletes it in Azure.

### 5. Import: block vs command

The old way, a command:
```
terraform import azurerm_resource_group.rg /subscriptions/<id>/resourceGroups/rg-manual
```

The new way (Terraform 1.5+), a block in the code that goes through `plan`:
```hcl
import {
  to = azurerm_resource_group.rg
  id = "/subscriptions/<id>/resourceGroups/rg-manual"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-manual"
  location = "swedencentral"
}
```

`terraform plan -generate-config-out=generated.tf` can even generate the resource code.

After an import, `plan` must show `No changes`. If it shows changes, the code doesn't match reality, and you have to align them. **In my project,** after importing `cae-demo`, the plan wanted to remove `workload_profile`, because Azure had added it on its own.

### 6. `moved`: renaming without recreating

If you rename a resource in the code, Terraform decides the old one must be deleted and a new one created. To avoid that:

```hcl
moved {
  from = azurerm_virtual_network.vnet
  to   = azurerm_virtual_network.main
}
```

The same works when moving resources into a module (`to = module.network.azurerm_virtual_network.main`).

There's also the `removed` block (Terraform 1.7+): remove a resource from the state through code, without deleting it in Azure.

### 7. Drift and refresh

Someone changed a tag in the portal. What happens:
- `terraform plan` shows that it will revert the tag to what's in the code;
- `terraform plan -refresh-only` shows only the difference between the state and Azure, without planning any changes;
- `terraform apply -refresh-only` writes the real state into the state file, without changing Azure.

### 8. Recreating a resource

```
terraform apply -replace=azurerm_linux_virtual_machine.vm
```

This replaced the old `terraform taint`. Useful when a resource is "broken" but the code hasn't changed. **In my project:** a change to the `custom_data` text didn't reach the VM, because cloud-init only runs on first boot.

### 9. When code, state and Azure disagree

| Situation | What to do |
|---|---|
| The resource is in Azure but not in the state | `import` |
| The resource is in the state but was deleted in Azure by hand | `plan` sees this after refresh and proposes creating it again. If the resource is no longer needed, `state rm` and remove it from the code |
| The resource was changed in Azure by hand | `plan -refresh-only`, then either revert it with `apply` or update the code |
| Apply failed halfway | Run `plan` again. Terraform writes everything it managed to create to the state |
| The lock got stuck after Ctrl+C | `force-unlock <id>`, but only if you're sure nobody else is working |

**Stories from my project:**
- Azure returned a capacity error but created the environment later. The resource was in Azure but not in the state.
- The provider didn't wait for a deletion to finish. The resource disappeared from Azure but stayed in the state. A second `destroy` helped: refresh saw that the resource was already gone.

## Commands to know by heart

```
terraform state list
terraform state show azurerm_resource_group.rg
terraform state mv <from> <to>
terraform state rm <address>
terraform import <address> <azure id>
terraform plan -refresh-only
terraform apply -replace=<address>
terraform force-unlock <lock id>
terraform state pull > backup.tfstate     # local copy of the state
```

## Check yourself

Deliberately desync the code, state and Azure in three ways: create a resource by hand, delete a resource by hand, change an attribute by hand. Recover from each case and explain what you did. The full exercise is in [`practice-03-state.md`](practice-03-state.md).

## Interview questions

- What is state, and why is it needed?
- What happens if two people run `apply` at the same time?
- How does state locking work in Azure?
- A resource was created by hand. How do you bring it under Terraform management?
- `state rm` vs `destroy`: what's the difference?
- Why is state considered a secret, and how do you protect it?
- How do you rename a resource in code without recreating it?
- Apply failed halfway. What do you do?
- What is drift, and how do you detect it?
- Why can't variables be used in the `backend` block?
