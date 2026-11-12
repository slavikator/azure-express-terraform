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

1. Public. After Practice 08 there are no secrets in the repo or in CI: login is OIDC, and the GitHub secrets hold only IDs and the SSH public key. Checked before: no `terraform.tfvars`, state, `.terraform` or key files in the git history; my email lives only in the gitignored `tfvars`. Public gives environment reviewers and rulesets for free.
2. Unexpected behaviour and errors: CI could run a newer version that isn't stable or drops something we use. **Correction:** the concrete risks are the state and the saved plan. A newer version can upgrade the state format, and an older one then can't read it; a saved plan can only be applied by the exact same version. Fixed by pinning 1.16.4 in CI, `required_version = ">= 1.16.0"` in the roots, and committing `.terraform.lock.hcl` for provider versions.
3. Apply must use the plan that was generated and reviewed; if something changed between the jobs, a new plan would differ. If someone applied in between, apply detects it and stops. **Correction:** the exact error is "Saved plan is stale": the state changed since the plan was made, so Terraform refuses and you plan again.
4. A cancelled apply could do only part of its job. **Correction:** more precisely, it can leave resources created in Azure but not recorded in state, half-configured resources, and a held state lock (`force-unlock`). That's why apply is never cancelled; a second run waits in the `concurrency` group instead.
5. The reviewer sees the exact plan as a PR comment, one per environment (two comments). It's computed by CI from the PR code against the real state, not from someone's laptop. **Correction:** the PR comment is not the plan that gets applied. After the merge, the `main` run makes a fresh plan, and that one is applied. The approver should check the `main` plan before approving.
6. Approval protects against auto-applying without review by a responsible person. **Correction (model answer):** the job with `environment: dev` presents the OIDC subject `...:environment:dev` instead of `...:ref:refs/heads/main`. The federated credential `github-env-dev` matches only that subject, and GitHub issues it only to a job that passed the environment rules (required reviewer, deployment branch `main`). So a job on another branch, or one without the environment, can't get the Azure token for apply.
7. **Model answer** (I didn't answer myself): `CKV_AZURE_119` (NIC with a public IP: the VM is reachable from the internet), suppressed with a reason, Bastion later. `CKV_TF_1` (module source not pinned to a commit SHA: a git tag can be moved to other code), suppressed, own repo and tag v1.0.0. Also suppressed: `CKV_AZURE_50` (VM extensions allowed) and `CKV2_AZURE_31` (mgmt subnet without NSG). 20 findings in `labs/` skipped by path (`skip_path: labs`).
8. `-refresh-only` checks for changes in Azure compared with the state; a normal plan also reports differences between the code and the state (unapplied code), which isn't drift. **Correction:** I didn't answer `-lock=false`. The drift job only reads, so it doesn't need the lock, and it must never block a real apply with "state locked". The cost is a possible read during an apply, which is acceptable for a report.
9. Two options: accept the change or remove it from Azure. **Correction:** if the change is legitimate, add it to the **code** (e.g. tags in `locals.tf`), not to the state; a refresh-only apply would record it in state, but the next normal plan would remove it again. `import` is for whole resources, not attributes. Decide by who made it and why (Activity log): a legitimate hotfix goes into code; an accidental or unauthorized change is reverted with `apply`. Third option: `lifecycle { ignore_changes = [...] }` when something outside Terraform owns the attribute.
10. Direct push to `main` was rejected (GH013): changes only through a PR, and 5 of 5 required status checks expected. **Correction:** together with the environment: the ruleset guards what gets into `main` (PR, required checks, in a team also an approval); the environment guards what gets applied from `main` (required reviewer, branch rule, OIDC subject). Either alone has a gap. Gap in my setup: only `dev` has an environment; prod would get its own, with stricter reviewers.
11. Built in parts with corrections (merging is a push to `main` that re-runs everything, the approval gate, drift). Final version:

    > It starts when I open a pull request into main; every push to that branch reruns it. The PR run validates each environment and lints the whole repo with fmt, tflint and checkov, in parallel. If both pass, it plans each environment against real Azure using OIDC, with no stored secrets, and posts the plan as a PR comment for the reviewer. Main is protected by a ruleset: changes only via PR, and the five required checks must pass before merge. Merging is a push to main, which re-runs the checks and creates a fresh plan from main, saved as an artifact. The apply job targets the dev environment, so it waits for a required reviewer. After approval, it authenticates with OIDC as environment:dev, downloads that exact plan and applies it, so what was approved is exactly what gets applied. Concurrency prevents two applies at once. Separately, a nightly drift job runs a refresh-only plan and fails if Azure no longer matches the state.

    ```mermaid
    flowchart TD
        dev(["Push to feature branch"]) --> pr["Open PR into main"]

        subgraph PRRUN["PR run (pull_request)"]
            v1["validate (dev, prod)<br/>init -backend=false, validate"]
            l1["lint<br/>fmt, tflint, checkov"]
            p1["plan (dev, prod)<br/>OIDC subject pull_request"]
            c1["Plan posted as PR comment"]
            v1 --> p1
            l1 --> p1
            p1 --> c1
        end

        pr --> v1
        pr --> l1
        c1 --> gate1{"Ruleset protect-main<br/>PR only + 5 required checks"}
        gate1 -- merge --> push["Push to main"]

        subgraph MAINRUN["Main run (push)"]
            v2["validate + lint"]
            p2["plan (dev, prod)<br/>OIDC subject ref:refs/heads/main"]
            art[("tfplan artifact")]
            gate2{"Environment dev<br/>required reviewer, branch main"}
            ap["apply (dev)<br/>OIDC subject environment:dev<br/>apply tfplan, concurrency group"]
            v2 --> p2 --> art --> gate2
            gate2 -- approved --> ap
        end

        push --> v2
        ap --> azure[("Azure resources<br/>state in Storage, Entra auth, blob lease lock")]

        subgraph DRIFT["Nightly drift (schedule 06:00 UTC, manual)"]
            d1["plan -refresh-only<br/>-detailed-exitcode -lock=false"]
            d2{"exit code 2?"}
            d1 --> d2
        end

        azure -.-> d1
        d2 -- yes --> red["Run fails: drift found"]
    ```

12. Security checks in lint, shutting down dev overnight and on weekends, budget alerts. **Correction:** checkov already is the security scan, and budget alerts already exist (and are reactive). Shutting down dev counts if tied to the pipeline (a scheduled destroy/apply, or an auto-shutdown schedule in Terraform). Stronger answers: Infracost cost diff in the PR; separate plan (read-only) and apply (write, behind approval) identities; a `prod` environment with its own reviewers and federated credential; notifications when apply fails or drift is found; policy checks on the plan JSON and SHA-pinned actions.

## Summary

- **Pipeline shape:** `validate` (matrix per env: `init -backend=false`, `validate`) and `lint` (whole repo once: `fmt -check -recursive`, tflint, checkov) run in parallel; `plan` has `needs: [validate, lint]`; `apply` runs only on push to `main`. Each job is a fresh runner: checkout + pinned `setup-terraform` every time. Only artifacts pass data between jobs.
- **Triggers:** `pull_request` into `main` (opened + every push to the branch, tests a merge commit, no secrets for forks); `push` to `main` = the merge; `workflow_dispatch` = manual (button, `gh workflow run`, API), runs checks and plan but no apply. `schedule` runs only from the default branch.
- **Saved plan:** `plan -out=tfplan` → artifact → `apply tfplan` in the same exact Terraform version. A state change in between gives "Saved plan is stale". The PR comment is for code review; the `main` run's plan is the one applied.
- **Gates:** ruleset `protect-main` (PR only, 5 required checks, no force push or delete); renaming a required job means updating the ruleset, or PRs wait forever for the old name. Environment `dev` (required reviewer, branch `main`) + OIDC subject `environment:dev`. `concurrency` with `cancel-in-progress: false` for apply.
- **Permissions:** top-level `contents: read`; job-level `permissions` replace it entirely. `id-token: write` only in `plan`/`apply` (request the OIDC token); `pull-requests: write` only in `plan`.
- **YAML gotchas:** `defaults.run.working-directory` affects only `run:` steps (paths in `uses:` start at `$GITHUB_WORKSPACE`); a step-level `working-directory` overrides it; `matrix` context only inside jobs; no dotted keys in YAML.
- **Linting:** tflint `# tflint-ignore:` directly above the line; checkov `#checkov:skip=ID:reason` inside the block; `skip_path` for labs. Contributor can't write `Microsoft.Authorization/*` (policy assignments need Resource Policy Contributor).
- **Drift:** `plan -refresh-only -detailed-exitcode -lock=false` (0 = none, 1 = error, 2 = drift). `setup-terraform`'s wrapper treats exit 2 as success, so `terraform_wrapper: false`. Resolve drift in code or revert it with apply. Partial state (`-target`, unknown outputs) keeps it red regardless.
- **Logs and secrets:** masking hides only exact secret values; `-no-color` for anything written to files or PR comments.
