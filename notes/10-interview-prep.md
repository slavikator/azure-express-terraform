# Week 10. Final preparation

Turn your knowledge into a story and practice answering.

## Terms

| Abbreviation / term | Stands for | What it is, in one sentence |
|---|---|---|
| **Bicep** | | Microsoft's IaC language for Azure only; compiles to ARM templates |
| **ARM template** | | A JSON description of Azure resources, the "native" IaC |
| **Pulumi** | | IaC in regular programming languages (TypeScript, Python, Go) |
| **HA** | High Availability | The system keeps working when individual components fail |
| **DR** | Disaster Recovery | Recovering after a region failure or data loss |
| **RTO** | Recovery Time Objective | How quickly the system must recover |
| **RPO** | Recovery Point Objective | How much data it's acceptable to lose (measured in time) |
| **WAF** | Well-Architected Framework | Azure's five pillars: reliability, security, cost, operational excellence, performance |
| **STAR** | Situation, Task, Action, Result | A structure for telling an experience story in an interview |
| **FinOps** | | The practice of managing cloud costs |

## Concepts you need to explain in your own words

### 1. Terraform, Bicep, ARM, Pulumi

| | Terraform | Bicep | ARM template | Pulumi |
|---|---|---|---|---|
| Clouds | any | Azure only | Azure only | any |
| Language | HCL | Bicep | JSON | TS, Python, Go, C# |
| State | a file you manage | none, state comes from Azure | none | a service or a file |
| New Azure features | delayed until the provider is updated | immediately | immediately | delayed |
| Preview of changes | `plan` | `what-if` | `what-if` | `preview` |

**How to answer "which would you choose":** a team that's Azure-only and has no Terraform experience → Bicep: no state, new Azure features immediately. Several clouds or SaaS providers (GitHub, Cloudflare, Datadog), a team that already knows Terraform, a need for a large module ecosystem → Terraform.

### 2. System design: a web application in Azure

A diagram you should be able to draw and explain:

```
User
   │
Front Door (WAF, global entry point, CDN)
   │
Application Gateway / or App Service directly
   │
App Service or Container Apps (several instances, availability zones)
   │  managed identity
   ├── Key Vault (secrets)
   ├── Azure SQL / PostgreSQL Flexible (zone-redundant, geo-replication for DR)
   └── Storage (ZRS or GZRS)
   │
Log Analytics + Application Insights + alerts
```

What you must cover:
- **Network:** VNet, private endpoints for the database and Key Vault, no public access to data.
- **Identity:** managed identity instead of passwords, RBAC with least privilege.
- **Reliability:** availability zones, autoscale, backups, a DR plan with RTO and RPO.
- **Deployment:** IaC, CI/CD with plan on PR and approved apply, deployment slots.
- **Monitoring:** metrics, logs, alerts.
- **Cost:** sizing for the load, autoscale, reserved instances.

### 3. Cost optimization

- Right-sizing based on usage metrics.
- **Reserved instances** and **savings plans**: a discount for a 1–3 year commitment.
- **Spot VMs**: up to 90% cheaper, but Azure can take the VM back. For batch jobs.
- Autoscale and scaling to zero (Container Apps, Functions).
- Shutting down dev overnight and on weekends.
- Storage tiers (Hot, Cool, Archive) and lifecycle policies.
- Budgets and alerts, tags for splitting costs between teams.
- Deleting "orphaned" resources: disks without a VM, unused public IPs.

### 4. Migrating manual infrastructure into Terraform

1. Inventory: `az resource list`, Azure Resource Graph.
2. Code for the resources (by hand, `terraform plan -generate-config-out`, or aztfexport).
3. `import` blocks.
4. `plan` must show `No changes`. Keep aligning the code until it does.
5. Forbid manual changes: RBAC, Azure Policy, drift detection.

### 5. Terraform for several teams

- Modules in a separate repository with versions (tags), or Azure Verified Modules.
- Separate states for teams and environments, separate SPs with permissions only for their own scope.
- Standards: required tags, policies, a repository template.
- CI checks: fmt, validate, tflint, checkov, Infracost.
- A platform team maintains the modules and pipelines; product teams use them.

## My interview stories (STAR)

### Story 1. CI hung on `terraform init`
- **Situation:** after a refactor, the GitHub Actions pipeline hung on the `terraform init` step.
- **Task:** find the cause and make the pipeline reliable.
- **Action:** I found that the `backend "azurerm"` block had become empty. Locally the parameters had been entered interactively and saved in `.terraform/`, but in CI Terraform waited for input. I wrote the backend configuration explicitly and added `-input=false` to all commands.
- **Result:** init passes. If parameters are missing, the step fails right away with an error instead of hanging. The lesson: always use `-input=false` in CI.

### Story 2. State diverged from Azure
- **Situation:** `apply` failed with `ManagedEnvironmentNoAvailableCapacityInRegion`, but Azure later created the Container Apps environment anyway.
- **Task:** bring the state back in line with reality.
- **Action:** I found the resource with `az` and tried `import`, but the service's own `provisioningState` turned out to be `Failed`, even though the general resource status showed `Succeeded`. I removed it from the state (`state rm`), deleted it, and moved the environment to another region.
- **Result:** the infrastructure came up. The lessons: check the state of the specific service, not the general resource status; know the subscription's limits (a trial allows only one environment).

