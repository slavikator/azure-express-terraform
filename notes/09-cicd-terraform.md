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

## Check yourself

Rebuild your workflow: `plan` on PR with a comment, `apply` after merge with approval through the `production` environment, the plan as an artifact, `concurrency`, `tflint` and `checkov`. Add daily drift detection.

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
