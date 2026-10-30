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

## Going deeper

### 10. The runtime, and what "managed" means

The **runtime** is the environment that executes your code: Node.js, .NET, Python, the JVM. On a VM you install and patch it yourself; on App Service you pick a version and Microsoft maintains it. With a **container**, the runtime is inside your image (`FROM node:20`), so you rebuild the image to update it, even on PaaS.

Don't confuse it with the **container runtime** (containerd, Docker): the software that runs containers.

**"Managed service" vs PaaS:** every PaaS service is managed, but "managed" just means Azure takes over some operational work. AKS ("managed Kubernetes") manages only the control plane; managed disks are IaaS.

### 11. Containers, images, runtimes

- A **container** is a process isolated by the Linux kernel: **namespaces** (its own view of files, processes, network) and **cgroups** (CPU and memory limits). It shares the host's kernel, so it's much lighter than a VM.
- An **image** is the packaged app plus everything it needs. One image can run as many containers.
- Images and runtimes are standardized by **OCI**, so an image built with any tool runs anywhere.

| Layer | Examples | Job |
|---|---|---|
| Recipe | **Dockerfile** (or `Containerfile`) | instructions to build an image |
| Build tools | Docker, Podman, Buildah, BuildKit (Docker's own engine) | read the Dockerfile and build an image |
| Registry | Docker Hub, **ACR**, ghcr.io | store and share images |
| High-level runtime | **containerd**, CRI-O | pull images, manage container lifecycles |
| Low-level runtime | runc | ask the kernel to start the isolated process |
| Orchestrator | Kubernetes, Container Apps | decide which containers run, how many, where |

- All build tools read the same Dockerfile. Only newer BuildKit features (`RUN --mount=type=cache`, `--mount=type=secret`) may differ.
- Kubernetes talks to runtimes through the **CRI** and dropped direct Docker Engine support in 1.24. AKS uses containerd. Images built with Docker still work everywhere.
- Other kinds: **Windows containers**; sandboxed runtimes like **Kata Containers** (each container in a tiny VM) for untrusted code.

### 12. Registries: Docker Hub and ACR

A registry is like npm for images: `docker push` = `npm publish`, `docker pull` = `npm install`.

```
myacr.azurecr.io / myapp : 1.4.0
└── registry ──┘  └ repo ┘ └ tag ┘
```

- **Docker Hub** is the default public registry (`node:20` = `docker.io/library/node:20`): official images, verified publishers, community images. Pulls are **rate-limited**, and **tags can move**: pin a digest (`@sha256:...`) for exactness.
- **ACR** is your private registry in Azure: managed identity with `AcrPull` (no passwords), private endpoints, no pull limits, Defender scanning, geo-replication on Premium. `az acr import` copies public images in.
- Typical flow: base image from Docker Hub → your image built in CI → pushed to ACR with a version tag → every environment pulls the same image. Never deploy `latest`.

### 13. What controls a VMSS

- **The model:** image, size, network, `custom_data`. Every instance is created from it.
- **Capacity:** set by you (`instances`) or by **Azure Monitor autoscale**. With autoscale, Terraform needs `lifecycle { ignore_changes = [instances] }`.
- **Upgrade policy:** how model changes reach existing instances: **manual**, **automatic** (all at once), or **rolling** (in batches, waiting for health).
- **Health:** an LB probe or the Application Health extension; **automatic repairs** replace unhealthy instances.
- **Orchestration:** Uniform (identical, managed as a group) or Flexible (recommended now).
- The scale set itself is **free**: you pay per instance, as for normal VMs.

### 14. Autoscaling

Horizontal scaling (**scale out/in**: more or fewer instances, no downtime) vs vertical (**scale up/down**: a bigger VM, with a restart). A single VM can't autoscale: that needs a VMSS, which has a model to copy.

An autoscale profile: **min**, **max**, **default**, **scale-out** and **scale-in** rules (e.g. CPU > 70% / < 30% for 10 min), a **cooldown**. Also **schedule-based** rules and **predictive** autoscale.

- Leave a gap between thresholds, or it **flaps**.
- Instances must be **stateless**: anything that must survive goes to a database, Storage or a cache.
- New VMs take minutes to be ready: scale out early.

### 15. VM vs VMSS

**The test:** can any instance be deleted at any moment and recreated from the image without losing anything?

- **Yes** → VMSS (or PaaS/containers): web and API tiers, queue workers, CI build agents, batch and rendering (often on **Spot**), NVAs behind an internal LB, game servers.
- **No** → a single VM with backups, or a **managed service**: databases, file servers, domain controllers, jump boxes, legacy apps that can't run as several copies, machine-bound licenses.

### 16. Kubernetes and VMSS together

VMSS scales **machines**; Kubernetes manages **applications** (containers) on them: it packs many apps onto shared nodes, scales individual apps in seconds, heals, does rolling updates and rollbacks, and provides service discovery.

```
Kubernetes control plane (in AKS hosted by Microsoft): API server, scheduler, etcd
        │ "run these pods on node 2"
node pool = a VMSS:  VM 1 (kubelet + containerd + pods)   VM 2 (...)
```

- **Cluster, node, pod, Deployment:** the cluster is the whole system; nodes are its VMs (created through node pools); a pod wraps one container; you declare a **Deployment** ("image X, 3 replicas") and Kubernetes creates the pods and places them on nodes (**scheduling**).
- The Dockerfile is used only to **build the image** before; Kubernetes knows only the image name.
- **Scaling in AKS is two-level:** the **HPA** adds pods on CPU or metrics; the **cluster autoscaler** adds VMs to the node pool's VMSS when pods are **Pending** for lack of room. Never touch the node pool's VMSS directly; pods need resource **requests** for this to work.
- Kubernetes only manages containers it started itself.

### 17. Container Apps: scaling without Kubernetes

No VMs and no VMSS for you: you define the image, CPU/memory per replica and **scale rules**: `min_replicas`/`max_replicas`, HTTP concurrency, events (queues, Event Hubs, Kafka, through **KEDA**), CPU/memory, cron.

**Scale to zero:** with `min_replicas = 0`, an idle app runs no replicas and costs nothing for compute; the next request starts one, with a **cold start** of a few seconds. For latency-sensitive APIs, keep `min_replicas = 1`. AKS can't really do it: nodes keep running and cost money.

**Workload profiles:** Consumption (serverless, the default) or Dedicated (you pick a machine profile and a count range, still no VMSS to manage).

### 18. Updating an app on a VM without recreating it

`custom_data` runs only on first boot, so it's not a deployment mechanism. Options, from simplest to most mature: SSH (not repeatable); **`az vm run-command`** (no SSH, controlled by RBAC, easy from CI); Custom Script Extension; **Ansible** for fleets; a **versioned container image** from a registry (pull a new tag and restart; rollback = previous tag); several VMs behind a Load Balancer for **rolling** or **blue-green** updates. The alternative is **immutable infrastructure**: bake a new image with Packer and roll it out to a VMSS.

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

For three applications, choose a service and justify the choice by cost, scaling and responsibility: (1) a legacy .NET Framework app on Windows; (2) a REST API with uneven load; (3) 30 microservices for a team with Kubernetes experience. The hands-on exercise is in [`practice-07-compute.md`](practice-07-compute.md).

## Interview answers

**IaaS, PaaS, SaaS, and what's the runtime?**
> In IaaS (a VM), Microsoft manages the hardware, virtualization and network, and I manage everything from the OS up. In PaaS (App Service), Microsoft also manages the OS and the runtime, and I bring code and data. In SaaS (Microsoft 365), I only manage data and access. The runtime is the environment that executes the code, like Node.js or .NET: on IaaS I patch it, on PaaS I pick a version; with containers it's inside my image, so I'm responsible for it even on PaaS.

**VM or VMSS?**
> A VMSS is for identical, stateless instances that can be added, removed or replaced at any time, which is what makes autoscaling and rolling upgrades possible. Databases, file servers, unique roles like domain controllers, legacy apps that can't run as several copies and machine-bound licenses stay on individual VMs with backups, or move to managed services. The scale set itself is free: you pay per instance.

**Where is a VMSS useful?**
> For many identical, stateless machines that need OS-level control: web or API tiers behind a load balancer, queue-driven worker pools, CI build agents, batch and rendering jobs on Spot VMs, and network appliances behind an internal load balancer. It's also the foundation of AKS node pools and Azure Batch. When the app can run as a container or on App Service, PaaS is less to manage.

**How does autoscaling work?**
> It adjusts the number of instances with the load: horizontal scaling, without downtime. A VMSS behind a Load Balancer scales by Azure Monitor rules, like +1 instance when average CPU is over 70% for 10 minutes and −1 under 30%, within min/max and with a cooldown; schedule-based and predictive scaling are options too. Instances must be stateless, thresholds need a gap to avoid flapping, and in Terraform I ignore changes to the instance count.

**Why Kubernetes if VMSS can scale?**
> A VMSS scales machines: a whole VM per step, usually one app per scale set, in minutes. Kubernetes orchestrates containers on those machines: it packs many apps onto shared nodes, scales each app in seconds, restarts or moves failed containers, does rolling updates and rollbacks, and provides service discovery. They're complementary: AKS node pools are VMSS, grown by the cluster autoscaler when pods don't fit, while the HPA scales the pods.

**Container Apps or AKS?**
> Container Apps hides Kubernetes completely: I define the container, ingress and scale rules, and Azure runs everything, including scaling to zero, which means no cost when idle, at the price of a cold start. AKS gives me a full cluster: Azure manages the control plane, but I manage node pools and everything deployed with `kubectl` or Helm. That's far more flexible but needs Kubernetes skills, and nodes cost money even when idle.

**What is a container, and does Kubernetes need Docker?**
> A container is a process isolated by Linux kernel features: namespaces and cgroups. Docker popularized the tooling, but images and runtimes are standardized by OCI, so an image built with Docker, Podman or Buildah runs anywhere. Kubernetes uses runtimes through the CRI, usually containerd as in AKS; it dropped direct Docker Engine support in 1.24, which changes nothing for images built with Docker.

**Docker Hub or ACR?**
> Docker Hub is the default public registry with official images like `node`; it rate-limits pulls and tags can move, so production pins versions or digests. For our own images in Azure, ACR: private, pulled by AKS or Container Apps with a managed identity and `AcrPull` instead of passwords, reachable privately, without pull limits. Public base images can be imported into ACR too.

**How do you update an application on a VM without recreating it?**
> Cloud-init and `custom_data` only run on first boot. For in-place updates, the pipeline runs a deployment script with `az vm run-command` (no SSH, RBAC-controlled), or Ansible for a fleet. Ideally the app is a versioned container image, so an update is pulling a new tag and restarting, and rollback is the previous tag. For zero downtime, several VMs behind a Load Balancer are updated one by one. The alternative is immutable infrastructure: a new Packer image rolled out to a scale set.

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
- What is a container, and how is it different from a VM?
- Does Kubernetes need Docker?
- What is a registry? Docker Hub or ACR?
- What controls a VMSS, and what are upgrade policies?
- Why use Kubernetes if VMSS can already scale?
- How does scaling work in AKS?
- What does "scale to zero" mean, and what's the trade-off?
- When would you still choose a single VM over a VMSS?
