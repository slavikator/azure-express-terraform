# Week 2. Terraform basics

How to write configuration: resources, variables, dependencies, provider versions.

## Terms

| Term | What it is, in one sentence |
|---|---|
| **IaC** | Infrastructure as Code: infrastructure is described in code, not created by hand |
| **HCL** | HashiCorp Configuration Language, the language of `.tf` files |
| **Provider** | A plugin that translates Terraform resources into API calls (here `azurerm`) |
| **Resource** | An object Terraform manages: creates, changes, deletes |
| **Data source** | Reading an existing object that Terraform doesn't manage |
| **Variable** | An input parameter of the configuration |
| **Local** | A computed value for reuse inside the configuration |
| **Output** | A value the configuration exposes to the outside |
| **Lock file** | `.terraform.lock.hcl`, pins exact provider versions and their hashes |
| **Declarative** | You describe the desired result, not the steps. Terraform decides what to do |

## Concepts you need to explain in your own words

### 1. The workflow

```
init  →  validate  →  plan  →  apply  →  destroy
```

| Command | What it does |
|---|---|
| `init` | Downloads providers and modules, connects the backend. Run it first, and after changes to providers, modules or the backend |
| `validate` | Checks syntax and types. Doesn't contact Azure |
| `fmt` | Formats code to the standard style. `fmt -check` in CI fails if the code isn't formatted |
| `plan` | Compares the code, the state and real Azure. Shows what will change |
| `apply` | Executes the plan |
| `destroy` | Deletes everything in the state |

### 2. Symbols in the plan

| Symbol | Meaning |
|---|---|
| `+` | create |
| `-` | delete |
| `~` | change in place (update in-place) |
| `-/+` | delete and create again (replace). Dangerous: data on the resource will be lost |
| `<=` | read a data source |

The `# forces replacement` line shows which attribute forces Terraform to recreate the resource.

How to know in advance: in the resource's documentation on registry.terraform.io, such arguments are marked *"Changing this forces a new resource to be created"*.

| Change | Result |
|---|---|
| `name`, `location` | `-/+`, recreation |
| `tags`, VM `size` | `~`, change in place |

