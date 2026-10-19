# Week 6. Modules and environments

How to organize code the way a real team does.

## Terms

| Term | What it is, in one sentence |
|---|---|
| **Module** | A folder of `.tf` files that other code can call with parameters |
| **Root module** | The folder where you run `terraform`. It has the backend and the provider |
| **Child module** | A module called from the root through a `module` block |
| **Module source** | Where to get a module from: a local folder, git, the Terraform Registry |
| **AVM** | Azure Verified Modules, Microsoft's official modules for Azure |
| **Workspace** | Several separate states for one configuration |
| **Environment** | dev, staging, prod |
| **DRY** | Don't Repeat Yourself |
| **Terragrunt** | A wrapper around Terraform for DRY environment and backend configuration |

## Concepts you need to explain in your own words

### 1. Module structure

```
modules/network/
├── main.tf         # resources
├── variables.tf    # inputs
├── outputs.tf      # outputs
└── versions.tf     # required_providers (no provider block and no backend)
```

A module does **not** contain a `backend` block, and a `provider` block in it is considered bad practice. The root module sets them.

### 2. Calling a module

```hcl
module "network" {
  source = "./modules/network"

  name          = "vnet-demo"
  address_space = ["10.0.0.0/16"]
  location      = azurerm_resource_group.rg.location
  rg_name       = azurerm_resource_group.rg.name
}

module "vm" {
  source    = "./modules/vm"
  subnet_id = module.network.subnet_id    # one module's output → another's input
}
```

After adding or changing a `source`, you need to run `terraform init`.

### 3. Module sources

```hcl
source = "./modules/network"                                          # local
source = "git::https://github.com/org/tf-modules.git//network?ref=v1.2.0"   # git with a tag
source = "Azure/avm-res-network-virtualnetwork/azurerm"               # Registry
version = "~> 0.4"                                                    # Registry only
```

- For git, the version is pinned with `?ref=<tag>`.
- For the Registry, with `version`.
- Without a pinned version, a module update can break all environments at once.

### 4. What to expose in outputs

- **Yes:** IDs, names, addresses that other modules need (`subnet_id`, `vnet_id`).
- **No:** the whole resource, secrets without `sensitive = true`, intermediate data.

A module's inputs should be minimal and clear: 5 variables with types and descriptions are better than 30 "just in case".

### 5. Moving resources into a module without recreating them

The resource's address changes from `azurerm_virtual_network.vnet` to `module.network.azurerm_virtual_network.this`. Without a hint, Terraform deletes the old one and creates a new one.

```hcl
moved {
  from = azurerm_virtual_network.vnet
  to   = module.network.azurerm_virtual_network.this
}
```

`plan` should show `has moved to`, not `destroy`.

### 6. Environments: three approaches

**Workspaces**
```
terraform workspace new prod
terraform workspace select prod
```
- One codebase, separate states (`env:/prod/...`).
- Downsides: it's easy to `apply` in the wrong workspace, all environments share the same backend and permissions, and differences between environments have to be written with `terraform.workspace` in the code.

**Separate directories**
```
envs/
├── dev/
│   ├── main.tf          # calls modules/*
│   ├── backend.tf       # key = "dev.tfstate"
│   └── terraform.tfvars
└── prod/
    ├── main.tf
    ├── backend.tf       # key = "prod.tfstate"
    └── terraform.tfvars
modules/
├── network/
└── vm/
```
- It's obvious where `apply` goes. You can give different permissions and even different subscriptions.
- Downside: `main.tf` is duplicated between environments (this is exactly what Terragrunt solves).

**One codebase + different tfvars and backend-config**
```
terraform init -backend-config=env/prod.backend.hcl
terraform apply -var-file=env/prod.tfvars
```
- Little code, but it's easy to mix up files.

**What teams choose:** most often separate directories, or separate repositories for prod, with modules in their own repository with tags. Workspaces are recommended for temporary copies (e.g. an environment per PR), not for dev/prod.

### 7. How to split states

- A separate state for each environment.
- Often also separate states by layer: network, databases, applications. Then a mistake in an application won't affect the network, and `plan` runs faster.
- To read another state's outputs: `data "terraform_remote_state"`.

## Commands to know by heart

```
terraform init                     # after changing a module source
terraform get -update              # update modules
terraform workspace list
terraform workspace new <name>
terraform workspace select <name>
terraform state list | grep module.network
```

## Check yourself

Move your project's network into `modules/network` and the VM into `modules/vm`. Move the existing resources with `moved` blocks so that `plan` shows no `destroy`. Bring up dev and prod with separate states.

## Interview questions

- What is a module, and why is it needed?
- Why don't you write `backend` and `provider` in a child module?
- Workspaces or separate directories for dev/prod: which would you choose, and why?
- How do you version modules for several teams?
- How do you move resources into a module without recreating them?
- What should go into a module's outputs?
- How do you split one large state, and why?
- What is Terragrunt, and what problem does it solve?