### Story 3. A provider without an upper version bound
- **Situation:** `terraform destroy` failed twice with `polling support ... was not implemented`.
- **Task:** cleanly remove the infrastructure.
- **Action:** I found that the constraint `>= 3.118.0` had pulled in azurerm 5.8.0, which had a bug. Resources were deleted in Azure, but not from the state. I checked the real state with `az` and ran `destroy` again: refresh saw that the resources were already gone.
- **Result:** the infrastructure was removed. I pinned versions with `~>` and added the lock file to git.

### Story 4. CI brought the infrastructure back after `destroy`
- **Situation:** after a manual `destroy`, pushing a commit with notes created the VM again.
- **Action:** through the activity log I found that the resources had been created by the CI service principal. The cause: `apply` on every push to main.
- **Result:** I left only `plan` on push, and I run `apply` manually. The lesson: a pipeline with auto-apply conflicts with manual changes; you need explicit approval.

### Story 5. A double Ctrl+C left a VM outside the state
- **Situation:** during `apply -replace` of a VM, the process was killed (simulating a laptop dying). The next `plan` wanted to create the VM again.
- **Task:** recover without losing or duplicating anything.
- **Action:** diagnosed with commands, not guesses: the state lock was free, `state list` didn't contain the VM, but `az vm show` showed it in Azure as `Succeeded`. Azure had finished creating it after Terraform was killed. Imported it with an `import` block, checked `plan` showed `1 to import, 0 to change`, then `No changes`.
- **Result:** no duplicate VM, no data loss. Lessons: one Ctrl+C is a graceful stop that records results; check lock, state and Azure separately; "not in the state" doesn't mean "not in Azure".

### Story 6. Trial quotas and partial applies
- **Situation:** an `apply` failed with `PublicIPCountLimitReached` (3 public IPs per region), and another with the regional vCPU quota (4 cores), while other resources in the same apply succeeded.
- **Task:** understand what was created and finish the deployment.
- **Action:** checked usage with `az network list-usages` and `az vm list-usage`; saw that Terraform had recorded exactly what succeeded (a partial apply, not a broken state). Redesigned the exercise to use resources without tight quotas, and re-ran `apply` once parallel deletions had released cores. Also learned that deallocated VMs still count toward the vCPU quota.
- **Result:** completed without manual state edits. Lessons: check quotas before big changes; independent resources are created in parallel, so a create can race a delete; the state always reflects what actually happened.

### Story 7. A `count` list nearly recreated resources
- **Situation:** removing the first item from a list used with `count` showed `2 to add, 3 to destroy` instead of deleting one resource.
- **Action:** recognized that `count` addresses are positions, so every later item shifted. Migrated to `for_each` with three `moved` blocks (plan: only `has moved to`), then removed the item again: `1 to destroy`, and the remaining resources kept their IDs.
- **Result:** a safe pattern for collections: `for_each` with stable keys, and `moved` blocks for migrations.

Tell each one out loud in 2 minutes.

## Exams

- **Terraform Associate (HashiCorp):** Terraform basics, state, modules, workflow, Terraform Cloud. Weeks 2–6 and 9 of this plan cover most topics.
- **AZ-104 (Azure Administrator):** identity, RBAC, networking, compute, storage, monitoring. Weeks 1, 4, 7, 8.
- **AZ-400 (DevOps Engineer):** the next step after AZ-104.

## Check yourself

Walk an interviewer through your project in 5 minutes: the architecture, why you chose these services, how state and CI/CD work, what broke and how you fixed it. Then ask Claude for a mock interview: 10 Terraform and Azure questions with feedback on your answers. The hands-on exercise is in [`practice-10-interview.md`](practice-10-interview.md).

## Interview answers

**Terraform or Bicep for a new Azure company?**
> Bicep if the team is Azure-only and new to IaC: no state file to manage, and new Azure features are available immediately. Terraform if they use several clouds or SaaS providers like GitHub or Cloudflare, already know Terraform, or want its module ecosystem and `plan` workflow. Both are declarative; the big operational difference is Terraform's state.

**How would you migrate manually created infrastructure into Terraform?**
> Inventory with Azure Resource Graph, then write or generate the code (`plan -generate-config-out`, or aztfexport) and bring resources in with `import` blocks, in small batches. Each batch must reach `No changes` before the next, which proves the code matches reality. Then stop manual changes: RBAC, Azure Policy and drift detection.

**What are RTO and RPO?**
> RTO is how quickly a system must be back after a failure; RPO is how much data, measured in time, it's acceptable to lose. They drive the design: zone-redundant services and autoscaling for availability, backups and geo-replication sized to the RPO, and a tested failover plan to meet the RTO.

**How would you organize Terraform for five teams?**
> Shared, versioned modules (our own or Azure Verified Modules) maintained by a platform team; separate root configurations and states per team and environment, each with its own least-privilege identity through OIDC; standards built into modules and enforced by Azure Policy; CI with fmt, validate, tflint, checkov and Infracost, plan on PR and apply on merge with approvals; and drift detection.