### 3. Provider versions

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
```

| Constraint | What it allows |
|---|---|
| `= 3.117.1` | only this version |
| `~> 3.0` | `3.x`, but not `4.0` |
| `~> 3.117.0` | `3.117.x`, but not `3.118` |
| `>= 3.118.0` | any newer version, including `4.x`, `5.x` |

**A story from my project:** the constraint `>= 3.118.0` pulled in azurerm 5.8.0, which had a bug with deleting Container Apps. With `~> 3.0` this wouldn't have happened.

### 4. The lock file

`init` writes the exact version of each provider and its hashes to `.terraform.lock.hcl`. The next `init` uses exactly those versions, even if newer ones have been released.

- The lock file is **committed**, so everyone (you, colleagues, CI) has the same versions.
- To upgrade versions on purpose: `terraform init -upgrade`.
- In my project, the lock file was in `.gitignore`. Because of that, 3.117.1 was installed locally, while CI took the newest version every time.

#### What's inside (my file)

```hcl
provider "registry.terraform.io/hashicorp/azurerm" {
  version     = "3.117.1"          # exact version
  constraints = "~> 3.0"           # constraint from required_providers
  hashes = [
    "h1:j6wnjp...=",               # 1 h1 hash
    "zh:0c5136...",                # 12 zh hashes
    ...
  ]
}
```

- **`zh:`**: hashes of the archives from the registry, one per platform (linux_amd64, darwin_arm64, ...);
- **`h1:`**: a hash of the contents, only for platforms where `init` was run (I have one, for Mac).

To add hashes for all your platforms: `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`.

#### How the file changes

| Command | What it does |
|---|---|
| `init` (no file) | creates it, choosing the newest version within the constraint |
| `init` (file exists) | **takes the version from the file**, even if a newer one exists |
| `init -upgrade` | chooses the newest allowed version and overwrites the file |
| `providers lock` | adds hashes for the specified platforms |
| `init -lockfile=readonly` | forbids changes to the file, useful in CI |

The file isn't edited by hand.

#### What the lock file doesn't pin

- **modules**: pinned with `version` (Registry) or `?ref=` (git) in `source`;
- **the Terraform version**: pinned with `required_version` and `terraform_version` in CI.

#### Lock file vs state lock

| | Lock file (dependency lock) | State lock |
|---|---|---|
| What it is | the `.terraform.lock.hcl` file | a temporary lock on the state |
| What it's for | the same provider versions | stopping two processes from changing the state at once |
| Where | in git | on the state blob in Azure Storage (lease) |
| How long it lives | permanently | only during `plan` / `apply` |

#### How to answer in an interview

1. **What does it store?** Exact provider versions, the constraints they were chosen from, and hashes for integrity checks.
2. **Why commit it?** So everyone (locally, colleagues, CI) has the same versions, and an upgrade is a deliberate step through a PR, not an accidental auto-upgrade.
3. **How do you upgrade?** `terraform init -upgrade` picks the newest version within the constraint and overwrites the file. For a new major version, change the constraint first. Commit the updated file.
4. **`h1:` and `zh:`?** Checksums to make sure the provider hasn't been tampered with. `zh:` covers the registry archives for every platform, `h1:` covers the contents for platforms where `init` was run.
5. **Does it pin modules?** No, only providers. Modules are pinned with `version` or `?ref=`.
6. **Lock file or state lock?** The lock file pins provider versions and lives in git. A state lock is a temporary lock on the state during `plan` or `apply`. In Azure, it's a lease on the blob.

### 5. `resource` and `data`

```hcl
# create and manage
resource "azurerm_resource_group" "rg" {
  name     = "rg-demo"
  location = "swedencentral"
}

