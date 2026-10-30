# Week 7 practice: "From one VM to a fleet"

**Goal:** replace the single-VM idea with a scale set behind a Load Balancer, see load balancing, health probes and autoscaling work, deploy the same kind of app to App Service with no VM at all, add monitoring and an alert, and compare the costs.

**Topics:** VMSS, Load Balancer, health probes, autoscale, App Service with a container from Docker Hub, Log Analytics, diagnostic settings, metric alerts, cost comparison.

**Time:** 2.5–3 hours, best split into two sessions. **Cost:** about $0.15 per hour at the peak (two VMSS instances, a Load Balancer, an App Service plan B1). There's a `destroy` at the end.

**Notes:** [`07-compute-paas.md`](07-compute-paas.md)

---

## Rules for this practice

1. **Guess first, then check.** Before every `plan`, write down what it will show.
2. **Everything lives in a separate lab folder, `labs/compute/`,** with its own state. Your main project isn't touched.
3. **Mind the trial quotas:** 4 vCPUs and 3 public IPs per region. Two `Standard_B2ls_v2` instances already use all 4 vCPUs, so **your main environment's VM must be destroyed first**. Deallocating isn't enough: deallocated VMs still count.
4. **Prove everything with a command**: `curl`, `az`, the Portal's metrics.

---

## Step 0. Preparation

