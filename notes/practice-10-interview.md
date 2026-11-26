# Week 10 practice: "Ready to talk about it"

**Goal:** turn ten weeks of work into a clear story: a README that explains the project and its decisions, interview stories you can tell in two minutes, a five-minute project walkthrough, mock interviews with feedback, an exam-style self-check, and a clean Azure account at the end.

**Topics:** everything from weeks 1–9, spoken out loud.

**Time:** 4–6 hours spread over several days. Talking practice works better in short, repeated sessions. **Cost:** none, except a short `apply` if you want to demo the project live.

**Notes:** [`10-interview-prep.md`](10-interview-prep.md)

---

## Rules for this practice

1. **Out loud, not in your head.** Every explanation here is spoken, ideally recorded on your phone. You'll hear the gaps immediately.
2. **No notes while answering.** Read the notes before and after, never during.
3. **Two minutes per answer.** Long answers lose the interviewer; short ones sound unprepared.

---

## Step 1. The README

Write `README.md` in the repo root. It's the first thing an interviewer opens if you share the link.

Include:

- **What it is**, in two sentences: an Express app on Azure, infrastructure in Terraform, deployed by GitHub Actions;
- **an architecture diagram** in Mermaid (GitHub renders it):

  ````
  ```mermaid
  flowchart LR
    dev[git push] --> ci[GitHub Actions: checks, plan]
    ci -->|approval| apply[apply]
    apply --> rg[Resource group]
    rg --> vnet[VNet + subnets + NSG] --> vm[VM: Express in Docker]
    state[(State: Azure Storage)] --- ci
  ```
  ````

- **the decisions and why**: separate state RG with versioning and a lock, `for_each` over `count`, modules and separate environment roots, OIDC instead of secrets, Entra auth for the state, policies;
- **how to run it**: prerequisites, `init`, `plan`, `apply`, `destroy`;
- **what you'd do next**.

> ❓ **1.** Ask someone (or Claude) to read only the README and explain the project back to you. What did they misunderstand, and what did you change?

---

## Step 2. Your stories

Your notes have six stories (STAR format): the CI hang on `init`, the provider without an upper bound, CI recreating the VM, the double Ctrl+C, the quotas and partial applies, and the `count` trap.

For each:

1. tell it out loud in **two minutes**, and record it;
2. listen back once, and note what was unclear or too long;
3. tell it again.

> ❓ **2.** Which two stories are your strongest, and which question would each answer? (E.g. "Tell me about a production incident", "a mistake you made", "a time you improved a process".)

---

## Step 3. The five-minute walkthrough

Prepare a five-minute tour of the project, as if sharing your screen in an interview:

1. the architecture (the README diagram);
2. the code structure: modules, environments, why;
3. state: where it lives, how it's protected, locking;
4. the pipeline: from PR to apply, with every gate;
5. security: OIDC, managed identity, Entra auth, policy;
6. one story of something that broke, and what you changed.

Record it, and time it.

> ❓ **3.** Where did you run over time, and what did you cut?

---

## Step 4. Mock interviews with Claude

Run three separate sessions. Start each with a prompt like:

> "Act as an interviewer for a mid-level DevOps engineer role focused on Azure and Terraform. Ask me 10 questions, one at a time, mixing [topic]. Wait for my answer before the next question. After each answer, give short feedback: what was correct, what was missing, and a model answer. At the end, give me a score and the three topics to review."

| Session | Topics |
|---|---|
| 1 | Terraform: state, modules, `for_each`, lifecycle, import, drift |
| 2 | Azure: identity and RBAC, networking, compute choices, security |
| 3 | CI/CD and scenarios: "the apply failed halfway", "someone changed prod by hand", "design a pipeline for five teams" |

Type your answers without looking at the notes.

> ❓ **4.** What were the three weakest topics across the sessions? Re-read those notes sections and retry them in a fourth session.

---

## Step 5. Exam-style self-check

1. **Terraform Associate:** read the official exam objectives on HashiCorp's site, and for each objective write the week of this plan that covers it. Mark any objective with no matching week, and study it. Then take a practice test.
2. **AZ-104** (if you plan it later): go through the skills outline and mark each area green, yellow or red.

> ❓ **5.** Which Terraform Associate objectives weren't covered by this plan, and what did you do about them?

---

## Step 6. A system design exercise

Design, on paper, the infrastructure for a public web app with a database:

- HA within a region, and DR to a second region, with your target **RTO and RPO**;
- networking: VNet, subnets, private endpoints, how users reach it;
- identity: managed identities, no passwords;
- deployment: how a change reaches production;
- monitoring and alerts;
- a rough monthly cost, and where you'd save money.

Explain it out loud in ten minutes.

> ❓ **6.** Which trade-off was hardest to decide, and how would you justify it to an interviewer?

---

## Step 7. Final cleanup of the Azure account

```
az group list -o table                      # nothing left except rg-tfstate (and what you deliberately keep)
az ad app list --show-mine -o table          # remove app registrations you no longer use
az role assignment list --all --query "[?principalType=='ServicePrincipal'].{id:principalName, role:roleDefinitionName, scope:scope}" -o table
az consumption budget list -o table          # your budget alert still exists
```