**What would you improve in your project?**
> Move CI to OIDC and a plan/apply split with a saved plan and approvals; restrict SSH through Bastion instead of an open port; switch the state backend to Entra auth with shared keys disabled and private network access; add tflint, checkov and drift detection; and run the app as a versioned container image from ACR instead of building it on the VM.

**How does secretless (OIDC) login from GitHub Actions to Azure work?**
> The job requests a short-lived OIDC token from GitHub and sends it with the app's client ID to Entra; Entra verifies GitHub's signature, matches issuer, subject and audience against the app's federated credential, and issues its own Azure token, and the job's actions are then limited by the service principal's RBAC roles.

**What is Infrastructure as Code?**
> Infrastructure is defined declaratively in version-controlled code, reviewed through pull requests and applied by a pipeline, so environments are repeatable and auditable, and drift can be detected and corrected.

**Where does your Terraform state live, and why there?**
> State lives remotely in a dedicated, bootstrapped storage account outside the environments it describes, with one state file per environment, so environments are isolated and destroying one never touches its own state.

**How is the state protected?**
> The state blob has versioning and soft delete, so I can roll back a bad write or undelete it, and Terraform locks it with a blob lease so two runs can never write at once. Access is Entra ID only, with shared keys disabled.

**What is HCP Terraform (Terraform Cloud), and why didn't you use it?**
> HCP Terraform is managed Terraform: remote state and locking, workspaces, VCS-driven plan and apply, dynamic OIDC credentials, and policy as code with Sentinel or OPA. I built the same pieces myself with Azure Storage and GitHub Actions, which gives more control and lower cost; HCP trades that for less to maintain.

**What triggers your pipeline, and what does each trigger do?**
> PRs into main run checks and plan, a merge to main runs plan and a gated apply, and workflow_dispatch lets me rerun the pipeline by hand without applying.

**Why are validate and lint separate jobs?**
> Per-root checks like validate run in a matrix per environment; whole-repo scans like fmt, tflint and checkov run once in a parallel job, and plan waits for both.

**Why does every job check out the code and install Terraform again?**
> Every job runs on a fresh runner, so it checks out the commit under test and installs a pinned Terraform version; pinning matters because a saved plan can only be applied by the exact same version.

**How do you limit what each CI job can do?**
> Each job gets only the token scopes it needs: read-only by default, `pull-requests: write` only in the job that posts the plan comment, and `id-token: write` only where Azure login is needed. A job-level permissions block replaces the top-level one, so it can also grant less.

**How does your drift detection work?**
> A nightly refresh-only plan with `-detailed-exitcode` (0 no changes, 1 error, 2 changes) and `-lock=false` turns drift into a failing job without blocking real applies; the setup-terraform wrapper must be disabled, or it treats exit code 2 as success.

**What does TFLint add to `terraform validate`?**
> TFLint is a pluggable linter: `.tflint.hcl` pins the azurerm ruleset, `tflint --init` downloads it, and it catches Azure-specific mistakes like invalid VM sizes that `terraform validate` can't see.

**How do you catch cost before it's spent?**
> Infracost prices the Terraform plan in CI and comments the monthly cost diff on the PR, so cost is reviewed alongside the change, while budgets and anomaly alerts in Cost Management catch what actually gets spent.

**What is Azure Front Door?**
> Front Door is the global HTTP entry point: anycast at Microsoft's edge, TLS, WAF and caching close to the user, health-based failover between regions, and the origin locked so traffic can only arrive through Front Door.

**What's the difference between layer 4 and layer 7 load balancing?**
> Layer 4 balances connections by IP and port; layer 7 understands HTTP, so it can route by path, terminate TLS, cache, and run a WAF. Load Balancer is L4; Application Gateway and Front Door are L7.

**What are deployment slots for?**
> Deployment slots let you deploy to a warmed-up staging copy of the app, validate it, and swap it into production with no downtime; rollback is just swapping back. Sticky settings keep environment-specific config like connection strings with the slot.

**How would you give SSH access without an open port 22?**
> The VM has only a private IP and the NSG allows SSH only from AzureBastionSubnet. Users connect over TLS through Azure Bastion, authenticated with Entra ID and RBAC, ideally with Entra SSH login so there are no keys to manage. For cheaper setups, JIT access opens the port only for my IP and only for a limited time.

**What is Azure Resource Graph used for?**
> Azure Resource Graph is a KQL-queryable index of all resources across subscriptions. I use it for inventory and governance: untagged or orphaned resources, insecure settings, policy compliance, and recent changes, respecting RBAC and without touching the resources.

## Interview questions

- Tell me about the hardest infrastructure problem you've solved.
- Terraform or Bicep for a new Azure company?
- Design infrastructure for a web application with HA and DR.
- What are RTO and RPO? How do you achieve them?
- How would you organize Terraform for five teams?
- How do you migrate manually created infrastructure into Terraform?
- How do you reduce Azure costs?
- What would you improve in your project if you had another week?
