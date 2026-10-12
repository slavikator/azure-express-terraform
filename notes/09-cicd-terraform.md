# Тиждень 9. CI/CD для Terraform

Пайплайн, який не страшно показати на співбесіді.

## Терміни

| Абревіатура / термін | Розшифровка | Що це, одним реченням |
|---|---|---|
| **CI** | Continuous Integration | Автоматична перевірка кожної зміни: формат, валідація, план |
| **CD** | Continuous Delivery / Deployment | Автоматичне застосування змін (Delivery — з ручним підтвердженням, Deployment — без) |
| **PR** | Pull Request | Запит на злиття гілки, місце для review |
| **GitOps** | | Git як єдине джерело правди: усе змінюється лише через merge |
| **Plan file** | | Збережений план (`plan -out`), який `apply` виконає без змін |
| **Environment** | GitHub environment | Захищене середовище з правилами: reviewers, секрети, гілки |
| **Drift detection** | | Регулярна перевірка, чи не змінили інфраструктуру поза Terraform |
| **SAST** | Static Application Security Testing | Статичний аналіз коду на вразливості (checkov, trivy) |

## Поняття, які треба вміти пояснити своїми словами

### 1. Типовий процес

```
гілка → PR → CI: fmt, validate, lint, security scan, plan → коментар з планом у PR
       → review → merge у main → CD: plan -out → підтвердження → apply цього плану
```

- На PR **ніколи** не робиться `apply`.
- Після merge застосовують саме той план, який переглянули.

### 2. Чому `plan -out`

Без збереженого плану `apply` будує план заново. Якщо між review і apply хтось змінив інфраструктуру або вийшла нова версія провайдера, застосується **не те**, що переглядали.

```
terraform plan -out=tfplan -input=false
terraform show -no-color tfplan > plan.txt    # для коментаря в PR
terraform apply -input=false tfplan            # без -auto-approve, план уже затверджено
```

Файл плану містить секрети, тому зберігайте його як artifact з коротким строком життя.

### 3. Exit-коди для автоматизації

`terraform plan -detailed-exitcode`:

| Код | Значення |
|---|---|
| `0` | змін немає |
| `1` | помилка |
| `2` | є зміни |

Так будують drift detection: щоночі запуск `plan`, код `2` означає, що інфраструктуру змінили поза Terraform.

### 4. Захист від паралельних запусків

Два одночасні `apply` впруться в state lock, і один упаде. Краще, щоб вони взагалі не запускалися одночасно:

```yaml
concurrency:
  group: terraform-prod
  cancel-in-progress: false    # не переривати apply посередині
```

### 5. GitHub environments

- **Required reviewers:** job чекає, поки хтось натисне Approve.
- **Deployment branches:** apply в prod лише з `main`.
- **Секрети середовища:** окремі облікові дані для dev і prod.
- OIDC subject можна прив'язати до environment: `repo:<owner>/<repo>:environment:production`.

### 6. Перевірки в CI

| Інструмент | Що перевіряє |
|---|---|
| `terraform fmt -check` | форматування |
| `terraform validate` | синтаксис і типи |
| **tflint** | помилки, які пропускає validate: неіснуючі розміри VM, застарілі аргументи, стиль |
| **checkov** / **trivy** | безпека: відкриті порти, публічні storage, вимкнене шифрування |
| **Infracost** | вартість змін у PR |
| `terraform test` | тести модулів (Terraform 1.6+) |

### 7. Приклад workflow

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
    environment: production          # тут чекає на підтвердження
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

### 8. Уроки з мого проєкту

| Що сталося | Чому | Як запобігти |
|---|---|---|
| CI висів на `init` | порожній блок `backend`, Terraform чекав вводу | `-input=false` на всіх командах |
| Пуш конспекту підняв VM після `destroy` | `apply` при кожному пуші в main | `apply` лише вручну або через environment з підтвердженням; `paths` фільтр |
| Apply впав посередині (баг провайдера) | провайдер без верхньої межі версії | фіксувати версії, комітити lock-файл |

Якщо apply впав посередині: не панікувати, запустити `plan`. Terraform записує в стейт усе, що встиг створити, і план покаже, що лишилося.

### 9. Azure DevOps Pipelines

На Azure-позиціях часто питають і про нього.

| Azure DevOps | GitHub Actions |
|---|---|
| Pipeline (`azure-pipelines.yml`) | Workflow (`.github/workflows/*.yml`) |
| Stage → Job → Step | Job → Step |
| Service connection | Секрети або OIDC + `azure/login` |
| Variable group, Library | Secrets, Variables |
| Environment з approvals | Environment з required reviewers |
| Agent pool (Microsoft-hosted / self-hosted) | Runner (GitHub-hosted / self-hosted) |

Service connection в Azure DevOps теж підтримує workload identity federation, без секретів.

## Команди напам'ять

```
terraform plan -out=tfplan -input=false
terraform show -no-color tfplan
terraform apply -input=false tfplan
terraform plan -detailed-exitcode
gh workflow run deploy.yml
gh run watch
gh run view --log-failed
```

## Перевірка себе

Перебудуйте свій workflow: `plan` на PR з коментарем, `apply` після merge з підтвердженням через environment `production`, артефакт з планом, `concurrency`, `tflint` і `checkov`. Додайте щоденний drift detection.

## Питання співбесіди

- Як виглядає ваш процес змін інфраструктури від гілки до prod?
- Чому apply має застосовувати збережений план, а не новий?
- Як уникнути двох одночасних apply?
- Apply впав посередині. Що робити?
- Як виявляти drift?
- Які перевірки ви запускаєте в CI для Terraform?
- Як GitHub Actions автентифікується в Azure без пароля?
- GitHub Actions чи Azure DevOps: що знаєте про обидва?
- Як розділити права для plan і apply?