Remove the unused service principal from week 1's notes ("two SPs with Contributor, one no longer used"), and any leftover role assignments.

> ❓ **7.** What did you find and remove? Why do unused identities with roles matter for security?

---

## Outcome

After this practice you should be able to:

- explain the project and its decisions from the README alone;
- tell your strongest stories in two minutes each;
- walk an interviewer through the project in five minutes;
- answer mixed Terraform and Azure questions without notes;
- design and justify a small production architecture;
- leave your cloud account clean.

## My answers

1. **Step 1 done** (README.md merged in PRs #9 and #10; "What I'd do next" dropped on purpose). Skipped the read-back exercise; went through every README section in a review instead: remote state in a separate bootstrapped RG with one key per root, versioning, soft delete and blob lease locking, validation/precondition vs Azure Policy, OIDC with three federated credentials, the ruleset (`~DEFAULT_BRANCH`, a GitHub setting, not code) and the environment gate, job-level permissions replacing top-level ones, `-detailed-exitcode`, tflint plugins via `.tflint.hcl`, the SSH public-key flow, and the prerequisites (data-plane role for the state). Fixed along the way: prod tags had `env = "dev"`.
2. **Step 2, in interviewer mode (chat, no recording).** Story 1 retold in my own words; Story 2 cut to the lesson (pin with `~>`, commit the lock file); the Container Apps story dropped as too specific.

   **Story 3, "a time automation did something you didn't expect":** I destroyed everything by hand, then pushed a notes-only change, expecting CI not to run because no Terraform code changed. The VM came back, because the workflow ran on every push. In the activity log the destroy had my email as `caller`, and the new VM had the service principal's ID, so the pipeline had done it. Fix: dispatch runs `plan` without `apply`, and push only runs after the PR is reviewed and approved.

   **Correction:** the approval isn't on the PR. The PR runs `plan` for the reviewer; the merge is the push to `main` that starts `apply`, and `apply` waits for approval in the `dev` environment.
   **Correction:** end with the lesson: with auto-apply, the code is the source of truth, so to remove infrastructure you remove it from the code.
   **Follow-up, "why not skip CI when only notes change?":** a `paths` filter would fix this one case, but the real problem was that `apply` could run without anyone looking. The approval fixes every case.

   **Tightened:** "I destroyed the infrastructure by hand, then pushed a notes-only change. The VM came back, because the workflow ran `apply` on every push to `main`, regardless of which files changed. In the activity log, the destroy had my email as `caller`, and the new VM had the CI service principal's ID, so I knew the pipeline did it. I changed the flow: PRs run `plan` for review, and after the merge `apply` waits for approval in a GitHub environment. The lesson: with auto-apply, the code is the source of truth."

   **Story 4, "a time the state didn't match reality":** my Mac crashed during the apply. I checked the lock: it wasn't locked. I checked the state: the VM was gone, because the apply was recreating it and had removed the old one but not created the new one. Then I checked Azure, and the VM was there: Terraform had already sent the create request, so Azure finished the job. I added an `import` block for the existing VM, so Terraform wouldn't try to create it again.

   **Correction:** say it was a simulation (Practice 03: a double Ctrl+C during `apply -replace`), not a real crash. In a real crash the lock usually stays stuck and needs `force-unlock`, so the details wouldn't hold up.
   **Correction:** add the verification: `plan` showed `1 to import, 0 to change`, then `No changes` after the apply.
   **Correction:** end with the lesson: "not in the state" doesn't mean "not in Azure".

   **Tightened:** "In a lab I simulated a laptop dying mid-apply by killing Terraform while it replaced a VM. Afterwards I checked three things separately: the lock was free, the VM wasn't in the state, but `az vm show` showed it running, because Azure finished creating it after Terraform died. I adopted it with an `import` block, confirmed `plan` showed 1 to import and 0 to change, and ended with `No changes`. The lesson: 'not in the state' doesn't mean 'not in Azure', so check each one before acting."

   **Story 5, "an apply that failed halfway":** an apply failed halfway because my trial subscription limits public IPs to 3 and cores to 4. Some resources were created and some weren't: a partial apply. The state isn't broken; Terraform recorded what succeeded. I checked usage with `az`, found a region that covered the IPs and cores I needed, added it to my setup and re-ran `apply`.

   **Correction:** I didn't add a region. For the public IPs I redesigned the exercise to use NSGs (free, no tight quota); for the cores I destroyed the main VM to free them, then re-ran `apply`. Tell what actually happened.
   **Correction:** end with the lesson: check quotas before big changes; after a partial apply, fix the cause and re-run, don't edit the state by hand. Extra detail: deallocated VMs still count toward the vCPU quota.

   **Tightened:** "On a trial subscription an apply failed halfway: 3 public IPs and 4 vCPUs per region. Some resources were created and some weren't, but the state wasn't broken: Terraform records exactly what succeeded. I checked usage with `az vm list-usage` and `az network list-usages`, freed cores by destroying a VM I didn't need (deallocating isn't enough, it still counts), swapped public IPs for resources without a tight quota, and re-ran `apply`. The lesson: check quotas before big changes, and after a partial apply, fix the cause and re-run, don't touch the state by hand."

   **Story 6, "when `count` and when `for_each`?":** I tried both `count` and `for_each` for a list of NSGs. `count` isn't appropriate here: when an item is removed, the remaining items shift their indexes, and `plan` shows them as removed and added again. `for_each` is right for this kind of list, because the address is a key instead of an index, so removing an item targets exactly that key, with no shifts: `plan` shows only 1 to destroy. Use `count` only for computation; for lists and anything with an address, `for_each`.

   **Correction:** not "`count` only for computation". `count` is for on/off (`count = var.create ? 1 : 0`) or truly identical copies; `for_each` for anything with its own identity.
   **Correction:** mention the migration: switching `count` → `for_each` changes every address, so I used `moved` blocks (`plan`: only "has moved to", nothing recreated).

   **Tightened:** "With `count`, a resource's address is its position, so removing the first NSG from a list shifted the others and `plan` wanted to recreate them. With `for_each`, the address is a key, so removing one item destroys only that item. I migrated with `moved` blocks so nothing was recreated. I use `count` for on/off (`0 or 1`) or truly identical copies, and `for_each` for anything with its own identity."

   **❓2, the two strongest stories:** I picked the provider bound for "something broke" and CI recreating the VM for "a problem you debugged".

   **Correction:** the provider story is now only the lesson, so it can't survive "how did you find it?". Use Story 1 (CI hung on `init`) for "something broke / a production incident", and Story 3 (CI recreated the VM) for "a problem you debugged" or "a time you improved a process". Keep the provider story as a short example of why I pin versions.

   **Step 2 done.**
3. **Step 3, walkthrough in parts (chat, no recording).** Ran over time on part 4 (the pipeline): I listed checkout/install/init for every job. **Cut:** per-job steps; keep the gates, and give details only if asked.

   - **Part 1, architecture:** I described the two RGs (project and state). **Correction:** that's part 3. Part 1 is what runs and where: the app, the network, the region, the environments.
   - **Part 2, code structure:** dev and prod environments, modules for network and VMs reused by both. **Correction:** say why the roots are separate (own state file each, smaller blast radius); prod is only planned, `apply` runs for dev only.
   - **Part 3, state:** a separate RG, versioning, soft delete, a lock, Entra-only access. **Correction:** add why for each. The state must exist before Terraform runs (bootstrap) and destroying the project can't delete it; versioning = roll back, soft delete = recover, a blob lease = no two applies at once, Entra-only = no storage keys, RBAC data role. One key per root.
   - **Part 4, pipeline:** every job and step in order. **Correction:** `plan` runs for dev and prod; I missed both gates (the ruleset requires 5 checks before merge; `apply` waits for environment approval); the artifact is the binary `tfplan`, the text goes to the PR comment.
   - **Part 5, security:** no long-lived secrets (OIDC), policy allows only `swedencentral`, an NSG, access over a public IP. **Correction:** a public IP isn't a control; say SSH keys only and an NSG with only needed ports. Add Entra-only state, least-privilege job permissions, guardrails at two levels (validation at plan, Policy at apply), and name the gap: the public SSH port, Bastion in production.
   - **Part 6, a story:** Story 1 (init hung on the empty backend block). **Correction:** `terraform init` prompted, not `az`; the values were written into the code and committed; end with the lesson.

   **Full five-minute version:**

   1. "It's a small Express app running in Docker on a Linux VM in Azure. The VM sits in a VNet subnet behind an NSG, with a public IP, in `swedencentral`, and there are separate dev and prod environments. All of it is described in Terraform and deployed by GitHub Actions."
   2. "There are reusable modules for the network and the VM, and two environment roots, dev and prod, that call them with different inputs. Each root has its own state file, so a change in dev can't touch prod. That keeps the blast radius small. In the pipeline both are planned on every PR, but only dev is applied."
   3. "The state lives in a storage account in its own resource group, created once before the project, so destroying the project can't touch it. Each environment has its own state file. Versioning and soft delete let me recover a corrupted or deleted state, a blob lease locks it so two applies can't run at once, and access is Entra-only, with no storage keys, through an RBAC data role."
   4. "On a PR, validate runs for both roots and a lint job runs fmt, TFLint and Checkov in parallel. If both pass, plan runs for dev and prod with OIDC and posts the plan as a PR comment. A ruleset on main requires all those checks to pass before merging. The merge reruns the pipeline, saves the plan file as an artifact, and the apply job waits for approval in a GitHub environment, then applies exactly that saved plan. Prod is planned but not auto-applied."
   5. "There are no long-lived secrets: the pipeline signs in to Azure with OIDC, and the state is Entra-only with no storage keys. Each CI job gets only the permissions it needs. Guardrails work at two levels: variable validation catches a wrong region or VM size at plan, and Azure Policy blocks it at apply. The VM uses SSH keys only, and the NSG opens only the ports it needs. The weak spot is the public SSH port; in production I'd remove it and go through Bastion."
   6. "The pipeline hung on `terraform init`. The backend block in the code was empty; locally, init had asked me for the values and cached them in `.terraform/`, which isn't in git, so the fresh CI runner sat waiting for input. I wrote the values into the code and added `-input=false`, so anything missing now fails with a clear error instead of hanging. The lesson: CI only has what's in git, so it has to run with no prompts at all."

   **Step 3 done.**
4. **Session 1, Terraform: 71/100.**

   1. **State (6).** I said: the file describing the actual infrastructure, used to compare, plan, lock and detect drift. **Correction:** its main job is mapping code addresses to real Azure IDs; it's Terraform's last known record, refreshed before plan; locking comes from remote state, not why state exists; it can contain secrets.
      > "State is Terraform's record of the resources it manages. Its main job is mapping each resource in the code to the real object in Azure by ID. On plan, Terraform refreshes the state against Azure, compares it with the code and shows the difference. It can contain secrets, so I keep it remote, encrypted, with locking and restricted access."
   2. **Plan vs apply (8).** I said: plan shows changes; a saved plan makes CI apply exactly what was reviewed. **Correction:** without a file, apply plans again; a stale saved plan is rejected.
      > "`plan` compares the code with the state and shows what would change, without changing anything. `apply` makes the changes; without a plan file, it plans again and asks for confirmation. In CI I save the plan with `-out`, reviewers check it, and apply runs exactly that file. If the state changed in between, Terraform rejects the stale plan."
   3. **Manual changes (6).** I said: plan shows removing the new resource; if legitimate, match the code. **Correction:** a changed managed resource → plan reverts the attribute; a resource created by hand isn't in the state, so Terraform ignores it (import it to manage it).
      > "On the next plan, Terraform refreshes the state, sees the attribute differs from the code, and proposes changing it back. If the manual change was wrong, I apply and the code wins. If it was right, I update the code until plan shows no changes. A resource created by hand isn't in the state, so Terraform ignores it; to manage it, I import it. A scheduled drift check catches this early."
   4. **Modules (7).** I said: reusable resources, like network and VM for dev and prod. **Correction:** a folder with inputs and outputs; the root module; also for standards (naming, tags, secure defaults); don't wrap a single resource; version shared modules.
      > "A module is a folder of Terraform code with inputs and outputs that you call from other configurations. I create one when the same group of resources repeats, like my network and VM used by both dev and prod, or to build in standards like naming, tags and secure defaults. I don't wrap a single resource with no logic. Shared modules are versioned, so consumers upgrade on purpose."
   5. **count vs for_each (9).** I said: `count` for 0/1 or where order doesn't matter, `for_each` otherwise. **Correction:** "address", not "path"; "truly identical copies"; migrate with `moved`.
      > "`count` for on/off (`0 or 1`) or truly identical copies. `for_each` for anything with its own identity, because the address uses a key instead of a position, so removing one item doesn't shift the others. Switching between them needs `moved` blocks."
   6. **Import (5).** I said: import it, because Terraform doesn't know about manual resources. **Correction:** give the how: `import` block (address + Azure ID), write or generate the code, plan shows `1 to import, 0 to change`, apply, remove the block.
      > "I add an `import` block with the resource's address and its Azure ID, and write the resource code, or generate it with `plan -generate-config-out`. Then I adjust the code until plan shows 1 to import and 0 to change, so the import doesn't modify anything. After apply, plan shows no changes, and I remove the import block. I did this when a VM ended up outside the state after an interrupted apply."
   7. **lifecycle (6).** I said: controls create/update/replace/destroy; `ignore_changes` on the VM for changes inside it. **Correction:** Terraform doesn't see inside a VM; `ignore_changes = [custom_data]` ignores that attribute, because changing it forces a replace. Name `create_before_destroy`, `prevent_destroy`, `replace_triggered_by`, preconditions.
      > "`lifecycle` changes how Terraform handles a resource's create, update and destroy. `create_before_destroy` reduces downtime on a replace, `prevent_destroy` protects critical resources, and `ignore_changes` skips attributes managed outside Terraform. In my project I ignore `custom_data` on the VM, because changing it would force a replace, and I use a precondition to allow only B-series VM sizes."
   8. **Concurrent applies (8).** I said: the first locks the state, the second gets "locked". **Correction:** only with a locking backend (blob lease); `-lock-timeout`; `force-unlock` only for a stale lock; CI concurrency group.
      > "The first apply takes a lock on the state; with my azurerm backend it's a blob lease. The second fails with a 'state locked' error showing who holds it, and can retry or wait with `-lock-timeout`. `force-unlock` is only for a lock left behind by a crash. In CI I also use a concurrency group, so applies to the same environment queue."
   9. **Environments (9).** I said: separate roots (duplication, but safer) vs workspaces (easy to be in the wrong one). **Correction:** with modules the roots are thin; separate roots allow separate state and credentials.
      > "I use separate root folders per environment, each calling the same modules with different inputs and with its own state. The roots stay thin, a mistake in dev can't touch prod, and prod can have stricter access. Workspaces avoid even that duplication, but share the backend and credentials, and it's easy to run in the wrong workspace, so I use them only for short-lived copies of the same environment."
   10. **Drift (7).** I said: drift is a check; a nightly `--refresh-only` job, exit code 2 = drift. **Correction:** drift is the difference itself, not the check; the command is `terraform plan -refresh-only -detailed-exitcode`; then apply or update the code.
       > "Drift is when real infrastructure no longer matches the code and state because something changed outside Terraform. I detect it with a nightly pipeline running `terraform plan -refresh-only -detailed-exitcode`; exit code 2 means drift and fails the run. Then I either apply to put things back, or update the code if the change was right."

   **To review:** import steps; `lifecycle` arguments; the definitions of state and drift. **Pattern:** strong where I've done it myself, vague on definitions, so open each answer with a one-line definition, then the example.

   **Session 2, Azure: 48/100.**

   1. **Service principal vs managed identity (2).** I said: SP for the app, MI for the user; `caller` shows email for MI, ID for SP. **Correction:** neither is for a person. An SP is an app identity whose credentials I manage, usable from anywhere; an MI is an SP that Azure manages, no credentials, only for resources in Azure. A person shows as an email in `caller`; an SP and an MI both show as an object ID. Any identity with a role can read Key Vault; MI is preferred for apps in Azure because it removes "secret zero".
      > "Both are identities for applications, not people. A service principal is an app identity whose credentials you manage, a secret, a certificate or OIDC federation, and it works from anywhere. A managed identity is a service principal Azure manages, with no credentials to handle, but only for resources running in Azure. My GitHub pipeline uses a service principal with OIDC; a VM reading Key Vault would use a managed identity."
   2. **RBAC (1).** I described OIDC federation (issuer, subject, audience). **Correction:** that's authentication ("who are you"); RBAC is authorization ("what can you do"). A role assignment = who (principal) + what (role) + where (scope, inherited downward); deny by default, roles add up.
      > "A role assignment is who, what and where: a security principal, a role defining allowed actions, and a scope, from management group down to a single resource, inherited downward. With no assignment, access is denied; roles add up. My pipeline's service principal has Contributor for resources and Storage Blob Data Contributor on the state account, and I keep scopes as narrow as possible."
   3. **Contributor vs Owner (8).** I said: Owner can assign roles, Contributor can't, which prevents self-escalation. **Correction:** both manage all resources; for a pipeline that must assign roles, a narrowly scoped access-management role, not Owner.
      > "Both can manage all resources in their scope; Owner can also assign roles. Contributor can't, so it can't escalate its own access. My pipeline uses Contributor; if it ever needs to assign roles, I'd give it a narrowly scoped access-management role rather than Owner."
   4. **NSG (6).** I said: inbound and outbound rules allowing or denying IPs and ports. **Correction:** explain how it decides: priority 100–4096 set on each rule, lowest first, first match wins (a match = every field fits: direction, protocol, source, destination, port); default rules allow the VNet and deny inbound internet; stateful; on a subnet or NIC.
      > "An NSG is a stateful firewall attached to a subnet or a NIC, with inbound and outbound rules matching source, destination, port and protocol. Rules are checked by priority, lowest number first, and the first match wins. The defaults allow traffic inside the VNet and deny inbound from the internet, so I only add the allows I need, like SSH and the app port in my project."
   5. **Private access to storage (3).** I said: assign a private IP. **Correction:** name it: a private endpoint (a NIC in my subnet that leads only to that storage account) + a private DNS zone so the normal hostname resolves privately + public access disabled. A service endpoint is the simpler alternative, but storage keeps its public IP.
      > "I'd use a private endpoint: a NIC in my subnet with a private IP that represents the storage account. A private DNS zone linked to the VNet makes the normal storage hostname resolve to that private IP, and I disable public network access so it's the only path. A service endpoint is the simpler alternative, but the storage account stays on a public IP."
   6. **VM vs VMSS vs App Service (7).** I said: a VM is one machine, VMSS adds copies, App Service is managed and scales itself, good for beginners. **Correction:** App Service scales only with configured rules, and you pay for the plan; not "for beginners", it's the default for web apps; the axis is how much I manage (patching = OS updates; non-HTTP = workers, other protocols, special OS needs). Containers package the app and share the host's kernel; they run on a VM, a VMSS or a managed platform (AKS nodes are scale sets).
      > "The difference is how much I manage. A VM is one server where I own everything, including patching and availability. A scale set gives identical VMs with autoscale behind a load balancer, but I still own the OS. App Service is PaaS: I deploy code or a container, and Azure handles the OS, TLS and scaling rules. For a web app or API I'd start with App Service, and go to a scale set only if I need OS-level control or a non-HTTP workload."
   7. **Secrets (5).** I said: use Key Vault so nothing is in the code. **Correction:** the app reads Key Vault with its managed identity; in Terraform, secrets come from CI env vars, `sensitive` only hides output, the state still stores them in plain text. To keep them out of the state, Terraform creates the vault and grants access, the secret is set outside Terraform. Best: Entra auth to the database, no password.
      > "Secrets live in Key Vault, and the app reads them with its managed identity, so it has no credentials of its own. In Terraform I never put secrets in code or committed tfvars; I pass them as environment variables from CI secrets, mark them sensitive, and protect the state, because secrets still end up there. Where possible I skip passwords entirely and use Entra authentication to the database with a managed identity."
   8. **Policy vs RBAC (6).** I said: policy is JSON rules like allowed locations; RBAC must be assigned to work. **Correction:** both are assigned to a scope; RBAC controls who does which action, Policy controls what resources may look like, even for an Owner. Effects: deny, audit, modify, deployIfNotExists; compliance on existing resources.
      > "RBAC controls who can perform which actions; Azure Policy controls what resources are allowed to look like, regardless of who creates them, so even an Owner is blocked. Policies are JSON rules assigned to a scope, with effects like deny, audit or modify, and they report compliance on existing resources. In my project a policy allows only `swedencentral`, so a wrong region fails at apply even with full rights."
   9. **Cost control (5).** I said: cost alerts with a daily limit; they don't stop spending and aren't real time. **Correction:** a budget (usually monthly) with forecast alerts. Three layers: see it (budgets, tags), prevent it (restrict expensive SKUs, the size/tier of a resource; Infracost on PRs), reduce it (right-size, autoscale, shut down dev, reservations).
      > "Three layers. Visibility: budgets with forecast alerts and tags so costs are grouped by team and environment. Prevention: policy or validation restricting expensive SKUs, and Infracost on PRs so cost changes are reviewed before merging. Optimization: right-sizing, autoscale, shutting down or destroying non-production when unused, and reservations for steady production load. In my project I restrict VMs to B-series, have a budget alert, and destroy environments when I'm done."
   10. **Secure SSH (5).** I said: port 22 is open and forwarded to the private subnet; close it and go through Azure. **Correction:** the NSG doesn't forward, it allows 22 to the VM's public IP. Name Azure Bastion: HTTPS + Entra sign-in, reaches the private IP, NSG allows 22 only from the Bastion subnet; keys only. Alternatives: JIT, VPN.
       > "I'd use Azure Bastion: the admin connects over HTTPS with Entra sign-in and MFA, and Bastion reaches the VM's private IP, so the VM has no public IP and the NSG allows SSH only from the Bastion subnet. Keys only, no passwords. Alternatives are JIT access, which opens the port briefly for one IP, or a VPN. In my project port 22 is open, which is the gap I'd close this way."

   **To review:** identity (SP vs MI; authentication vs authorization); private networking (private endpoint + DNS, Bastion, NSG evaluation); secrets in the state and the three layers of cost control. **Pattern:** I know the ideas but miss the names (private endpoint, Bastion, budget, SKU). Azure is my weaker area.

   **Session 3, CI/CD and scenarios: 61/100.**

   1. **PR to production (7).** I said: a push triggers the pipeline; validate for both envs, lint for the whole project, plan for both envs posted as a PR comment; the reviewer accepts, the pipeline runs again, the plan is uploaded as an artifact and the apply job applies that exact file; if the plan changes in between, apply fails. **Correction:** name both gates: the ruleset `protect-main` requires a PR and five passing checks (`validate (dev)`, `validate (prod)`, `lint`, `plan (dev)`, `plan (prod)`, the job names) before merging, plus required approvals in a team; after the merge, `apply` pauses for environment approval (Settings → Environments → `dev`, required reviewers, Approve/Reject). The ruleset protects the code, the environment protects the infrastructure. A stale saved plan is refused ("saved plan is stale"), not shown as new changes. Add promotion: dev first, then prod with its own plan and stricter approval.
      > "The PR runs validate and lint, then a plan for dev and prod, posted as a comment. A ruleset blocks the merge until checks pass and a reviewer approves. The merge reruns the pipeline: the plan is saved as an artifact, and the apply job waits for environment approval, then applies exactly that file. If the state changed meanwhile, Terraform rejects the stale plan. After dev is verified, the same change goes to prod with its own plan and a stricter approval."
   2. **Sign in without a secret (9).** I said: OIDC; Azure checks GitHub's token against the federated credential (iss GitHub, sub exact repo + env dev, aud the token exchange) and issues its own short-lived token. **Correction:** add that GitHub stores only IDs, the job needs `id-token: write`, and RBAC limits what the token can do.
      > "I use OIDC federation. The job requests a short-lived token from GitHub, and Entra checks its issuer, subject and audience against a federated credential on the service principal: GitHub, my exact repo and environment, and the Azure token exchange audience. If they match, Entra issues its own short-lived access token. GitHub stores only IDs, no secrets, and RBAC limits what the pipeline can do."
   3. **Apply failed halfway in CI (7).** I said: check the lock, force-unlock if I'm sure, plan again, apply. **Correction:** first read the error and fix the cause (quota, policy, name conflict), or the re-run fails the same way; the state recorded what succeeded, don't edit it; import orphans ("already exists"); re-run through the pipeline. A normal failure releases the lock; it's stuck only if the runner was killed.
      > "First I read the error and fix the cause, like a quota, a policy denial or a name conflict, otherwise a re-run fails the same way. Terraform recorded what succeeded, so the state isn't broken and I don't edit it by hand. If the lock is stuck because the runner was killed, I force-unlock it once I'm sure nothing is running. Then a new plan through the pipeline shows what's left; if something exists in Azure but not in the state, I import it, then apply."
   4. **Manual change in prod during an incident (6).** I said: if legitimate, import, write the code until plan shows no changes, remove the import block. **Correction:** that covers only a new resource. The danger: the next apply reverts the fix, so don't apply first. Find what changed (refresh-only plan, activity log), usually a changed setting → update the code; temporary → apply reverts it later. Prevent: read-only prod access, break-glass, drift check.
      > "First I make sure nobody applies, because the next apply would revert the fix and bring the incident back. I find what changed with a refresh-only plan and the activity log, and talk to whoever made it. If the change should stay, I put it in code through a PR, importing anything created by hand, until plan shows no changes. If it was temporary, apply reverts it after the incident. To prevent it: read-only production access, a break-glass process, and a nightly drift check."
   5. **Five teams, one Azure environment (7).** (Clarified: one tenant/subscription; a platform team owns the shared network, modules and policies; app teams own their apps.) I said: a separate env per team with its own code and state, team-specific RBAC, common setups in modules, temporary access when needed. **Correction:** roots per team per environment; the platform team owns versioned modules that teams consume pinned, no "temporary access"; read shared values with data sources; a service principal per team with scoped RBAC; one reusable workflow; CODEOWNERS; Azure Policy at the management group. Asking what "environment" means is a good move in an interview.
      > "Each team gets its own Terraform roots per environment with separate state, and its own service principal with OIDC, scoped by RBAC to its resource groups. The platform team owns shared infrastructure like the network, and versioned modules that teams consume by pinned version; teams read shared values with data sources rather than touching that code. All teams call one reusable pipeline with the same checks and approvals, CODEOWNERS enforces review per folder, and Azure Policy at the management group enforces common rules."
   6. **Plan wants to recreate a database (5).** I said: find the cause and address it; never recreate a database. **Correction:** give the how: block the apply; read `# forces replacement`; usual causes: provider or module upgrade, manual change, rename without `moved`, a different variable value in CI. Prevent: `prevent_destroy` and backups.
      > "I block the apply and read the plan for the attribute marked 'forces replacement'. Common causes are a provider or module upgrade, a manual change in the portal, a rename without a `moved` block, or a variable with a different value in CI. I fix the cause, pin a version, add a `moved` block or match the code, until the plan shows no replacement. Databases get `prevent_destroy` and backups, so a bad plan can't delete data."
   7. **Testing Terraform (7).** I said: fmt, TFLint, validate, a reviewed plan, deploy to dev and test live, then prod. **Correction:** name Checkov (security); `terraform test` for modules; an automatic smoke test after apply; short-lived PR environments for big changes.
      > "In layers. Static checks on every PR: fmt, validate, TFLint and Checkov for security. Then a reviewed plan. Modules get `terraform test` with assertions. Changes are applied to dev first, with a smoke test hitting the app, and only the same code that worked in dev is promoted to prod, with its own approval."
   8. **A laptop apply broke prod (4).** I said: prod only after dev is tested, with the same code. **Correction:** that doesn't stop the laptop. Remove the path: people get read-only on prod, only the pipeline identity can write resources and the prod state; a break-glass account for emergencies; a blameless review.
      > "I remove the path: engineers get read-only access to production, and only the pipeline's identity can change resources or write to the prod state, so a laptop apply fails. All changes go through a PR, a reviewed plan and an approved apply, promoted from dev. For emergencies there's a monitored break-glass account. And I'd run a blameless review, because the real problem is that the system allowed it."
   9. **A 25-minute pipeline (6).** I said: find the slow step, fix technical issues, sort out reviewer delays. **Correction:** reviewer delay isn't pipeline time. Concrete fixes: parallel jobs, provider caching, plan only changed roots, split large states, heavy scans less often, bigger runners.
      > "First I measure which jobs and steps take the time. Typical fixes: run independent jobs in parallel, cache Terraform providers, plan only the roots whose files changed, and split large states, because refresh time grows with the number of resources. Heavy scans can run less often, and bigger runners help if CPU is the limit. Review delays are a separate, process issue."
   10. **Rollback (3).** I said: restore a previous state version, refresh-only plan, match the code, apply. **Correction:** restoring state doesn't change the real resources, it only makes the record disagree with reality; state versioning is for a corrupted state file. Roll back in git: revert the commit in a PR, review the plan, apply. Deleted data needs backups; recreated resources get new IDs.
       > "I roll back in code, not in state: revert the bad commit in a PR, review the plan that undoes the change, and apply through the pipeline. Restoring an old state file doesn't change the real resources; it only makes the state disagree with them, and state versioning is for recovering a corrupted state file. Some changes can't be reverted, like a deleted database, so data needs backups, and I check anything that depended on recreated resources."

   **To review:** rollback and recovery (git, not state; backups); access to production (read-only for people, only the pipeline writes, break-glass); concrete techniques after the principle. **Pattern:** the right order of thinking (stop, find the cause, fix safely), but too few specifics.

   **All sessions:** Terraform 71, Azure 48, CI/CD 61. Weakest: Azure identity and networking.

   **Session 4, Session 2 retried (Azure): 87/100, up from 48.**

   1. **SP vs MI (8, was 2).** I said: MI only inside Azure, SP for access from outside; SP needs a token, MI authenticates with Entra with no secrets; SP for GitHub Actions, MI for the database. **Correction:** open with "both are identities for applications, not people"; an MI is an SP that Azure manages; an SP needs credentials I manage (secret, certificate or OIDC; mine uses OIDC, so no stored secret).
   2. **RBAC (9, was 1; first retry 6).** I said: who (SP, MI), what (Reader, Contributor, Owner, data roles), where (scope from the management group down, inherited); roles add up, denied when not assigned; my pipeline has Contributor + Storage Blob Data Contributor on the state; narrow scopes. **Correction:** "who" also includes users and groups; in a team, assign roles to groups. The first retry ("who can do what and where") was too short: say what each part is, with an example.
   3. **Contributor vs Owner (9, was 8).** **Correction:** "both can manage all resources", not "full access"; name User Access Administrator.
   4. **NSG (9, was 6).** I said: a firewall on a subnet or NIC; rules by priority, lowest first, first match wins; inbound denied by default; allow 22 for SSH; inbound allows the replies. **Correction:** denied by default from the internet, the VNet is allowed; stateful means replies pass, not new outbound connections.
   5. **Private access to storage (9, was 3).** I said: private endpoint (a NIC with a private IP representing the account), private DNS, public access closed. **Correction:** compare with a service endpoint (simpler, but storage keeps its public IP).
   6. **VM vs VMSS vs App Service (9, was 7).** I said: a VM = full control (OS, patches); VMSS = identical VMs with autoscale, still OS control; App Service = PaaS, Azure handles OS, TLS, scaling; App Service for web/API, VMSS for OS control or non-HTTP. **Correction:** I configure the scaling rules, Azure runs them; one VM is a single point of failure; VMSS sits behind a load balancer.
   7. **Secrets (7, was 5).** I said: Key Vault + managed identity so Terraform holds no secrets; passed as env vars, sensitive, the state protected because they end up there; best, Entra auth. **Correction:** those contradict; separate the cases: Terraform passes the secret → it's in the state; Terraform creates only the vault and access → not in the state; Entra auth → nothing to store.
      > "The app reads secrets from Key Vault with its managed identity, so it has no credentials of its own. Where Terraform must pass a secret, it comes from CI as an environment variable, marked sensitive, and since it still ends up in the state, the state is locked down. Better, Terraform creates only the vault and the access, and the secret is set outside it. Best, there's no password: Entra auth to the database with a managed identity."
   8. **Policy vs RBAC (9, was 6).** **Correction:** state the contrast in one line (RBAC = who does which actions; Policy = what resources may look like); Policy reports compliance on existing resources.
   9. **Cost control (9, was 5).** **Correction:** add reservations or savings plans for steady production load.
   10. **Secure SSH (9, was 5).** **Correction:** normal SSH keys aren't short-lived; say "keys only", or name Entra ID SSH login (short-lived certificates).

   **What changed:** I now use the names (private endpoint, Bastion, budget, SKU) and finish with my project. **Left:** secrets, separating the cases.

   **Step 4 done.**
5. **Terraform Associate 004** (tests Terraform 1.12; [objectives](https://developer.hashicorp.com/certifications/terraform-associate), [content list](https://developer.hashicorp.com/terraform/tutorials/certification-004/associate-review-004)) mapped to my weeks:

   | Domain | Weeks | Status |
   |---|---|---|
   | 1. IaC (what, advantages, multi-cloud/service-agnostic) | 2, 10 | ✅, 1c light |
   | 2. Fundamentals (providers, versions, `alias`, state) | 2, 3 | ✅ |
   | 3. Core workflow (init, validate, plan, apply, destroy, fmt) | 2, 9 | ✅ |
   | 4. Configuration (resource/data, references, variables/outputs, complex types, expressions, dependencies, custom conditions, sensitive data) | 2, 5, 8 | ✅, Vault is a gap |
   | 5. Modules (sources, variable scope, use, versions) | 6 | ✅ |
   | 6. State (local backend, locking, remote backend, drift) | 3, 9 | ✅, local backend light |
   | 7. Maintain (import, CLI state inspection, verbose logging) | 3 | ⚠️ no `TF_LOG` |
   | 8. HCP Terraform (runs, collaboration and governance, workspaces and projects, VCS integration) | 10 (one Q/A) | ❌ biggest gap |

   **Gaps and plan:** HCP Terraform (a concepts session); `TF_LOG`/`TF_LOG_PATH`; the Vault provider (reads secrets, which still land in the state); skim the local backend and the multi-cloud argument. Then a practice test.
6.
7.
