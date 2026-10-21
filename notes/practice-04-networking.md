# Week 4 practice: "Closing the doors"

**Goal:** turn the project's flat, wide-open network into something you can defend in an interview: SSH only from your IP, subnets calculated with `cidrsubnet`, a second VNet connected through peering, and the ability to explain what a packet passes through.

**Topics:** CIDR, reserved addresses, NSG rules, NSG on subnet and NIC, `cidrsubnet`, VNet peering, effective routes and effective NSG rules.

**Time:** 1.5–2 hours, can be split into two sessions. **Cost:** about $0.10 per hour while both VMs are running. There's a `destroy` at the end.

**Notes:** [`04-azure-networking.md`](04-azure-networking.md)

---

## Rules for this practice

1. **Guess first, then check.** Before every `plan`, write down what it will show: `+`, `~`, `-/+`, and how many resources.
2. **Prove connectivity with a command.** "It should work" isn't an answer; `ping`, `ssh` or `az ... effective-...` output is.
3. **Steps 2 and 3 are real improvements and get committed. Step 4 is an experiment and gets deleted.**

---

## Step 0. Preparation

```
cd ~/azure/demo
terraform apply
terraform plan
```

The last `plan` must show `No changes`.

---

## Step 1. Counting addresses

Use `terraform console` as a calculator. It knows the same functions as your `.tf` files:

```
terraform console
> cidrsubnet("10.0.0.0/16", 8, 1)
> cidrsubnet("10.0.0.0/16", 8, 2)
> cidrhost("10.0.1.0/24", 4)
> pow(2, 32 - 28)
> exit
```

Then check which private IP Azure gave your VM:

```
az network nic show -g rg-devops-demo-swe -n nic-demo-vm --query "ipConfigurations[0].privateIPAddress" -o tsv
```

> ❓ **1.** How many usable addresses does Azure give you in a `/28`, and why not 16?
>
> ❓ **2.** Why does the VM have `.4` at the end of its private IP, and not `.1`?

---

## Step 2. SSH only from your IP

Right now the `SSH` rule in `security.tf` has `source_address_prefix = "*"`: the whole internet can try to log in.

Find your public IPv4 address:

```
curl -4 -s https://ifconfig.me
```

**Change the code:**

- add a variable `admin_source_ip` to `variables.tf`: type `string`, **no default**, and a `validation` that checks it's a valid CIDR (`can(cidrhost(var.admin_source_ip, 0))`);
- put your value in `terraform.tfvars` as `"<your IP>/32"`;
- use `var.admin_source_ip` as the `source_address_prefix` of the `SSH` rule only. `HTTP` stays open to `*`: it's a public web app.

<details>
<summary>Hint: why no default</summary>

A default like `"*"` would silently reopen SSH to everyone whenever someone forgets to set the value. Without a default, forgetting it is an error.

</details>

**Predict**, then check:

```
terraform plan
```

> ❓ **3.** What did `plan` show: which symbol, how many resources? Why isn't it `-/+`?

Apply it and check that SSH still works for you:

```
terraform apply
ssh -i ~/.ssh/id_rsa_azure azureuser@$(terraform output -raw vm_public_ip) hostname
```

`-i` points to the private key that matches `ssh_public_key` in `terraform.tfvars`. Without it, `ssh` tries your default keys and fails with `Permission denied (publickey)`. To check which local key matches: compare `ssh-keygen -lf ~/.ssh/<key>.pub` with the key in `terraform.tfvars`.

**Before you push,** CI needs the value too. The variable has no default, so without it `plan` in CI fails.

```
gh secret set ADMIN_SOURCE_IP --body "<your IP>/32"
```

Then add one line to the `env:` block of `.github/workflows/deploy.yml`, next to `TF_VAR_ssh_public_key`. Work out yourself what the line should be.

> ❓ **4.** What would the CI `plan` have done if you had pushed without the secret? Why does the variable name in the workflow have to start with `TF_VAR_`?

Commit and push, then check that the CI `plan` shows `No changes`.

---

## Step 3. Subnets with `cidrsubnet`