1. Destroy your main environment (the repo root, or `envs/dev` if you've done practice 06), and check the quotas:

   ```
   az vm list-usage -l swedencentral --query "[?name.value=='cores'].{current:currentValue, limit:limit}" -o table
   az network list-usages -l swedencentral --query "[?name.value=='PublicIPAddresses'].{current:currentValue, limit:limit}" -o table
   ```

   You need 4 free cores and at least 1 free public IP.

2. Create `labs/compute/` with:
   - `providers.tf`: a copy of your current one, with a **new backend key**, `lab-compute.terraform.tfstate`;
   - `variables.tf` with `ssh_public_key` (no default);
   - a copy of `terraform.tfvars` and `.terraform.lock.hcl`;
   - a resource group `rg-lab-compute-swe`, a VNet `10.20.0.0/16` and one subnet.

   ```
   cd labs/compute
   terraform init
   terraform plan
   ```

> ❓ **1.** Why a new backend key? What would happen if this folder used the same key as your main project?

---

## Step 1. A scale set behind a Load Balancer

Create these resources (look up each one's arguments in the azurerm 3.117.1 docs, as in week 4):

| Resource | Key settings |
|---|---|
| `azurerm_public_ip` | Standard, Static: the Load Balancer's frontend |
| `azurerm_lb` | Standard SKU, a `frontend_ip_configuration` using that IP |
| `azurerm_lb_backend_address_pool` | the pool the instances join |
| `azurerm_lb_probe` | `Http`, port 80, path `/` |
| `azurerm_lb_rule` | TCP 80 → 80, with the pool and the probe |
| `azurerm_network_security_group` | allow TCP 80 from `Internet`. No SSH rule |
| `azurerm_linux_virtual_machine_scale_set` | `Standard_B2ls_v2`, `instances = 2`, `upgrade_mode = "Manual"`, no public IPs on instances, the NSG on its `network_interface`, and the pool in `load_balancer_backend_address_pool_ids` |

**The app:** each instance must show **its own hostname**, so you can see the load balancing. Ubuntu already has Python, so cloud-init needs no downloads. A `custom_data` that works:

```hcl
custom_data = base64encode(<<-EOF
  #cloud-config
  runcmd:
    - mkdir -p /srv/www
    - echo "Hello from $(hostname)" > /srv/www/index.html
    - nohup python3 -m http.server 80 --directory /srv/www > /dev/null 2>&1 &
EOF
)
```

**Predict** how many resources `plan` will add, then `apply`. Then call the Load Balancer several times:

```
LB_IP=$(az network public-ip show -g rg-lab-compute-swe -n <your LB IP name> --query ipAddress -o tsv)
for i in $(seq 1 10); do curl -s http://$LB_IP; done
```

> ❓ **2.** Did you get answers from both instances? The instances have no public IPs: how does your request reach them?
>
> ❓ **3.** Why must the NSG allow port 80 even though the Load Balancer is in front? Which NSG rule lets the health probe in?

---

## Step 2. Health probe in action

Stop the web server on one instance, without SSH, through the VM agent:

```
az vmss list-instances -g rg-lab-compute-swe -n <your vmss name> --query "[].{id:instanceId, name:osProfile.computerName}" -o table
az vmss run-command invoke -g rg-lab-compute-swe -n <your vmss name> --instance-id <id> --command-id RunShellScript --scripts "pkill -f http.server"
```

Wait about 30 seconds, then repeat the `curl` loop.

> ❓ **4.** What did the `curl` loop return now, and why? What would happen if the probe pointed at a port nothing listens on?

Start the server again on that instance with `run-command` (the same `nohup python3 ...` line), and check that both hostnames come back.

---

## Step 3. Autoscaling

Change the scale set to start with **one** instance, and add an autoscale setting:

- `azurerm_monitor_autoscale_setting` targeting the scale set, with `minimum = 1`, `default = 1`, `maximum = 2` (the quota limit);
- a scale-out rule: average `Percentage CPU` > 60% over 5 minutes → +1, cooldown 5 minutes;
- a scale-in rule: average `Percentage CPU` < 20% over 5 minutes → −1;
- on the scale set: `lifecycle { ignore_changes = [instances] }`.

**Predict** the plan, apply, then generate CPU load on the single instance (2 vCPUs, so two busy loops):

```
az vmss run-command invoke -g rg-lab-compute-swe -n <your vmss name> --instance-id <id> --command-id RunShellScript --scripts "nohup sh -c 'yes > /dev/null' & nohup sh -c 'yes > /dev/null' &"
```

Watch the instance count for 10–15 minutes:

```
az vmss list-instances -g rg-lab-compute-swe -n <your vmss name> -o table
```

Then stop the load (`pkill yes`) and watch it scale in.

> ❓ **5.** How long did it take from the load starting to the second instance serving traffic? What were the delays made of?
>
> ❓ **6.** Why is `ignore_changes = [instances]` needed? What would the next `plan` show without it?
>
> ❓ **7.** Why are the scale-out and scale-in thresholds far apart (60% and 20%)?

---

## Step 4. The same kind of app on App Service

Now run a web app with **no VM at all**. Add:

- `azurerm_service_plan`: Linux, `sku_name = "B1"`;
- `azurerm_linux_web_app` running a public Docker Hub image that shows its hostname: in `site_config.application_stack`, `docker_image_name = "nginxdemos/hello:latest"` and `docker_registry_url = "https://index.docker.io"`.

**Predict**, then apply, and open the app's default hostname (`https://<name>.azurewebsites.net`). The first start pulls the image, so give it a minute.

> ❓ **8.** Compare this step with Step 1: what did you have to configure for the VMSS that you didn't for App Service? What do you still manage here, and what does Microsoft?
>
> ❓ **9.** You pulled `latest`. Why is that a bad idea in production, and what would you use instead?

---

## Step 5. Monitoring and an alert

Add:

- `azurerm_log_analytics_workspace` (`PerGB2018`, 30 days);
- `azurerm_monitor_diagnostic_setting` on the web app, sending the `AppServiceHTTPLogs` category to the workspace;
- `azurerm_monitor_action_group` with an email receiver (your address);
- `azurerm_monitor_metric_alert` on the scale set: average `Percentage CPU` > 80% → the action group.

Apply, open the web app a few times, then in the Portal: Log Analytics workspace → **Logs**, and run:

```kusto
AppServiceHTTPLogs
| project TimeGenerated, CsMethod, CsUriStem, ScStatus, TimeTaken
| order by TimeGenerated desc
```

Logs can take 5–10 minutes to appear. Trigger the CPU load from Step 3 again and wait for the alert email.

> ❓ **10.** What's the difference between the autoscale rule and the metric alert, even though both watch CPU?

---

## Step 6. Compare the costs

In the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/), price these for a month in Sweden Central, and write the numbers in your notes:

1. one VM `Standard_B2ls_v2` with a Standard SSD and a public IP (your original project);
2. a scale set of 2 × `Standard_B2ls_v2` plus a Standard Load Balancer;
3. App Service plan B1;
4. Container Apps on the Consumption plan, for a small app with modest traffic.

> ❓ **11.** Which is cheapest, and which would you choose for the Express app? Justify it with cost, scaling and how much you manage.

---

## Step 7 (optional). Container Apps and scale to zero

Only if `az containerapp env list -o table` shows **no** environment: a trial allows one, and `swedencentral` sometimes lacks capacity (try `northeurope`).

Create a `azurerm_container_app_environment` and a `azurerm_container_app` running `nginxdemos/hello:latest` with external ingress on port 80, `min_replicas = 0`, `max_replicas = 2`. Open it, then wait about 10 minutes without traffic and check:

```
az containerapp replica list -g rg-lab-compute-swe -n <your app name> -o table
```

> ❓ **12.** How many replicas were running after the idle period? What did you notice on the first request afterwards, and why?

---

## Step 8. Cleanup

```
cd ~/azure/demo/labs/compute
terraform destroy
az group exists -n rg-lab-compute-swe
```

Decide whether to keep `labs/compute/` in git (as a record of the lab) or delete it. Either way, `terraform.tfvars` must not be committed (it's ignored), and `git status` should be clean.

---

## Outcome

After this practice you should be able to, without looking:

- build a VMSS behind a Load Balancer and explain the path of a request;
- explain how health probes take broken instances out of rotation;
- configure autoscaling, and explain its delays and the Terraform interaction;
- deploy a container to App Service and explain what you no longer manage;
- send logs to Log Analytics, query them, and alert on a metric;
- compare the cost of VM, VMSS, App Service and Container Apps for one app.

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