# only read something that already exists
data "azurerm_client_config" "current" {}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}
```

A reference to a resource: `<type>.<name>.<attribute>`. To a data source: `data.<type>.<name>.<attribute>`.

#### Local name vs `name`: how to answer in an interview

```hcl
resource "azurerm_virtual_network" "vnet" {   # ← local name, for Terraform
  name = "vnet-demo"                          # ← name in Azure, visible in the portal
```

> The local name exists only in Terraform: it forms the resource's address in the state (`azurerm_virtual_network.vnet`), and the code refers to the resource through it. Azure doesn't know about it. `name` is the real name of the resource in Azure, visible in the portal. Changing them has different consequences: if you change the local name, Terraform decides it's a new resource and proposes deleting the old one, which is why renames use a `moved` block. If you change `name`, the resource will be recreated, because a name in Azure can't be changed.

| | Local name (`vnet`) | `name` (`vnet-demo`) |
|---|---|---|
| Who knows it | only Terraform | Azure |
| What it's for | references in code, the address in the state | the resource's real name |
| Uniqueness | within the resource type in one module | by Azure's rules: a VNet within an RG, a storage account globally |
| If you change it | destroy + create, unless there's a `moved` | `-/+`, recreation |

#### Resource address: how to answer in an interview

> A resource address is its unique identifier inside Terraform, made of the type and the local name: `azurerm_virtual_network.vnet`. With `count`, an index is added (`[0]`); with `for_each`, a key (`["web"]`); in a module, the prefix `module.<name>.`. Terraform uses the address to link a resource in the code with an entry in the state. It's used in `plan` output, in the commands `state list`, `state show`, `state mv`, `state rm`, `import`, `apply -replace`, and in `moved` and `import` blocks.

Address forms:

```
azurerm_virtual_network.vnet                    # a plain resource
azurerm_public_ip.pip[0]                        # with count, by index
azurerm_linux_virtual_machine.vm["web"]         # with for_each, by key
module.network.azurerm_virtual_network.this     # a resource in a module
data.azurerm_client_config.current              # a data source
```

Where it's used:

- `terraform state list`: a list of all resource addresses;
- `plan` output: `# azurerm_virtual_network.vnet will be created`;
- `state show`, `state rm`, `state mv`, `import`, `apply -replace=...`, `plan -target=...`;
- `moved` and `import` blocks (`from`, `to`).

#### Argument vs attribute, `(known after apply)`: how to answer in an interview

> An argument is an input: a value I set on a resource in the code, like `name` or `location`. An attribute is an output: a value the resource exposes, which you can refer to, e.g. `azurerm_public_ip.pip.ip_address`. Attributes include all arguments plus computed values determined by the provider or Azure: `id`, IP addresses. Until the resource is created these values don't exist, and `plan` marks them `(known after apply)`. That mark carries over to resources that refer to them. That's why computed values can't be used in `count` or in `for_each` keys: Terraform needs to know them already during `plan`.

```hcl
resource "azurerm_public_ip" "pip" {
  name              = "pip-demo-vm"   # argument (input)
  allocation_method = "Static"        # argument (input)
}

output "ip" {
  value = azurerm_public_ip.pip.ip_address   # attribute (output), set by Azure
}
```

- The difference is the **direction**: an argument is what I pass in, an attribute is what the resource gives back.
- **Computed** attributes are calculated by the provider or Azure, not by me.
- The error when using a computed value in `count` or `for_each`: *"value depends on resource attributes that cannot be determined until apply"*.

#### Data sources in detail

A data source **reads** something that already exists and lets you use that data in code, **without taking it under management**.

```hcl
data "azurerm_resource_group" "tfstate" {
  name = "rg-tfstate"          # argument = search criterion
}

output "tfstate_location" {
  value = data.azurerm_resource_group.tfstate.location   # attribute = the data found
}
```

| | `resource` | `data` |
|---|---|---|
| What it does | creates, changes, deletes | only reads |
| Who owns it | Terraform | someone else: a person, another team, another state |
| `destroy` | deletes the resource | deletes nothing |
| If the object doesn't exist | creates it | **error**, `plan` fails |
| In the plan | `+`, `~`, `-` | `<=` or not shown |

Typical cases in Azure:

| Data source | What it's for |
|---|---|
| `azurerm_client_config` | `tenant_id`, `subscription_id`, `client_id`, `object_id` of whoever runs Terraform. `object_id` is needed, for example, to give yourself access to a Key Vault |
| `azurerm_subscription` | the subscription's ID and name |
| `azurerm_virtual_network` | a shared network (hub) managed by another team |
| `azurerm_key_vault_secret` | a secret from Key Vault. **The value ends up in the state** |
| `terraform_remote_state` | outputs of another state: connecting separate states (network and applications) |

When it's read:

- usually **during `plan`**, and it's not shown in the plan;
- if its arguments depend on `(known after apply)` values, reading is deferred to `apply`: the plan shows `<= data.xxx will be read during apply`;
- it's read on **every** `plan` and `apply`, so the data is always fresh.

`data` vs `import`:

- **`data`**: you need a resource's data, but someone else manages it;
- **`import`**: from now on, I manage this resource.

A typical mistake is `import`ing a shared resource (a hub VNet): then your `destroy` may delete a network others depend on.

In my project: `rg-tfstate` was created by hand and must not be deleted by Terraform, so if it's needed in code, it's only through `data`.

### 6. Variables, locals, outputs

```hcl
variable "location" {
  type        = string
  default     = "swedencentral"
  description = "Region for all resources"

  validation {
    condition     = contains(["swedencentral", "northeurope"], var.location)
    error_message = "Only swedencentral and northeurope are allowed."
  }
}

variable "admin_password" {
  type      = string
  sensitive = true    # not shown in plan and logs, but stored in plain text in the state
}

locals {
  prefix = "demo"
  tags = {
    project = "azure-demo"
    env     = "dev"
  }
}

output "rg_name" {
  value = azurerm_resource_group.rg.name
}
```

Variable types: `string`, `number`, `bool`, `list(...)`, `set(...)`, `map(...)`, `object({...})`, `tuple([...])`.

#### Variables in detail

All block arguments (none is required):

```hcl
variable "vm_size" {
  type        = string
  default     = "Standard_B2ls_v2"
  description = "VM size"
  sensitive   = false
  nullable    = false                       # forbid null
  validation {
    condition     = startswith(var.vm_size, "Standard_")
    error_message = "The size must start with Standard_."
  }
}
```

**Required or not:** without `default`, a variable is required (like `ssh_public_key`). Make values that differ between environments, and secrets, have no `default`, so they can't be forgotten.

**Types:**

```hcl
list(string)      # ["a", "b"], order matters, duplicates allowed
set(string)       # unique, unordered; suitable for for_each
map(string)       # { key = "value" }

object({           # fields of different types
  size    = string
  disk_gb = number
  zones   = optional(list(string), [])   # the field can be omitted
})

map(object({ size = string }))           # typical for for_each
```

The type lets Terraform check the value before contacting Azure and give a clear error.

**`validation`:**

- there can be several blocks;
- it runs at the start of `plan`, before any calls to Azure;
- since Terraform 1.9, `condition` can refer to other variables;
- useful functions: `contains`, `can(regex(...))`, `length`, `startswith`, `alltrue`.

**`sensitive` and `ephemeral`:**

- `sensitive = true` hides the value from `plan` and logs; an output using such a variable must also be `sensitive`;
- **in the state, the value is stored in plain text**;
- `ephemeral = true` (Terraform 1.10+): the value goes into neither the plan nor the state, but it can only be used where Terraform doesn't need to store it.

**Passing complex types** uses HCL syntax:

```
terraform plan -var='zones=["1","2"]'
export TF_VAR_tags='{ env = "dev", owner = "me" }'
```

| File | Loaded | Typical use |
|---|---|---|
| `terraform.tfvars` | automatically | local values |
| `*.auto.tfvars` | automatically | additional values |
| `prod.tfvars` | only with `-var-file` | values for an environment |

Files without secrets (`dev.tfvars`, `prod.tfvars`) are usually committed; secrets are passed through `TF_VAR_` from CI secrets.

**What variables can't do:**

- they don't work in the `backend` block (it's configured before variables are read) → use `-backend-config`;
- `default` can't refer to resources or other variables, only a constant → `locals` are for computed values;
- `var.x` is read-only.

