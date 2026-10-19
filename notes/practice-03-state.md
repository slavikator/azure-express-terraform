# Week 3 practice: "When code, state and Azure disagree"

**Goal:** deliberately break the sync between code, state and Azure in four different ways, and each time find and fix the problem yourself. This is the final check for week 3: all previous topics come together here.

**Topics:** import, drift, refresh, `removed`, lock, interrupted `apply`.

**Time:** 1–1.5 hours. **Cost:** about $0.05 per hour while the VM is running. There's a `destroy` at the end.

**Notes:** [`03-terraform-state.md`](03-terraform-state.md), section 9.

---

## Rules for this practice

1. **Guess first, then check.** Before every `plan`, write down what it will show: `+`, `~`, `-/+`, `-`, and how many resources.
2. **Always diagnose in the same order:**
   ```
   terraform plan -refresh-only     # what changed in Azure compared to the state
   terraform plan                   # what Terraform wants to do about it
   terraform state list             # what's in the state
   az ...                           # what actually exists in Azure
   ```
3. **Don't push code to git in the middle of a scenario.** On push, CI only runs `fmt` and `plan`, but code and state are temporarily out of sync, so the CI plan will look strange.
4. Hints are hidden under "Hint". Try without them first.

The table you need to fill in at the end:

| Code | State | Azure | What `plan` shows |
|---|---|---|---|
| ✅ | ❌ | ✅ | ? |
| ✅ | ✅ | ❌ | ? |
| ✅ | ✅ | ✅, but a different value | ? |
| ❌ | ✅ | ✅ | ? |

---

## Step 0. Preparation

```
cd ~/azure/demo
terraform apply
terraform plan
```

The last `plan` must show `No changes`. Start the scenarios only from this point.

> ❓ **1.** Why is it important to start from `No changes`? What goes wrong if the plan already has some changes before a scenario?

---

## Scenario 1. A resource was created by hand

**Situation:** a colleague created an NSG in the portal "just for a minute" and forgot about it. Now it needs to be brought under Terraform management.

**Break it:**

```
az network nsg create -g rg-devops-demo-swe -n nsg-manual -l swedencentral
```

**Predict**, then check:

```
terraform plan
```

> ❓ **2.** What did `plan` show, and why exactly that? Which row of the table above is this situation?

**Fix it:** bring `nsg-manual` under Terraform management so that `plan` ends with `No changes`. In the code, name the resource `azurerm_network_security_group.manual`.

<details>
<summary>Hint</summary>

- Resource ID: `az network nsg show -g rg-devops-demo-swe -n nsg-manual --query id -o tsv`
- An `import {}` block in a separate file, plus `terraform plan -generate-config-out=generated.tf` (topic 5).
- Check that the generated code has nothing extra, and that `plan` shows `1 to import, 0 to change`.

</details>

> ❓ **3.** What did `plan` show before `apply`: how many `to import`, `to change`? If there were changes, where did they come from?

**Clean up:** `nsg-manual` is no longer needed, either in code or in Azure. Do it with a single `apply`.

> ❓ **4.** What did you do to delete `nsg-manual` from both Azure and the state? What would have happened if you had used `terraform state rm` instead?

---

## Scenario 2. A resource was deleted by hand

**Situation:** someone in the portal detached the NSG from the subnet because it "was in the way". The association is still in the state.

**Break it:**

```
az network vnet subnet update -g rg-devops-demo-swe --vnet-name vnet-demo -n snet-internal --remove networkSecurityGroup
```

**Predict**, then check:

```
terraform plan -refresh-only
terraform plan
```

> ❓ **5.** What did `-refresh-only` show about `azurerm_subnet_network_security_group_association.subnet_assoc`? And the normal `plan`?

**Fix it:** restore the association and bring `plan` back to `No changes`.

> ❓ **6.** Imagine the association really isn't needed anymore. What's the right way to remove it so Terraform doesn't try to create it again?

---

## Scenario 3. An attribute was changed by hand

**Situation:** an admin restricted SSH to a single IP address directly in the portal, because "it's more secure".

**Break it:**

```
az network nsg rule update -g rg-devops-demo-swe --nsg-name nsg-demo -n SSH --source-address-prefixes 203.0.113.10
```

**Predict**, then check:

```
terraform plan -refresh-only
terraform plan
```

> ❓ **7.** What does `plan` want to do with the SSH rule? Why is it `~` and not `-/+`?

**Decide for yourself** who's right, and fix it accordingly:

- **the code is right** → revert it to how it was;
- **the manual change is right** → move the change into the code.

Either way, `plan` must end with `No changes`, and the SSH rule must still let you log in to the VM.

> ❓ **8.** What did you choose, and how exactly did you fix it? Why isn't `apply -refresh-only` the solution here?

---

## Scenario 4. `apply` was interrupted halfway

**Situation:** your laptop died during `apply`. We simulate this with a double Ctrl+C.

**Break it:**

```
terraform apply -replace=azurerm_linux_virtual_machine.vm
```

Type `yes`. Wait for the line `azurerm_linux_virtual_machine.vm: Creating...` and **quickly press Ctrl+C twice**.

Write down what Terraform printed after the two Ctrl+C presses.

**Diagnose.** Answer each question with a command, not a guess:

- Is the state locked?
- Is the VM in the state?
- Does the VM exist in Azure? What state is it in?

<details>
<summary>Hint: commands</summary>

```
terraform plan
terraform state list | grep vm
az vm show -g rg-devops-demo-swe -n vm-demo-node --query provisioningState -o tsv
```

The lock is also visible in the portal: container `tfstate`, column **Lease state**.

</details>

> ❓ **9.** What did the diagnosis show: lock, state, Azure? Which row of the table are you in?

**Fix it:** bring `plan` back to `No changes`, with the VM running. The outcome depends on exactly when you pressed Ctrl+C, so there's no ready-made recipe.

<details>
<summary>Hint: possible outcomes</summary>

- The state is locked → `terraform force-unlock <ID>`, but only once you're sure no other `apply` is running.
- The VM exists in Azure but not in the state → `plan` will want to create it, and `apply` will fail with `already exists`. You already know what to do from scenario 1.
- The VM exists in Azure in a `Failed` state → it's easier to delete it (`az vm delete`) and let Terraform create it again.
- The VM is in both the state and Azure → everything may be fine, and `plan` will show `No changes`.

</details>

> ❓ **10.** What did you do to fix it, and in what order? Why wouldn't this have happened with a single Ctrl+C?

---

## Step 5. Cleanup

```
terraform plan          # should be No changes
terraform destroy
az group exists -n rg-devops-demo-swe
git status              # should be clean: no import.tf, no generated.tf
```

Also make sure `nsg-manual` isn't left behind in Azure:

```
az network nsg list -o table
```

---

## Outcome

After this practice you should be able to, without looking:

- fill in the "code / state / Azure / what plan shows" table;
- tell real drift apart from computed-attribute noise;
- bring a resource created by hand under Terraform management;
- remove a resource from Terraform management without deleting it in Azure;
- recover from an interrupted `apply` and a stuck lock.

## My answers

Table:

| Code | State | Azure | What `plan` shows |
|---|---|---|---|
| ✅ | ❌ | ✅ | |
| ✅ | ✅ | ❌ | |
| ✅ | ✅ | ✅, but a different value | |
| ❌ | ✅ | ✅ | |

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
