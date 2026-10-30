# Week 9. CI/CD for Terraform

A pipeline you're not afraid to show in an interview.

## Terms

| Abbreviation / term | Stands for | What it is, in one sentence |
|---|---|---|
| **CI** | Continuous Integration | An automatic check of every change: format, validation, plan |
| **CD** | Continuous Delivery / Deployment | Automatically applying changes (Delivery with manual approval, Deployment without) |
| **PR** | Pull Request | A request to merge a branch, the place for review |
| **GitOps** | | Git as the single source of truth: everything changes only through a merge |
| **Plan file** | | A saved plan (`plan -out`) that `apply` executes unchanged |
| **Environment** | GitHub environment | A protected environment with rules: reviewers, secrets, branches |
| **Drift detection** | | A regular check of whether the infrastructure was changed outside Terraform |
| **SAST** | Static Application Security Testing | Static analysis of code for vulnerabilities (checkov, trivy) |

## Concepts you need to explain in your own words

### 1. A typical process

```
branch → PR → CI: fmt, validate, lint, security scan, plan → comment with the plan on the PR
       → review → merge into main → CD: plan -out → approval → apply that plan
```

- A PR **never** runs `apply`.
- After merge, you apply exactly the plan that was reviewed.

### 2. Why `plan -out`

Without a saved plan, `apply` builds the plan again. If someone changed the infrastructure, or a new provider version came out between review and apply, it will apply **something other** than what was reviewed.

```
terraform plan -out=tfplan -input=false
terraform show -no-color tfplan > plan.txt    # for the PR comment
terraform apply -input=false tfplan            # no -auto-approve; the plan is already approved
```

The plan file contains secrets, so store it as an artifact with a short retention period.

### 3. Exit codes for automation

`terraform plan -detailed-exitcode`:

| Code | Meaning |
|---|---|
| `0` | no changes |
| `1` | error |
| `2` | there are changes |

This is how drift detection is built: run `plan` every night; code `2` means the infrastructure was changed outside Terraform.

### 4. Preventing parallel runs

Two simultaneous `apply` runs will hit the state lock, and one will fail. It's better if they never run at the same time:

```yaml
concurrency:
  group: terraform-prod
  cancel-in-progress: false    # don't interrupt an apply halfway
```

### 5. GitHub environments

- **Required reviewers:** the job waits until someone clicks Approve.
- **Deployment branches:** apply to prod only from `main`.
- **Environment secrets:** separate credentials for dev and prod.
- The OIDC subject can be tied to an environment: `repo:<owner>/<repo>:environment:production`.

### 6. Checks in CI

| Tool | What it checks |
|---|---|
| `terraform fmt -check` | formatting |
| `terraform validate` | syntax and types |
| **tflint** | errors validate misses: nonexistent VM sizes, deprecated arguments, style |
| **checkov** / **trivy** | security: open ports, public storage, disabled encryption |
| **Infracost** | the cost of changes in the PR |
| `terraform test` | module tests (Terraform 1.6+) |

### 7. Example workflow

```yaml
name: terraform

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read
  pull-requests: write

env:
  ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  ARM_USE_OIDC: true

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init -input=false
      - run: terraform fmt -check
      - run: terraform validate
      - run: terraform plan -input=false -out=tfplan
      - uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: tfplan
          retention-days: 1

  apply:
    needs: plan
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production          # waits for approval here
    concurrency:
      group: terraform-prod
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init -input=false
      - uses: actions/download-artifact@v4
        with:
          name: tfplan
      - run: terraform apply -input=false tfplan
```

### 8. Lessons from my project

| What happened | Why | How to prevent it |
|---|---|---|
| CI hung on `init` | an empty `backend` block; Terraform waited for input | `-input=false` on every command |
| Pushing notes brought the VM back after `destroy` | `apply` on every push to main | `apply` only manually or through an environment with approval; a `paths` filter |
| Apply failed halfway (a provider bug) | a provider with no upper version bound | pin versions, commit the lock file |

If an apply fails halfway: don't panic, run `plan`. Terraform writes everything it managed to create to the state, and the plan shows what's left.

### 9. Azure DevOps Pipelines

Azure roles often ask about it too.

| Azure DevOps | GitHub Actions |
|---|---|
| Pipeline (`azure-pipelines.yml`) | Workflow (`.github/workflows/*.yml`) |
| Stage → Job → Step | Job → Step |
| Service connection | Secrets, or OIDC + `azure/login` |
| Variable group, Library | Secrets, Variables |
| Environment with approvals | Environment with required reviewers |
| Agent pool (Microsoft-hosted / self-hosted) | Runner (GitHub-hosted / self-hosted) |

A service connection in Azure DevOps also supports workload identity federation, with no secrets.

## Commands to know by heart

```
terraform plan -out=tfplan -input=false
terraform show -no-color tfplan
terraform apply -input=false tfplan
terraform plan -detailed-exitcode
gh workflow run deploy.yml
gh run watch
gh run view --log-failed
```

## Going deeper

### 10. CI in practice

**Continuous Integration:** small changes merged into `main` frequently, every push and PR checked automatically, fast feedback, `main` always green, merges gated by **branch protection** (required status checks). A pipeline has **triggers** (`on:`), **runners** (fresh VMs per job), **jobs** and **steps**, **secrets**, **artifacts**, and a status on the commit or PR.

**Continuous delivery** keeps every change deployable behind an approval; **continuous deployment** applies automatically. My pipeline today: CI on push and PR (`fmt`, `plan`), apply only on manual `workflow_dispatch`: continuous delivery with a manual trigger.