**In modules,** variables are the module's inputs: `type`, `description` and `validation` form the module's contract.

**Conventions:** all variables in `variables.tf`, names in `snake_case`, every variable has a `type` and `description`, and only things that actually change become variables.

#### Locals in detail

A local is a named value inside the configuration: the expression is written once and used by name.

The block is **`locals`** (plural), and you refer to it as **`local.x`** (singular). There can be several blocks; names are unique within a module.

Why:

```hcl
locals {
  # don't repeat an expression
  name_prefix = "${var.project}-${var.env}"

  # give a complex expression a name
  is_prod = var.env == "prod"
  vm_size = local.is_prod ? "Standard_D2s_v5" : "Standard_B1s"

  # merge data
  tags = merge(var.extra_tags, {
    env        = var.env
    managed_by = "terraform"
  })

  # prepare data for for_each
  subnets = {
    app  = cidrsubnet(var.address_space, 8, 1)
    mgmt = cidrsubnet(var.address_space, 8, 2)
  }
}
```

What it can refer to: variables, other locals, resources, data sources, functions. If it refers to a `(known after apply)` value, it becomes one too, and can't be used for `count` or `for_each` keys. Circular references are forbidden.

| | `variable` | `local` | `output` |
|---|---|---|---|
| Direction | **input** from outside | **internal** value | **output** to the outside |
| Who sets it | the user: `-var`, `tfvars`, `TF_VAR_` | the code author | the code author |
| Can be changed from outside | yes | **no** | no |
| Expressions and references to resources | no, `default` is a constant only | yes | yes |
| Analogy | a function parameter | a function's local variable | a function's return value |

