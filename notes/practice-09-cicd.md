# Week 9 practice: "A pipeline worth showing"

**Goal:** turn the current single-job workflow into a pipeline you'd present in an interview: checks on every PR with the plan posted as a comment, a saved plan applied after approval, protection against parallel applies, linting and security scanning, and nightly drift detection.

**Topics:** pipeline structure, saved plan files and artifacts, PR comments, GitHub environments, concurrency, tflint, checkov, drift detection, branch protection.

**Time:** 3 hours, can be split into two sessions. **Cost:** practically zero: the pipeline mostly plans; one apply at the end.

**Notes:** [`09-cicd-terraform.md`](09-cicd-terraform.md)

**Prerequisite:** practice 08, Step 1 (CI uses OIDC). If CI still uses a client secret, everything here works too, just less securely.

---

## Rules for this practice

1. **Work on a branch and through pull requests** from Step 2 on: that's the workflow you're building.
2. **Read every CI log you trigger.** The goal is to understand each step, not just to get green checks.
3. **"Your main root"** means the repo root, or `envs/dev` (and `envs/prod`) if you've done practice 06. With several environments, use a matrix as in practice 06, Step 5.

---

## Step 0. A decision about your private repository

Your repository is **private**. On the free GitHub plan, two features this practice uses are restricted in private repositories: **environment protection rules** (required reviewers) and **branch protection**. Check what your account allows: repo → **Settings → Environments** and **Settings → Branches**.

Options:

| Option | Trade-off |
|---|---|
| Make the repository **public** | everything works for free. Your git history contains no `tfvars`, state or key files (checked), and secrets live in GitHub Secrets. Still, review the repo before doing it |
| A paid plan (GitHub Pro) | everything works, at a monthly cost |
| Stay private and free | skip required reviewers and branch protection; keep `apply` behind a manual `workflow_dispatch` instead |

> ❓ **1.** Which option did you choose, and why? If you went public, what did you check before doing it?

---

## Step 1. Align the Terraform version

The workflow pins `terraform_version: 1.8.0`, but you work locally with a much newer version.

```
terraform version
grep -n terraform_version .github/workflows/deploy.yml
```

Set the workflow to your local version, and add `required_version` to the `terraform` block so mismatches fail clearly.

> ❓ **2.** What can go wrong when CI and your laptop use different Terraform versions against the same state?

---

## Step 2. Split the workflow: checks, plan, apply

Rewrite `.github/workflows/deploy.yml` into three jobs:

| Job | Runs on | Steps |
|---|---|---|
| `checks` | every push and PR | `terraform fmt -check -recursive`, `init -backend=false`, `validate` |
| `plan` | every push and PR, `needs: checks` | `init`, `plan -out=tfplan -input=false`, `terraform show -no-color tfplan > plan.txt`, upload `tfplan` as an artifact (`retention-days: 1`) |
| `apply` | only on push to `main`, `needs: plan` | `init`, download the artifact, `apply -input=false tfplan` |

Also:

- `-input=false` on every command that could prompt;
- a `concurrency` group on the `apply` job, with `cancel-in-progress: false`;
- the `apply` job uses `environment: production` (if you have environments, Step 0), or `if: github.event_name == 'workflow_dispatch'` (if you don't).

> ❓ **3.** Why does `apply` use the downloaded `tfplan` instead of planning again? What happens if someone applied something else between the plan and the apply?
>
> ❓ **4.** Why `cancel-in-progress: false` for apply? What could a cancelled apply leave behind?

---

## Step 3. The plan as a PR comment

Add a step to the `plan` job that runs only for pull requests and posts `plan.txt` as a comment, e.g. with `gh pr comment ${{ github.event.pull_request.number }} --body-file plan.txt` (the job needs `pull-requests: write` permission, and `GH_TOKEN: ${{ github.token }}`).

Open a PR that changes one tag in `locals.tf`, and look at the comment.

> ❓ **5.** What does the reviewer see, and why is this better than "trust me, I ran plan locally"?

---

## Step 4. Approval before apply

If you have environments (Step 0): create `production` with yourself as a **required reviewer** and **`main` as the only deployment branch**.

If you switched CI to OIDC with environments, the job's token subject changes. Add a federated credential for `repo:slavikator/azure-express-terraform:environment:production`.

Merge the PR from Step 3, and watch the `apply` job wait for your approval. Approve it.

> ❓ **6.** What exactly does the approval protect against? What does `environment:production` change in the OIDC subject, and why is that safer?

---

## Step 5. tflint and checkov

Add to the `checks` job:

- **tflint** with the azurerm ruleset (`terraform-linters/setup-tflint`, then `tflint --init` and `tflint --recursive`, with a `.tflint.hcl` enabling the `azurerm` plugin);
- **checkov** on the Terraform code (e.g. `bridgecrewio/checkov-action`, `framework: terraform`).

Run it on a PR and read the findings. Fix what's reasonable. For findings you accept on purpose (e.g. SSH open in a learning project), suppress them **with a reason** in the code:

```hcl
#checkov:skip=CKV_AZURE_10:SSH open for the learning project, replaced by Bastion later
```

> ❓ **7.** Name two findings checkov reported, what risk each describes, and whether you fixed or suppressed them.

---

## Step 6. Nightly drift detection

Add a second workflow, `.github/workflows/drift.yml`:

- `on: schedule` with `cron: "0 6 * * *"`, plus `workflow_dispatch`;
- `init`, then `plan -refresh-only -detailed-exitcode -input=false -lock=false`;
- the job fails when the exit code is 2.

Test it: change a tag on your resource group in the Portal, then run the workflow by hand (`gh workflow run drift.yml`).

> ❓ **8.** Why `-refresh-only` here, and why `-lock=false`? What would a normal `plan` also report that isn't drift?
>
> ❓ **9.** The drift job found your tag change. What are your two options to resolve it, and how do you decide?

Restore the tag (`terraform apply`), and check that the next drift run is green.

---

## Step 7. Branch protection

If available (Step 0), protect `main`: require a pull request, and require the `checks` and `plan` status checks to pass. Then try to push directly to `main`.

> ❓ **10.** What happened? How do branch protection and the production environment together form the path "nobody changes production without review"?

---

## Step 8. Present it

Draw the final pipeline (on paper or with Mermaid in your notes), from `git push` on a branch to `apply` in Azure, with every check and gate.

> ❓ **11.** Walk through the diagram in two minutes, as you would in an interview.
>
> ❓ **12.** What would you still add for a real team? Name three things (hint: cost estimates, plan/apply identities, notifications, policy checks on the plan JSON).

---

## Outcome

After this practice you should be able to, without looking:

- structure a Terraform pipeline into checks, plan and apply jobs;
- explain why apply uses a saved plan and how stale plans are rejected;
- gate production with environment approvals and branch protection;
- run tflint and checkov, and handle findings deliberately;
- detect drift on a schedule without interfering with real applies.

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
