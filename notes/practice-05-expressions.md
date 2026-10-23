# Week 5 practice: "No copy-paste"

**Goal:** see with your own eyes why `count` is dangerous for lists, fix it with `for_each` without recreating anything, generate NSG rules from a variable, create several VMs from one block, and protect resources with `lifecycle` and conditions.

**Topics:** `terraform console`, `count`, `for_each`, `moved`, `dynamic`, `for` expressions, `lifecycle`, `precondition`.

**Time:** 2 hours, can be split into two sessions. **Cost:** about $0.15 per hour at the peak (three VMs in Step 4). There's a `destroy` at the end.

**Notes:** [`05-expressions-meta-arguments.md`](05-expressions-meta-arguments.md)

---

## Rules for this practice

1. **Guess first, then check.** Before every `plan`, write down: how many `+`, `~`, `-/+`, `-`, and which addresses.
2. **Experiments live in their own files** (`count-demo.tf`, `vms.tf`) and get deleted. **Steps 3 and 5b are real improvements** and get committed.
3. **A refactor must end with `No changes`.** If the plan shows changes after a pure refactor, something in the new code differs from the old.

---

## Step 0. Preparation

```
cd ~/azure/demo
terraform apply
terraform plan
```

The last `plan` must show `No changes`.

---

## Step 1. Warm-up in the console

Open `terraform console` and type these **one at a time** (pasting several lines at once shows only the last result). **Predict each result before pressing Enter.**

```
[for s in ["web","api","db"] : upper(s)]
{ for s in ["web","api","db"] : s => length(s) }
[for s in ["web","api","db"] : s if s != "api"]
merge(local.tags, { role = "web" })
toset(["a","b","a"])
{ for i, n in ["app","mgmt"] : n => cidrsubnet("10.0.0.0/16", 8, i + 1) }
lookup({ dev = "Standard_B1s", prod = "Standard_D2s_v5" }, "test", "Standard_B2ls_v2")
```

Leave with `exit`.

> ❓ **1.** Which expressions returned a list, and which a map? What decides it?
>
> ❓ **2.** What did `toset(["a","b","a"])` do to the duplicate, and why does that matter for `for_each`?

---

## Step 2. The `count` trap, and the fix

This step is an experiment in a new file, `count-demo.tf`. It uses NSGs: they're free, created in seconds, and have no tight quota. (Public IPs would also work, but a trial subscription allows only 3 per region, and your VM already uses one.)

**Part A: create three NSGs with `count`.**

```hcl
locals {
  nsg_names = ["a", "b", "c"]
}

resource "azurerm_network_security_group" "demo" {
  count               = length(local.nsg_names)
  name                = "nsg-demo-${local.nsg_names[count.index]}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}
```

Apply it, then list the addresses and each NSG's `resourceGuid`. Azure assigns a new GUID whenever a resource is created, so it proves whether something was recreated:

```
terraform apply
terraform state list | grep demo
az network nsg list -g rg-devops-demo-swe --query "[?starts_with(name,'nsg-demo-')].{name:name, guid:resourceGuid}" -o table
```

**Part B: remove `"a"`.** Change the list to `["b", "c"]`. **Predict** the plan: which addresses get which symbol, and what will the `Plan:` line say? Then:

```
terraform plan
```

**Don't apply.**

> ❓ **3.** What did the plan show for `demo[0]`, `demo[1]` and `demo[2]`? You wanted to delete one NSG. What would actually happen to `nsg-demo-b` and `nsg-demo-c`?

**Part C: switch to `for_each` without recreating anything.**

1. Put `"a"` back: `["a", "b", "c"]`.
2. Replace `count = ...` with `for_each = toset(local.nsg_names)`, and build the name from `each.key`.
3. Add three `moved` blocks, from `azurerm_network_security_group.demo[0]` to `azurerm_network_security_group.demo["a"]`, and so on.

**Predict**, then check:

```
terraform plan
```

The plan must show three `has moved to` lines and `0 to add, 0 to change, 0 to destroy`. Apply it.

> ❓ **4.** Why did nothing get recreated, even though every address changed? What would the plan have shown without the `moved` blocks?

**Part D: remove `"a"` again.** Change the list to `["b", "c"]`, predict, then `plan` and `apply`. Compare the GUIDs of `nsg-demo-b` and `nsg-demo-c` with Part A.

> ❓ **5.** What did the plan show this time? Did the remaining NSGs keep their GUIDs?

**Cleanup:** delete `count-demo.tf` (the `moved` blocks go with it), then `plan` (predict!) and `apply`.

---

## Step 3. NSG rules from a variable with `dynamic`

Right now `security.tf` has two hand-written `security_rule` blocks. Move them into a variable.

**Change the code:**

