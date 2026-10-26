# Week 6 practice: "One codebase, two environments"

**Goal:** restructure the project the way a real team would: the network and the VM become reusable modules, dev and prod become two small root configurations with separate states, the existing dev infrastructure moves into the modules **without being recreated**, and the network module gets a version through a git tag.

**Topics:** module structure, inputs and outputs, `moved` into modules, separate directories per environment, backend keys, CI for several environments, versioning with git tags.

**Time:** 2.5–3 hours, best split into two or three sessions. **Cost:** about $0.05 per hour per running VM. There's a `destroy` at the end.

**Notes:** [`06-modules-environments.md`](06-modules-environments.md)

---

## Rules for this practice

1. **Guess first, then check.** Before every `plan`, write down what it will show.
2. **Moving dev into modules must end with `No changes`.** It's a refactor: the same resources, only different addresses.
3. **Don't push until Step 5.** Until the workflow is updated, CI runs in the repo root, and after Step 4 there's no configuration there.
4. **Mind the trial quotas:** 4 vCPUs and 3 public IPs per region. Dev and prod together use 4 vCPUs and 2 public IPs, which fits, but only if nothing else is running.

---

## The target structure

```
azure/demo/
├── modules/
│   ├── network/              # VNet, subnets, NSG, NSG ↔ subnet association
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   └── vm/                   # public IP, NIC, NSG ↔ NIC association, VM
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── versions.tf
├── envs/
│   ├── dev/                  # the current infrastructure, same state key
│   │   ├── providers.tf      # backend key = "demo-node.terraform.tfstate"
│   │   ├── main.tf           # resource group + module calls + moved blocks
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── .terraform.lock.hcl
│   └── prod/                 # a new environment, new state key
│       └── ...               # backend key = "prod.terraform.tfstate"
└── notes/
```

The resource group stays in each environment's root (`envs/<env>/main.tf`), not in a module: it's the container that the modules are deployed into.

---

## Step 0. Preparation

The existing infrastructure must exist **before** you restructure, otherwise you can't prove the move with `No changes`.

```
cd ~/azure/demo
terraform apply
terraform plan
```

The last `plan` must show `No changes`.

---

## Step 1. Design on paper

Before writing code, decide what goes where. Look at your current files and answer:

> ❓ **1.** Which of your current resources go into `modules/network`, which into `modules/vm`, and which stay in the root? Why does the `data "azurerm_client_config"` source stay in the root?
>
> ❓ **2.** List the inputs each module needs. Hint: a module can't see the root's `var.*`, `local.*` or resources, so everything it uses from outside must be an input.

**Naming.** Prod must not collide with dev, so each module takes a `name` input and builds resource names from it. For dev, `name = "demo"` must produce **exactly** the current names, or dev will be recreated:

| Resource | Current name | Built from `name` |
|---|---|---|
| VNet | `vnet-demo` | `"vnet-${var.name}"` |
| NSG | `nsg-demo` | `"nsg-${var.name}"` |
| Public IP | `pip-demo-vm` | `"pip-${var.name}-vm"` |
| NIC | `nic-demo-vm` | `"nic-${var.name}-vm"` |
| VM | `vm-demo-node` | `"vm-${var.name}-node"` |

The subnets keep their fixed names (`snet-internal`, `snet-mgmt`): subnet names only need to be unique inside their VNet.

---

## Step 2. `modules/network`

Create the four files. Move the resources from `network.tf` and `security.tf` into `main.tf`, **keeping their local names** (`main`, `mgmt`, `nsg`, `subnet_assoc`). That makes the `moved` blocks in Step 4 simple.

- `variables.tf`: every input from your ❓2 list, each with `type` and `description`. `nsg_rules` moves here from the root.
- `outputs.tf`: what the VM module and the root need, e.g. the main subnet's ID and the NSG's ID.
- `versions.tf`: only `required_providers` with `source = "hashicorp/azurerm"`. **No `provider` block, no `backend`.**

Check it on its own:

```
cd modules/network
terraform init -backend=false
terraform validate
cd ../..
```

`-backend=false` skips the backend, which a module doesn't have.

> ❓ **3.** Why doesn't a module have a `provider` block, and where does it get its provider configuration from?

---

## Step 3. `modules/vm`

The same for the VM: the public IP, the NIC, the NSG ↔ NIC association and the VM from `security.tf` and `compute.tf`, with their local names (`pip`, `nic`, `nsg_assoc`, `vm`). Keep `custom_data`, the `lifecycle` block and the `precondition`.

- Inputs include `subnet_id` and `nsg_id`: the VM module gets them from the network module through the root, as IDs.
- An output for the public IP.

Validate it the same way.

---

## Step 4. `envs/dev`: move the existing infrastructure

1. Create `envs/dev/` and move into it: `providers.tf` (backend unchanged: same storage account, same key `demo-node.terraform.tfstate`), the root's `variables.tf` (only what the root still needs), `outputs.tf`, and `locals.tf`.
2. Copy `terraform.tfvars` and `.terraform.lock.hcl` into `envs/dev/`. The lock file keeps the same provider version (3.117.1). `terraform.tfvars` is ignored by git, so copying it is safe.
3. Write `envs/dev/main.tf`: the resource group, `module "network"` and `module "vm"` with `source = "../../modules/network"` and `"../../modules/vm"`, and `name = "demo"`.
4. Add `moved` blocks for every resource that went into a module:

| From | To |
|---|---|
| `azurerm_virtual_network.main` | `module.network.azurerm_virtual_network.main` |
| `azurerm_subnet.main` | `module.network.azurerm_subnet.main` |
| `azurerm_subnet.mgmt` | `module.network.azurerm_subnet.mgmt` |
| `azurerm_network_security_group.nsg` | `module.network.azurerm_network_security_group.nsg` |
| `azurerm_subnet_network_security_group_association.subnet_assoc` | `module.network.azurerm_subnet_network_security_group_association.subnet_assoc` |
| `azurerm_public_ip.pip` | `module.vm.azurerm_public_ip.pip` |
| `azurerm_network_interface.nic` | `module.vm.azurerm_network_interface.nic` |
| `azurerm_network_interface_security_group_association.nsg_assoc` | `module.vm.azurerm_network_interface_security_group_association.nsg_assoc` |
| `azurerm_linux_virtual_machine.vm` | `module.vm.azurerm_linux_virtual_machine.vm` |

The old `moved` blocks from week 3 (`vnet` → `main`, `subnet` → `main`) can go: the state was updated long ago.

5. Remove the old `.tf` files from the repo root with `git rm`, so git records them as moved.

**Predict**, then check:

```
cd envs/dev
terraform init
terraform plan
```

The target: nine `has moved to` lines and `0 to add, 0 to change, 0 to destroy`.

> ❓ **4.** Why does `envs/dev` see the existing infrastructure at all, even though it's a new directory? What would happen if you gave it a new backend key?
>
> ❓ **5.** What would `plan` show without the `moved` blocks? And what if `name = "demo"` produced `vm-demo` instead of `vm-demo-node`?

Apply it, and check `plan` → `No changes`.

---

## Step 5. CI for several environments

The workflow runs in the repo root, where there's no configuration anymore. Change `.github/workflows/deploy.yml`:

- `terraform fmt -check -recursive` once, from the repo root, so it covers `modules/` and `envs/`;
- `init` and `plan` in **each** environment directory. Use a `strategy.matrix` with `env: [dev, prod]` and `defaults.run.working-directory: envs/${{ matrix.env }}`;
- `apply` only for `dev`, only on manual `workflow_dispatch`.

You'll add `envs/prod` in Step 6, so the `prod` job would fail until then. Either add the matrix in Step 6, or start with `env: [dev]`.

Commit and push. Check that the dev job's `plan` shows `No changes`.

> ❓ **6.** Why must the dev job's `plan` in CI also show `No changes`? What would it mean if it showed the nine resources being created?

---

## Step 6. `envs/prod`

1. Copy `envs/dev` to `envs/prod` without `.terraform/`.
2. Change what makes it prod: the backend `key = "prod.terraform.tfstate"`, the resource group name `rg-devops-prod-swe`, `name = "prod"`, and an address space that doesn't overlap with dev, e.g. `10.1.0.0/16`.
3. Remove the `moved` blocks: prod has no history to move.

**Predict**, then check:

```
cd ../prod
terraform init
terraform plan
```

> ❓ **7.** How many resources will prod create, and why doesn't dev's state change at all?
>
> ❓ **8.** What differs between `envs/dev` and `envs/prod`, and what's duplicated? What would you do about the duplication in a bigger project?

Optionally apply prod to see both environments running side by side (4 vCPUs, the quota limit), then `terraform destroy` in `envs/prod`.

Add `prod` to the CI matrix if you haven't yet, commit and push.

---

## Step 7. Versioning the network module with a git tag

So far both environments use `source = "../../modules/network"`: any change to the module immediately affects both. Real teams pin versions.

1. Tag the current state of the repo and push the tag:

   ```
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. In `envs/prod/main.tf`, change the network module source to the tagged version:

   ```hcl
   source = "git::https://github.com/slavikator/azure-express-terraform.git//modules/network?ref=v1.0.0"
   ```

   The `//` separates the repository from the path inside it.

3. The repository is private, so git needs your credentials over HTTPS. Set that up once with `gh auth setup-git`.

4. Run `terraform init` and `plan` in `envs/prod`. Look in `.terraform/modules/` to see where the module was downloaded.

5. **Prove the pin works:** add a harmless change to `modules/network`, e.g. a new output. Run `plan` in both environments.

> ❓ **9.** Which environment sees the change, and which doesn't? Why?
>
> ❓ **10.** CI also needs to download the module from the private repository. What does the workflow need for that? (Hint: notes, section 13.)

Make CI work, e.g. with a step that rewrites `https://github.com/` to use `${{ github.token }}`, then commit and push.

> ❓ **11.** Why is pinning to a tag safer than a local path, and why is a commit SHA even safer than a tag?

---

## Step 8. Workspaces, for comparison

Don't change anything; just think it through.

> ❓ **12.** How would the same dev/prod setup look with `terraform workspace` instead of separate directories? Name two things that would be harder or riskier.

---

## Step 9. Cleanup

```
cd ~/azure/demo/envs/prod
terraform destroy          # if prod is running
cd ../dev
terraform destroy
az group exists -n rg-devops-demo-swe
az group exists -n rg-devops-prod-swe
cd ~/azure/demo
git status                 # should be clean
```

---

## Outcome

After this practice you should be able to, without looking:

- split a configuration into modules with clear inputs and outputs;
- move existing resources into modules without recreating them;
- run dev and prod from shared modules with separate states;
- run CI for several environments;
- pin a module version with a git tag, and explain the trade-offs of local paths, tags and SHAs;
- compare separate directories with workspaces.

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