How to choose:

- set by whoever runs the code (region, size, environment) → `variable`;
- computed, or an internal convention (name prefix, common tags) → `local`;
- needed outside the module (IP, subnet ID) → `output`.

What to avoid: a local for every obvious value; long chains of locals with complex logic; a local instead of a variable when the value should differ between environments.

#### Outputs in detail

An output is a value the configuration exposes to the outside: to a person, a CI script, another module or another state.

```hcl
output "vm_public_ip" {
  value       = azurerm_linux_virtual_machine.vm.public_ip_address
  description = "Public IP address of the Virtual Machine"
}
```

| Argument | What it does |
|---|---|
| `value` | **required**: any expression |
| `description` | an explanation, especially important in modules |
| `sensitive` | hide it from `plan` and `apply` output |
| `depends_on` | an explicit dependency, rarely needed |
| `precondition` | a check before the value is returned |

Where you see it:

```
terraform output                     # all
terraform output vm_public_ip        # one, in quotes
terraform output -raw vm_public_ip   # without quotes, for scripts
terraform output -json               # JSON, for programs
```

- `terraform output` **doesn't contact Azure**; it reads the **state**, so it shows the values as of the last `apply`.
- In the plan, changes are shown in a separate `Changes to Outputs` section.

Why:

- **for people**: IP, URL, names;
- **for CI**: through `-raw`: `echo "ACR_SERVER=$(terraform output -raw acr_login_server)" >> $GITHUB_ENV`;
- **for modules**: they're the module's public interface; the root sees only its outputs, `module.network.subnet_id`;
- **for other states**: `terraform_remote_state` reads **only outputs**, not resources.

`sensitive`:

- `plan` and `apply` show `<sensitive>`;
- if an output uses a sensitive value, `sensitive = true` is required, otherwise there's an error;
- **the value isn't secret**: `terraform output -raw` and `-json` show it in plain text, and it's in plain text in the state.

Conventions: outputs in `outputs.tf`; expose specific values (`id`, `name`, IP), not the whole resource; every module output has a `description`.

### 7. Where a variable's value comes from

From lowest to highest priority (each one overrides the previous):

1. `default` in the `variable` block
2. environment variables `TF_VAR_<name>`
3. `terraform.tfvars`
4. `terraform.tfvars.json`
5. `*.auto.tfvars` (in alphabetical order)
6. `-var` and `-var-file` on the command line (in the order written)

If there's no value anywhere, Terraform asks interactively. In CI this means hanging, so there it's always `-input=false`.

**In my project:** locally, `ssh_public_key` comes from `terraform.tfvars`, and in CI from `TF_VAR_ssh_public_key` (the `SSH_PUBLIC_KEY` secret).

### 8. Dependencies

- **Implicit:** if a resource refers to another's attribute (`subnet_id = azurerm_subnet.subnet.id`), Terraform creates them in the right order by itself.
- **Explicit:** `depends_on = [...]` only when there's a dependency but no reference. For example, a VM has to wait until an RBAC role exists.
- Terraform creates independent resources in parallel (up to 10 at once by default).

`terraform graph` prints the dependency graph in DOT format.

### 9. Providers

#### How Terraform is built

```
Terraform core                        Providers (plugins)
─────────────────                     ─────────────────────
reads .tf files                       azurerm  → Azure ARM API
builds the dependency graph    ──►    azuread  → Microsoft Graph API
compares code with state              random   → nothing, generates values
decides: create/update/delete         github   → GitHub API
```

