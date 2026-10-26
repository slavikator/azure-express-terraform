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

## Going deeper

### 8. How a module is "called": inputs, outputs, scope

A module is like a function:

| Function (JavaScript) | Module (Terraform) |
|---|---|
| parameters | `variable` blocks in the module |
| arguments passed in a call | arguments in the `module "x" { ... }` block |
| return value | `output` blocks in the module |
| local variables | `locals` and resources inside the module |

- **A module sees only its own inputs.** Inside `modules/network`, you can't write `azurerm_resource_group.rg.name` or `var.location` from the root. Everything the module needs must be passed in as a variable.
- **The root sees only the module's outputs:** `module.network.subnet_id`. It can't reach `module.network.azurerm_subnet.main` directly in expressions.
- That's why a module is reusable: it depends only on what you pass in.

### 9. Addresses inside modules

Resources in a module get the prefix `module.<name>.`:

```
azurerm_virtual_network.main                    # in the root
module.network.azurerm_virtual_network.main     # inside module "network"
module.vm["web"].azurerm_linux_virtual_machine.this   # a module with for_each
```

That's why moving resources into a module changes their addresses, and why it needs `moved` blocks (section 5). In `state list`, `plan`, `-replace` and `import`, you always use the full address.

### 10. Meta-arguments on modules

The same meta-arguments as on resources work on a whole module call:

```hcl
module "vm" {
  source   = "./modules/vm"
  for_each = { web = "Standard_B2ls_v2", api = "Standard_B2ls_v2" }
  name     = each.key
  vm_size  = each.value
}
```

`count`, `for_each`, `depends_on` and `providers` work. `lifecycle` doesn't: it belongs inside the module, on its resources.

### 11. Providers and modules

- A child module **inherits** the root's default provider configuration. That's why a module has no `provider` block, only `required_providers` (source and a minimum version) in `versions.tf`.
- To give a module a **different** provider (another subscription or region), pass it explicitly:

```hcl
module "network_prod" {
  source    = "./modules/network"
  providers = { azurerm = azurerm.prod }
}
```

- A module that needs **two** providers declares `configuration_aliases` in its `required_providers`.

### 12. Designing module inputs

- **Few, typed, described inputs.** Every variable has `type` and `description`.
- **Required vs optional:** no `default` for values the caller must decide (names, address space); a sensible `default` for the rest.
- **`optional()` in objects** for settings most callers don't need: `optional(string, "Standard_LRS")`.
- **`validation`** in the module protects every caller at once.
- **Pass IDs, not names, between modules** (`subnet_id`), so the module doesn't have to look things up.
- **Names:** take a `name` or `name_prefix` input and build resource names from it, so the same module works in dev and prod without collisions.

### 13. Versioning modules

| Source | How the version is pinned | Update |
|---|---|---|
| local `./modules/x` | not pinned: always the current files | every change applies immediately to every caller |
| git | `?ref=v1.2.0` (a tag) or `?ref=<commit SHA>` | change the `ref`, then `terraform init` |
| Terraform Registry | `version = "~> 1.2"` | `terraform init -upgrade` |

- Use **semantic versioning**: `MAJOR.MINOR.PATCH`. A new major version means breaking changes (renamed inputs, recreated resources).
- **A tag can be moved; a commit SHA can't.** For maximum safety, pin to a SHA.
- Downloaded modules go to `.terraform/modules/`. The lock file does **not** pin module versions (week 2).
- **Private git repositories** need credentials: locally through your git setup (`gh auth setup-git`), in CI through a token, e.g. `git config --global url."https://x-access-token:${TOKEN}@github.com/".insteadOf "https://github.com/"`.

### 14. Sharing data between states

When the network and the applications live in separate states, the application needs the network's IDs. Options:

| Method | How | Trade-off |
|---|---|---|
| `terraform_remote_state` | read the other state's **outputs** | simple, but needs read access to that whole state, secrets included |
| data sources | `data "azurerm_subnet"` by name | no access to the other state; depends on naming conventions |
| a shared store | the producer writes IDs to Key Vault or App Configuration, the consumer reads them | the most decoupled, more setup |

Data sources are usually the safest default.

### 15. Module anti-patterns

- **A "god module"** that creates everything, with 50 inputs. Split it by responsibility.
- **A thin wrapper** around one resource that just passes every argument through. It adds a layer and no value.
- **Too deep nesting:** modules calling modules calling modules. Two levels are usually enough.
- **Hard-coded values** inside a module (a region, a name) that make it usable only once.

### 16. Testing modules

- `terraform validate` and `terraform plan` on an example configuration that calls the module;
- **`terraform test`** (Terraform 1.6+): `.tftest.hcl` files with `run` blocks and `assert` conditions, run against a plan or a real temporary deployment;
- static checks in CI: `tflint`, `checkov` (week 9).

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

Move your project's network into `modules/network` and the VM into `modules/vm`. Move the existing resources with `moved` blocks so that `plan` shows no `destroy`. Bring up dev and prod with separate states. The hands-on exercise is in [`practice-06-modules.md`](practice-06-modules.md).

## Interview questions

- What is a module, and why is it needed?
- Why don't you write `backend` and `provider` in a child module?
- Workspaces or separate directories for dev/prod: which would you choose, and why?
- How do you version modules for several teams?
- How do you move resources into a module without recreating them?
- What should go into a module's outputs?
- How do you split one large state, and why?
- What is Terragrunt, and what problem does it solve?
- What can and can't a module see from the root configuration?
- How do you pass a different provider (another subscription) to a module?
- Why pin a module to a commit SHA rather than a tag?
- How does one state get values from another? Compare the options.
- What makes a module badly designed?
- How do you test a Terraform module?
