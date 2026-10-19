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

Tell each one out loud in 2 minutes.

## Exams

- **Terraform Associate (HashiCorp):** Terraform basics, state, modules, workflow, Terraform Cloud. Weeks 2–6 and 9 of this plan cover most topics.
- **AZ-104 (Azure Administrator):** identity, RBAC, networking, compute, storage, monitoring. Weeks 1, 4, 7, 8.
- **AZ-400 (DevOps Engineer):** the next step after AZ-104.

## Check yourself

Walk an interviewer through your project in 5 minutes: the architecture, why you chose these services, how state and CI/CD work, what broke and how you fixed it. Then ask Claude for a mock interview: 10 Terraform and Azure questions with feedback on your answers.

## Interview questions

- Tell me about the hardest infrastructure problem you've solved.
- Terraform or Bicep for a new Azure company?
- Design infrastructure for a web application with HA and DR.
- What are RTO and RPO? How do you achieve them?
- How would you organize Terraform for five teams?
- How do you migrate manually created infrastructure into Terraform?
- How do you reduce Azure costs?
- What would you improve in your project if you had another week?
