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

Your notes have seven stories (STAR format): the CI hang on `init`, the state/Azure mismatch, the provider without an upper bound, CI recreating the VM, the double Ctrl+C, the quotas and partial applies, and the `count` trap.

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

1.
2.
3.
4.
5.
6.
7.