Right now `address_prefixes = ["10.0.1.0/24"]` is typed by hand. Calculate it from the VNet's address space instead, and add a second subnet for management.

**Change the code in `network.tf`:**

- in `azurerm_subnet.main`, replace the literal with `cidrsubnet(azurerm_virtual_network.main.address_space[0], 8, 1)`. Don't change its `name`;
- add `azurerm_subnet.mgmt` with the name `snet-mgmt` and `cidrsubnet(..., 8, 2)`.

**Predict**, then check:

```
terraform plan
```

> ❓ **5.** How many resources does `plan` add or change? Why didn't replacing the literal in `azurerm_subnet.main` cause any change?
>
> ❓ **6.** Why must you not change the `name` of `azurerm_subnet.main` to `snet-app`? What would `plan` show, and why would `apply` fail?

Apply, then commit and push. Check that the CI `plan` shows `No changes`.

---

## Step 4. A second VNet and peering

This step is an experiment: create everything in a new file `peering.tf`, and delete the file at the end.

**Part A: the second network.** In `peering.tf`, create:

- a VNet `vnet-peer` with the address space `10.1.0.0/16`;
- a subnet `snet-peer`, `10.1.1.0/24`;
- a NIC `nic-peer-vm` **without** a public IP;
- a Linux VM `vm-peer` in that subnet. Copy the main VM's block from `compute.tf`, but without `custom_data`, and with its own name and NIC.

**Part B: one-way peering.** Add **only one** peering, from `vnet-demo` to `vnet-peer` (`azurerm_virtual_network_peering`).

**Predict** how many resources `plan` will add, then apply. Check:

```
az network vnet peering list -g rg-devops-demo-swe --vnet-name vnet-demo --query "[].{name:name, state:peeringState}" -o table
```

From your Mac, run `ping` on the main VM through SSH, aimed at the second VM's private IP:

```
ssh -i ~/.ssh/id_rsa_azure azureuser@$(terraform output -raw vm_public_ip) ping -c 3 10.1.1.4
```

The command after the address runs **on the VM**, not on your Mac, and `ssh` returns when it finishes. `10.1.1.4` is a private IP, so your Mac can't reach it directly; only something inside Azure can.

> ❓ **7.** What's the peering state, and did `ping` work? Why?

**Part C: the second direction.** Add the peering from `vnet-peer` back to `vnet-demo`, apply, and repeat both checks.

> ❓ **8.** What changed in the state and in `ping`? Why does peering need two resources?

**Part D: what the NIC sees.**

```
az network nic show-effective-route-table -g rg-devops-demo-swe -n nic-demo-vm -o table
```

> ❓ **9.** Find the route for `10.1.0.0/16`. What's its next hop type? Now imagine a third VNet, `10.2.0.0/16`, peered only with `vnet-peer`. Could `vm-demo-node` reach it? Why not, and how do real networks solve this?

---

## Step 5. Which NSG rules actually apply

```
az network nic list-effective-nsg -g rg-devops-demo-swe -n nic-demo-vm
```

The output is long. Look for the `association` blocks and the SSH rule's source.

> ❓ **10.** Your NSG is attached to both the subnet and the NIC. In what order is it checked for **inbound** traffic, and when does a packet get through? Trace the path of your SSH connection from your laptop to `vm-demo-node`.

---

## Step 6. Cleanup

Step 4 was an experiment. Remove it before destroying, so `git status` is clean:

```
rm peering.tf
terraform plan          # predict: what will it destroy?
terraform destroy
az group exists -n rg-devops-demo-swe
git status              # should be clean: Steps 2 and 3 committed, peering.tf gone
```

---

## Outcome

After this practice you should be able to, without looking:

- count usable addresses in any subnet and explain the 5 reserved ones;
- explain how NSGs on a subnet and a NIC combine;
- restrict access by IP without hard-coding it, locally and in CI;
- calculate subnets with `cidrsubnet`;
- set up peering and explain why it's two-way and non-transitive;
- prove connectivity with `ping`, effective routes and effective NSG rules.

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