- add a variable `nsg_rules` to `variables.tf`, of type `map(object({ priority = number, port = string }))`, with a default that describes your two current rules. Use the **rule names** as map keys;
- in `azurerm_network_security_group.nsg`, replace both `security_rule` blocks with one `dynamic "security_rule"` block that generates them from `var.nsg_rules`. Everything that's the same for both rules (direction, access, protocol, source, destination) stays fixed in `content`.

<details>
<summary>Hint: the map keys</summary>

The names of your current rules are `SSH` and `HTTP`, uppercase. If your keys are `ssh` and `http`, the plan will show the rules as changed. That's the point of question 6.

</details>

**Predict**, then check:

```
terraform plan
```

> ❓ **6.** What did `plan` show? Why is `No changes` the only acceptable result of this step?

**Now use it.** Add a third rule to the map's default: `HTTPS`, priority `1003`, port `443`. **Predict**, then `plan`.

> ❓ **7.** Which resource changes, and with which symbol? How many lines of code did it take to add a rule, compared with before?

Remove `HTTPS` again (the app doesn't serve HTTPS), check that `plan` shows `No changes`, then commit and push. Check that the CI `plan` shows `No changes`.

---

## Step 4. Several VMs from one block with `for_each`

This step is an experiment in a new file, `vms.tf`. The VMs go into `snet-mgmt`, the subnet you created in week 4.

**Write `vms.tf`:**

- a `locals` block with `lab_vms = { web = "Standard_B2ls_v2", api = "Standard_B2ls_v2" }` (name → size);
- `azurerm_network_interface.lab` with `for_each = local.lab_vms`, named `nic-lab-<key>`, in `azurerm_subnet.mgmt`, without a public IP;
- `azurerm_linux_virtual_machine.lab` with `for_each = local.lab_vms`, named `vm-lab-<key>`, using `each.value` as the size and the **matching** NIC. Copy the rest from `compute.tf` without `custom_data`. Include a `lifecycle` that ignores `vm_agent_platform_updates_enabled` (you saw why in week 4);
- an output `lab_private_ips`: a **map** of VM name → private IP, built with a `for` expression over `azurerm_network_interface.lab`.

<details>
<summary>Hint: the matching NIC</summary>

Inside the VM block, `each.key` is `web` or `api`. The NIC for the same key is `azurerm_network_interface.lab[each.key]`.

</details>

**Predict** how many resources `plan` will add, then apply and look at the output:

```
terraform apply
terraform output lab_private_ips
```

> ❓ **8.** What addresses did the two VMs get, and why do they start with `10.0.2.`? Why couldn't you write `[*]` after `azurerm_network_interface.lab`?

**Remove one VM.** Delete `api` from the map. **Predict**, then `plan`.

> ❓ **9.** What will be destroyed? Which resources are untouched, and why is that guaranteed with `for_each`?

Apply it, then delete `vms.tf` entirely, `plan` (predict!) and `apply`.

---

## Step 5. `lifecycle` and conditions

**Part A: `prevent_destroy` (experiment).** Add to `azurerm_resource_group.rg`:

```hcl
lifecycle {
  prevent_destroy = true
}
```

Then try to plan a destroy:

```
terraform plan -destroy
```

> ❓ **10.** What happened? Now think it through without trying it: if someone deleted the **whole** `azurerm_resource_group.rg` block from the code, would `prevent_destroy` still stop the deletion? What would actually protect the RG?

Remove the `lifecycle` block from the RG again, and check that `plan` shows `No changes`.

**Part B: a `precondition` (keep it).** In the main VM's `lifecycle` block in `compute.tf`, add a `precondition` that allows only burstable B-series sizes: `startswith(var.vm_size, "Standard_B")`, with a clear `error_message`. Then test it:

```
terraform plan
terraform plan -var="vm_size=Standard_D2s_v5"
```

> ❓ **11.** What did each command show? How is this `precondition` different from putting the same check in a `validation` block on `var.vm_size`?

Commit and push. Check that the CI `plan` shows `No changes`.

---

## Step 6. Cleanup

```
terraform plan          # should be No changes
terraform destroy
az group exists -n rg-devops-demo-swe
git status              # should be clean: Steps 3 and 5B committed, no count-demo.tf or vms.tf
```

> ❓ **12.** Look back at your code: where else are you still repeating yourself? Name one place where `for_each` or `dynamic` would help, and one place where it would make the code worse.

---

## Outcome

After this practice you should be able to, without looking:

- explain, with an example, why `count` over a list causes recreations;
- migrate `count` to `for_each` with `moved` and no recreation;
- generate nested blocks with `dynamic` and prove the refactor with `No changes`;
- create several resources from a map, link matching copies, and output a map with a `for` expression;
- explain what `prevent_destroy` protects and what it doesn't;
- choose between `validation` and `precondition`.

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