### 11. GitOps

Git is the single source of truth, and an automated process keeps the environment matching it. The four principles: **declarative**, **versioned in Git**, **pulled automatically**, **continuously reconciled**.

| | Push (classic CI/CD) | Pull (GitOps) |
|---|---|---|
| Who applies | the pipeline, holding production credentials | an agent **inside** the environment (Argo CD, Flux) |
| Drift | stays until the next apply | reverted automatically within minutes |

- Rollback = `git revert`; every change has an author and a review.
- Secrets can't be in Git in plain text: SOPS, Sealed Secrets, External Secrets with Key Vault.
- Most natural with Kubernetes (AKS has a built-in Flux extension). For Terraform: PR-driven workflows (Atlantis, HCP Terraform), plan on PR and apply on merge, plus drift detection.

### 12. Scheduled drift detection

A job on a schedule (`on: schedule: - cron: "0 6 * * *"`, always UTC, only from the default branch) runs:

```
terraform plan -refresh-only -detailed-exitcode -input=false -lock=false
```

- Exit `0` = no drift, `1` = error, `2` = differences → the job fails and alerts (email, Slack, or an auto-created issue).
- **`-refresh-only`** reports only changes made outside Terraform; a normal plan also flags merged-but-unapplied code.
- **`-lock=false`** and a **read-only identity** (Reader + state read): the job must not block or change anything.
- It can't see resources created outside Terraform (not in the state): add **activity log alerts** for writes by anyone except the pipeline's identity.
- Avoid noise (computed attributes, Modify policies) with `ignore_changes`, or alerts get ignored.

### 13. The plan file in detail

`plan -out=tfplan` saves the planned changes, the configuration, **variable values**, the prior state snapshot and provider versions in a binary file. `apply tfplan` executes exactly that, without re-planning or prompting.

- If the state changed since the plan: `Saved plan is stale`. Different Terraform or provider versions, or a different `init`: refused.
- **It contains secrets in plain text:** never commit it; store it as a short-lived artifact.
- `terraform show -json tfplan` feeds policy checks (OPA, checkov), cost estimates (Infracost) and PR comments.

### 14. GitHub environments in detail

A named target (`dev`, `production`) that a job declares with `environment:`.

- **Protection rules:** required reviewers (the job pauses until approved), prevent self-review, a wait timer, deployment branches/tags (only `main` may deploy to prod).
- **Environment secrets and variables:** available only to jobs for that environment, after the rules pass. Separate credentials per environment.
- **Deployment history:** what was deployed where, when, by whom.
- **OIDC:** the subject becomes `repo:<owner>/<repo>:environment:production`, so the federated credential trusts only jobs that passed the protections.
- ⚠️ In **private** repositories, protection rules and environment secrets need a paid GitHub plan; public repositories get them for free.

## Check yourself

Rebuild your workflow: `plan` on PR with a comment, `apply` after merge with approval through the `production` environment, the plan as an artifact, `concurrency`, `tflint` and `checkov`. Add daily drift detection. The hands-on exercise is in [`practice-09-cicd.md`](practice-09-cicd.md).

## Interview answers

**What is CI?**
> Continuous Integration means merging small changes into the main branch frequently, with a pipeline that checks every push and pull request automatically, so problems are caught within minutes and main stays releasable. For Terraform it runs `fmt -check`, `validate`, tflint, a security scanner like checkov, and a `plan` posted to the PR. Continuous delivery keeps every change deployable behind an approval; continuous deployment applies automatically.

**What is GitOps?**
> Git is the single source of truth for the desired state. Everything is declared and changed through pull requests, and an agent like Argo CD or Flux inside the environment pulls from Git and continuously reconciles reality, so drift is reverted and CI needs no production credentials. Rollback is a `git revert`. For Terraform, the equivalent is plan on PR, apply on merge, plus scheduled drift detection; the main challenge is secrets, handled with SOPS or External Secrets.

**How do you detect drift?**
> A scheduled CI job runs `terraform plan -refresh-only -detailed-exitcode`, which exits with 2 when something changed outside Terraform, so the job fails and alerts. It runs read-only, with a Reader identity and `-lock=false`. When drift is found, I check the activity log for who made the change, then either reapply the code or update the code to match. Resources created outside Terraform aren't in the state, so I add activity log alerts for manual changes.

**Why apply a saved plan?**
> `plan -out` saves exactly what was reviewed, and `apply tfplan` executes only that; if the state changed in between, Terraform rejects the stale plan. The file contains secrets, so it's a short-lived artifact, never committed. Its JSON form feeds policy and cost checks.

**What are GitHub environments for?**
> A named deployment target with protection rules (required reviewers, prevent self-review, allowed branches) and environment-scoped secrets available only after those rules pass. The apply job targets `production`, so it waits for approval before applying the saved plan. With OIDC, the subject becomes `environment:production`, so Azure only trusts jobs that passed those protections.

## Interview questions

- What does your process for infrastructure changes look like, from branch to prod?
- Why should apply use the saved plan rather than a new one?
- How do you prevent two applies running at the same time?
- Apply failed halfway. What do you do?
- How do you detect drift?
- Which checks do you run in CI for Terraform?
- How does GitHub Actions authenticate to Azure without a password?
- GitHub Actions or Azure DevOps: what do you know about both?
- How do you split permissions between plan and apply?
- What is GitOps, and how is it different from push-based CI/CD?
- How do you detect drift on a schedule without blocking real applies?
- What does a saved plan file contain, and how do you store it?
- What do GitHub environments give you?
