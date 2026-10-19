# Week 7. Compute and PaaS

The main services for running applications, and how to choose the right one.

## Terms

| Abbreviation / term | Stands for | What it is, in one sentence |
|---|---|---|
| **IaaS** | Infrastructure as a Service | You manage the OS and everything above it. Example: a VM |
| **PaaS** | Platform as a Service | Azure manages the OS; you provide code or a container. Example: App Service |
| **SaaS** | Software as a Service | A finished product. Example: Microsoft 365 |
| **VM** | Virtual Machine | A virtual machine |
| **VMSS** | Virtual Machine Scale Set | A group of identical VMs with autoscaling |
| **ASP** | App Service Plan | The "hardware" behind App Service: size and number of instances |
| **ACR** | Azure Container Registry | A private registry for Docker images |
| **ACA** | Azure Container Apps | Containers without managing Kubernetes, scaling to zero |
| **AKS** | Azure Kubernetes Service | Managed Kubernetes |
| **LRS / ZRS / GRS** | Locally / Zone / Geo-Redundant Storage | Data replication options in Storage |
| **SLA** | Service Level Agreement | A guaranteed availability percentage |

## Concepts you need to explain in your own words

### 1. Shared responsibility

```
              On-prem   IaaS (VM)   PaaS (App Service)   SaaS
Application     you        you           you              Microsoft
Runtime         you        you           Microsoft        Microsoft
OS              you        you           Microsoft        Microsoft
Hardware        you      Microsoft       Microsoft        Microsoft
```

The higher up the stack, the less you administer, and the less control you have.

### 2. Virtual machines

- **Sizes:** the series shows the purpose. `B` is burstable (cheap, for light workloads; your project uses `Standard_B2ls_v2`), `D` is general purpose, `E` is memory-optimized, `F` is compute-optimized.
- **Disks:** an OS disk is required, data disks are extra. Types: Standard HDD, Standard SSD, Premium SSD, Ultra.
- **Stop vs deallocate:**
  - stopping from the OS: the VM is off, but the hardware is still reserved, so **you keep paying for compute**;
  - `az vm deallocate`: the hardware is released, you don't pay for compute, but you keep paying for disks and a static IP.
- **`custom_data` / cloud-init runs only on first boot.** Updating an application on a running VM has to be done another way: SSH, Ansible, VM extensions, or recreating the VM (`-replace`).

### 3. Availability

| Option | What it protects against | VM SLA |
|---|---|---|
| A single VM with Premium SSD | | 99.9% |
| **Availability set** | a rack failure or an update in one datacenter | 99.95% |
| **Availability zones** | the failure of a whole datacenter | 99.99% |
| Several regions | a region failure | depends on the architecture |

### 4. VMSS

- A group of identical VMs from one image.
- **Autoscale:** adds or removes instances based on metrics (CPU, a queue) or a schedule.
- Usually sits behind a Load Balancer or Application Gateway.
- Modes: Uniform (all identical) and Flexible (recommended now; supports zones and mixed sizes).

### 5. App Service

- The **App Service Plan** is the hardware (SKU: Free, Basic, Standard, Premium) and the number of instances. A **Web App** is an application running on the plan. Several apps can share one plan.
- Deployment: code (Node, Python, .NET, Java) or a container.
- Built in: HTTPS, custom domains, deployment slots (staging → swap into production with no downtime), autoscale.

### 6. Containers

| | Container Apps (ACA) | AKS |
|---|---|---|
| Kubernetes | under the hood, hidden | full access |
| Who manages the cluster | Azure | you (Azure manages only the control plane) |
| Scale to 0 | yes | no (not without extra tools) |
| When | microservices, APIs, background jobs that don't need Kubernetes | you need Kubernetes features, complex platforms, a team with K8s experience |

ACA terms from your project:
- **Environment**: a shared boundary for several apps: network, logs. A trial subscription allows only one.
- **Revision**: an immutable version of an app. A new image version creates a new revision.
- **Ingress**: incoming traffic; `target_port` must match the app's port.

**ACR:** a private image registry. Access: the admin user (simpler, less secure) or a managed identity with the `AcrPull` role (recommended). `az acr build` builds an image in Azure (ACR Tasks), but it's disabled on a trial subscription.

### 7. What to choose

| Task | Service |
|---|---|
| Full control over the OS, legacy software | VM |
| Many identical VMs with autoscaling | VMSS |
| A web app or API without OS administration | App Service |
| Containers without Kubernetes, pay per use | Container Apps |
| A platform on Kubernetes | AKS |
| Short events, triggers, cron | Azure Functions |

### 8. Storage account

| Replication | Copies | Where | Protects against |
|---|---|---|---|
| **LRS** | 3 | one datacenter | a disk or server failure |
| **ZRS** | 3 | three zones in a region | a datacenter failure |
| **GRS** | 6 | LRS + an async copy in the paired region | a region failure |
| **GZRS** | 6 | ZRS + a copy in the paired region | datacenter and region failures |
| **RA-GRS / RA-GZRS** | 6 | like GRS/GZRS + read access in the second region | |

Blob access tiers: **Hot** (read often), **Cool** (rarely, 30+ days), **Cold** (90+ days), **Archive** (very rarely; restoring takes hours).

### 9. Monitoring

- **Azure Monitor**: the overall platform for metrics and logs.
- **Log Analytics workspace**: log storage, queried with **KQL**.
- **Diagnostic settings**: what a resource sends and where (logs from NSG, Key Vault, App Service).
- **Alerts**: notifications based on a metric or a log query. Actions are defined by an **action group** (email, webhook).
- **Application Insights**: application monitoring: requests, errors, dependencies.

## Commands to know by heart

```
az vm list -d -o table                       # with current power state
az vm deallocate -g <rg> -n <vm>
az vm start -g <rg> -n <vm>
az vm list-sizes -l swedencentral -o table
az webapp list -o table
az containerapp list -o table
az containerapp logs show -n <app> -g <rg>
az acr repository list -n <acr> -o table
```

## Check yourself

For three applications, choose a service and justify the choice by cost, scaling and responsibility: (1) a legacy .NET Framework app on Windows; (2) a REST API with uneven load; (3) 30 microservices for a team with Kubernetes experience.

## Interview questions

- IaaS, PaaS, SaaS: what's the difference, with Azure examples?
- VM, VMSS, App Service, Container Apps, AKS: when to use which?
- Availability set or availability zone?
- Stop or deallocate: what's the cost difference?
- LRS, ZRS, GRS: which to choose for Terraform state, and why?
- How do you update an application on a VM without recreating it?
- What is a deployment slot in App Service?
- How do you give App Service or ACA access to ACR without a password?
- How do you set up an alert for high CPU load?