**Core** knows nothing about Azure; it decides **what** to do. The **provider** knows **how**: which APIs to call, which fields are required, how to wait for an operation to finish. That's why the same Terraform works with Azure, AWS, GitHub and Cloudflare.

#### Where a provider comes from

- `source = "hashicorp/azurerm"` is an address in the Terraform Registry: `<namespace>/<name>`.
- `terraform init` downloads it from registry.terraform.io into `.terraform/providers/`. That's why `.terraform/` is in `.gitignore`: it's binaries, not code.
- A provider has **its own version**, independent of the Terraform version.
- The resource type prefix shows the provider: `azurerm_resource_group` → `azurerm`, `random_string` → `random`.
- Major versions (3 → 4 → 5) break compatibility. For version constraints and the lock file, see sections 3 and 4.

#### The `provider` block

```hcl
provider "azurerm" {
  features {}                 # required for azurerm, even if empty
  subscription_id = "..."     # required in azurerm 4.x+
}
```

- `features {}` configures behavior, e.g. `resource_group { prevent_deletion_if_contains_resources = false }`. This exact check stopped `destroy` from deleting a group that still contained `cae-demo`.
- In azurerm 3.x, `subscription_id` can be omitted; it's then taken from `az` or `ARM_SUBSCRIPTION_ID`.

#### How `azurerm` signs in to Azure

| Method | Where |
|---|---|
| `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` | my CI right now |
| OIDC (`ARM_USE_OIDC=true`) | week 8 |
| managed identity (`ARM_USE_MSI=true`) | Terraform on a VM in Azure |
| Azure CLI (`az login`) | locally on the Mac |

That's why locally Terraform runs as my account, and in CI as `github-actions-terraform`.

#### Several providers: `alias`

```hcl
provider "azurerm" {
  features {}
}

provider "azurerm" {
  alias           = "prod"
  features {}
  subscription_id = "<another subscription>"
}

resource "azurerm_resource_group" "prod_rg" {
  provider = azurerm.prod
  ...
}
```

This is how one codebase manages several subscriptions or regions.

#### Providers in Azure projects

| Provider | What it's for |
|---|---|
| `azurerm` | Azure resources through ARM |
| `azuread` | Entra ID: app registrations, groups, users (through Microsoft Graph) |
| `azapi` | any Azure resource directly through the ARM API, even a new one not yet in `azurerm` |
| `random` | random names, suffixes, passwords |
| `tls` | keys and certificates |

`azurerm` vs `azuread` is the same difference as `az group` vs `az ad`: ARM vs Microsoft Graph.

### 10. The declarative approach

**Declarative**: I describe the **desired result** ("a VNet with these parameters must exist"). **Imperative**: I describe the **steps** ("create a group, then a VNet, then a subnet").

Imperative (a script):

```bash
az group create -n rg-demo -l swedencentral
az network vnet create -g rg-demo -n vnet-demo --address-prefix 10.0.0.0/16
```

Declarative (Terraform): `resource` blocks, and their order in the files doesn't matter.

| Situation | `az` script | Terraform |
|---|---|---|
| Running again with no changes | the commands run again, some fail with "already exists" | `No changes` |
| A parameter changed | write a new `update` command | change the value in the code |
| A resource removed | write a `delete` command | delete the block from the code |
| A change in the portal | the script never finds out | `plan` shows it and reverts it to the code |

**Idempotency**: however many times you run it, the result is the same. The declarative approach gives you this automatically.

How Terraform does it: **reconciliation**:

```
Desired state (code)  ─┐
                       ├──►  plan: the difference  ──►  apply: actions to remove the difference
Current state ─────────┘
(state + refresh from Azure)
```

**In my project:** after a manual `destroy`, a push recreated the VM. For the declarative approach that's correct: the code says "the VM must exist". To make a resource go away, you remove it **from the code**.

