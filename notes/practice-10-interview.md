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
3.
4.
5.
6.
7.
