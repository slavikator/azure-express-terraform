# Week 2 practice: "Tidying up the code"

**Goal:** rewrite your own project following the week 2 rules: the lock file in git, validated variables, common tags, a data source and outputs. And before every `apply`, predict what `plan` will show.

**Topics:** lock file, variables, `validation`, variable value precedence, `locals`, `data`, `output`, dependency graph.

**Time:** 1.5–2 hours, can be split into two sessions. **Cost:** about $0.05 per hour while the VM is running. There's a `destroy` at the end.

**Notes:** [`02-terraform-basics.md`](02-terraform-basics.md)

---

## The rule for the whole practice

Before every `terraform plan`, **guess first** what it will show: how many resources, `+`, `~` or `-/+`. Then compare with the real output. This is how you train reading plans.

---

## Step 0. Bring up the infrastructure

To see how code changes affect resources, the resources have to exist.

```
terraform init
terraform plan
terraform apply
```

> ❓ **1.** How many resources did `apply` create? Find all of them in the output of `terraform state list`.

## Step 1. The lock file in git

Open `.gitignore` and delete the `.terraform.lock.hcl` line. Then look at what's inside the file:

```
cat .terraform.lock.hcl
git status
```

> ❓ **2.** Which `azurerm` version is pinned? What do the `h1:` and `zh:` lines mean?
>
> ❓ **3.** What happens in CI if the lock file isn't in the repo, and HashiCorp releases a new provider version within `~> 3.0`?

A lock file created on a Mac may not contain all the hashes for Linux, where CI runs. Add them explicitly:

```
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64
```

## Step 2. Validated variables

Create two variables in `variables.tf`:

- `location`, of type `string`, with the default `"swedencentral"` and a `validation` that allows only `swedencentral` and `northeurope`;
- `vm_size`, of type `string`, with the default `"Standard_B2ls_v2"`.

Use them to replace the hard-coded values: `location` in the resource group (`network.tf`) and `size` in the VM (`compute.tf`). The other resources already take the region from `azurerm_resource_group.rg.location`, so leave them alone.

```
terraform plan
```

> ❓ **4.** What did `plan` show, and why?

Test the `validation`:

```
terraform plan -var="location=mars"
```

> ❓ **5.** What error did you get? Did Terraform get as far as calling Azure?

## Step 3. Where a variable's value comes from

Try these one at a time, and each time look only at the `Plan:` line and at the marker next to the resource group:

```
TF_VAR_location=northeurope terraform plan
TF_VAR_location=northeurope terraform plan -var="location=swedencentral"
```

> ❓ **6.** Which value won in the second command, and why?
>
> ❓ **7.** In the first command, the resource group is marked `-/+`. Why does changing the region require recreation? What happens to the other resources?

**Don't run `apply` with `northeurope`.**

## Step 4. Common tags through `locals`

Create `locals.tf`:

```hcl
locals {
  tags = {
    project = "azure-demo"
    env     = "dev"
    owner   = "slavikator"
  }
}
```

Add `tags = local.tags` to every resource that supports tags. Check the resource's documentation on registry.terraform.io if you're not sure.

> ❓ **8.** Which resources in your project **don't** support tags, and why?

```
terraform plan
```

> ❓ **9.** How many resources will change, and with which marker: `~` or `-/+`? Why don't tags require recreation?

```
terraform apply
az group show -n rg-devops-demo-swe --query tags
```

## Step 5. `data` and `output`

Add to the code:

```hcl
data "azurerm_client_config" "current" {}
```

And in any file (better: create `outputs.tf` and move `vm_public_ip` there), add two outputs: `subscription_id` and `tenant_id` from this data source.

```
terraform plan
terraform apply
terraform output
terraform output -raw subscription_id
```

> ❓ **10.** How does `data "azurerm_client_config"` differ from a `resource`? Does it create anything in Azure?
>
> ❓ **11.** Who did Terraform sign in as, i.e. whose `client_id` will this data source return locally, and whose in CI?

## Step 6. The dependency graph

```
terraform graph > graph.dot
```

Paste the contents of `graph.dot` into any online Graphviz renderer (for example, search for "graphviz online"), or install it locally: `brew install graphviz`, then `dot -Tsvg graph.dot > graph.svg`, and open `graph.svg`.

> ❓ **12.** Find the chain from the resource group to the VM. Which resources does it pass through?
>
> ❓ **13.** Which resources don't depend on each other, and are therefore created in parallel?

Don't add `graph.dot` and `graph.svg` to git.

## Step 7. Check and push

```
terraform fmt -recursive
terraform validate
terraform plan
```

The last `plan` must show `No changes`. Commit everything: code changes, `.gitignore` and `.terraform.lock.hcl`.

```
git add -A && git commit -m "refactor: variables, tags, outputs, lock file" && git push
```

Open the log of the **Terraform Plan** step in GitHub Actions.

> ❓ **14.** What did `plan` show in CI, and why exactly that? Note: CI uses the same variables with their default values, and `ssh_public_key` from a secret.

## Step 8. Cleanup

```
terraform destroy
az group exists -n rg-devops-demo-swe
```

---

## Outcome

After the practice you should be able to explain, without looking:

- why you commit the lock file;
- how `validation` works and when it runs;
- in what order Terraform takes variable values;
- the difference between `~` and `-/+` in a plan, and what causes it;
- the difference between `resource` and `data`;
- how Terraform determines the order in which resources are created.

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
13.
14.