| Advantages | Disadvantages |
|---|---|
| the code describes the current state and reads like documentation | less control over the order of execution |
| idempotency out of the box | limited logic |
| you see the difference before changes (`plan`) | you need state, and you have to protect it |
| drift detection | one-off procedures (migrations, restarts) are awkward to express |

In practice they're combined: Terraform declaratively describes the infrastructure, and one-off actions are run by imperative scripts in CI.

Other tools: **Bicep/ARM** are declarative without state; **Kubernetes** has declarative manifests with continuous reconciliation; **Ansible** has declarative modules, but a playbook runs step by step; **Pulumi** has a declarative model in an imperative language.

#### How to answer in an interview

> The declarative approach means I describe the desired end state, not the steps. Terraform compares the code with the state and the real state in Azure, and decides by itself what to create, change or delete, and in what order. That gives idempotency: a repeated `apply` with no changes does nothing. Deletion is declarative too: to make a resource go away, you remove it from the code. In the imperative approach, like a script of `az` commands, I set the sequence of actions myself, and I have to handle reruns, changes and deletions by hand.

## Commands to know by heart

```
terraform init
terraform init -upgrade          # upgrade providers within constraints
terraform fmt -recursive
terraform validate
terraform plan
terraform plan -var="location=northeurope"
terraform apply -auto-approve -input=false
terraform output
terraform output -raw vm_public_ip
terraform console                # interactive expression testing
terraform providers              # which providers are needed and where from
```

## Common mistakes

- An empty `backend {}` block or a variable without a value: in CI, Terraform waits for input and hangs.
- A version constraint with no upper bound (`>=`): an unexpected jump to a new major version.
- `sensitive = true` doesn't encrypt the value in the state; it only hides it from output.
- The lock file in `.gitignore`: different provider versions in different environments.

## Check yourself

Without documentation, write from scratch an RG + VNet + subnet with a `location` variable, tags through `locals`, and an output with the subnet ID. Explain every line.

## Interview questions

- What does `terraform init` do?
- Why have a lock file, and why commit it?
- `~> 3.0` vs `>= 3.0`: what can happen with the second one?
- In what order does Terraform take variable values?
- `resource` vs `data`: what's the difference?
- When do you need `depends_on`?
- What does `-/+` mean in a plan, and why is it dangerous?
- Does `sensitive = true` protect a secret in the state?
- What is a provider, and how does it relate to Terraform core?
- Where does Terraform get a provider from, and where is it stored?
- How does the `azurerm` provider authenticate to Azure?
- How do you manage two subscriptions from one codebase?
- What do you do if a resource you need isn't in `azurerm` yet?
- What happens if the object a data source reads doesn't exist?
- When is a data source read during `plan`, and when during `apply`?
- `data` or `import`: when to use which?
- How do you get the subscription ID and object ID of whoever runs Terraform?
- How do you pass values from one state to another?
- How do you make a variable required?
- What does `optional()` do in an `object`?
- How does `validation` work, and when does it run?
- `sensitive` or `ephemeral`: which one protects the state?
- Why can't variables be used in `backend`?
- How does a `variable` differ from a `local`?
- How do you pass a secret to Terraform in CI?
- When do you use a `local`, and when a `variable`?
- Can a `local` be overridden from outside?
- What can a `local` refer to?
- How do you apply common tags to all resources?
- Why do you need outputs? Give three scenarios.
- Where does `terraform output` get its values?
- How does `-raw` differ from `-json` and the normal output?
- How does a module pass data to the root module?
- Does `sensitive = true` protect an output's value?
- What can you read from another state through `terraform_remote_state`?
- What do the `h1:` and `zh:` hashes mean?
- Does the lock file pin module versions?
- How does the lock file differ from a state lock?
- Declarative vs imperative: what's the difference?
- What is idempotency, and how does Terraform provide it?
- Why doesn't the order of blocks matter in Terraform?
- How do you delete a resource in the declarative approach?
- Is Ansible declarative or imperative?
