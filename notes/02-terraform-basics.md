# Тиждень 2. Основи Terraform

Як писати конфігурацію: ресурси, змінні, залежності, версії провайдерів.

## Терміни

| Термін | Що це, одним реченням |
|---|---|
| **IaC** | Infrastructure as Code: інфраструктура описана в коді, а не створена руками |
| **HCL** | HashiCorp Configuration Language, мова файлів `.tf` |
| **Provider** | Плагін, який перекладає ресурси Terraform у виклики API (тут `azurerm`) |
| **Resource** | Об'єкт, яким Terraform керує: створює, змінює, видаляє |
| **Data source** | Читання існуючого об'єкта, яким Terraform не керує |
| **Variable** | Вхідний параметр конфігурації |
| **Local** | Обчислене значення для повторного використання всередині конфігурації |
| **Output** | Значення, яке конфігурація віддає назовні |
| **Lock file** | `.terraform.lock.hcl`, фіксує точні версії провайдерів і їхні хеші |
| **Declarative** | Ви описуєте бажаний результат, а не кроки. Terraform сам вирішує, що зробити |

## Поняття, які треба вміти пояснити своїми словами

### 1. Цикл роботи

```
init  →  validate  →  plan  →  apply  →  destroy
```

| Команда | Що робить |
|---|---|
| `init` | Завантажує провайдери і модулі, підключає бекенд. Запускається першою і після змін у провайдерах, модулях чи бекенді |
| `validate` | Перевіряє синтаксис і типи. Не звертається до Azure |
| `fmt` | Форматує код за стандартом. `fmt -check` у CI падає, якщо код не відформатований |
| `plan` | Порівнює код, стейт і реальний Azure. Показує, що буде змінено |
| `apply` | Виконує план |
| `destroy` | Видаляє все, що є в стейті |

### 2. Символи в плані

| Символ | Значення |
|---|---|
| `+` | створити |
| `-` | видалити |
| `~` | змінити на місці (update in-place) |
| `-/+` | видалити і створити заново (replace). Небезпечно: дані на ресурсі зникнуть |
| `<=` | прочитати data source |

Рядок `# forces replacement` показує, який саме атрибут змушує Terraform пересоздати ресурс.

### 3. Версії провайдерів

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
```

| Обмеження | Що дозволяє |
|---|---|
| `= 3.117.1` | лише цю версію |
| `~> 3.0` | `3.x`, але не `4.0` |
| `~> 3.117.0` | `3.117.x`, але не `3.118` |
| `>= 3.118.0` | будь-яку новішу, включно з `4.x`, `5.x` |

**Історія з мого проєкту:** обмеження `>= 3.118.0` підтягнуло azurerm 5.8.0, у якому був баг з видаленням Container Apps. З `~> 3.0` цього б не сталося.

### 4. Lock-файл

`init` записує в `.terraform.lock.hcl` точну версію кожного провайдера і хеші. Наступний `init` бере саме ці версії, навіть якщо вийшли новіші.

- Lock-файл **комітять**, щоб у всіх (у вас, у колег, у CI) були однакові версії.
- Оновити версії свідомо: `terraform init -upgrade`.
- У моєму проєкті lock-файл був у `.gitignore`. Через це локально стояла 3.117.1, а CI щоразу брав найновішу.

### 5. `resource` і `data`

```hcl
# створити і керувати
resource "azurerm_resource_group" "rg" {
  name     = "rg-demo"
  location = "swedencentral"
}

# лише прочитати те, що вже існує
data "azurerm_client_config" "current" {}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}
```

Посилання на ресурс: `<тип>.<ім'я>.<атрибут>`. На data source: `data.<тип>.<ім'я>.<атрибут>`.

#### Локальне ім'я чи `name`: як відповісти на співбесіді

```hcl
resource "azurerm_virtual_network" "vnet" {   # ← локальне ім'я, для Terraform
  name = "vnet-demo"                          # ← ім'я в Azure, видно в порталі
```

> Локальне ім'я існує лише в Terraform: воно утворює адресу ресурсу в стейті (`azurerm_virtual_network.vnet`), і через нього посилаються на ресурс у коді. Azure про нього не знає. `name` — це реальне ім'я ресурсу в Azure, яке видно в порталі. Наслідки змін різні: якщо змінити локальне ім'я, Terraform вирішить, що це новий ресурс, і запропонує видалити старий, тому для перейменування використовують блок `moved`. Якщо змінити `name`, ресурс буде пересоздано, бо ім'я в Azure змінити не можна.

| | Локальне ім'я (`vnet`) | `name` (`vnet-demo`) |
|---|---|---|
| Хто знає | лише Terraform | Azure |
| Для чого | посилання в коді, адреса в стейті | реальне ім'я ресурсу |
| Унікальність | у межах типу ресурсу в одному модулі | за правилами Azure: VNet у межах RG, storage account глобально |
| Якщо змінити | destroy + create, якщо немає `moved` | `-/+`, пересоздання |

#### Адреса ресурсу: як відповісти на співбесіді

> Адреса ресурсу — його унікальний ідентифікатор усередині Terraform, складений з типу і локального імені: `azurerm_virtual_network.vnet`. З `count` до неї додається індекс (`[0]`), з `for_each` — ключ (`["web"]`), у модулі — префікс `module.<ім'я>.`. За адресою Terraform зв'язує ресурс у коді з записом у стейті. Її використовують у виводі `plan`, у командах `state list`, `state show`, `state mv`, `state rm`, `import`, `apply -replace`, а також у блоках `moved` і `import`.

Форми адреси:

```
azurerm_virtual_network.vnet                    # звичайний ресурс
azurerm_public_ip.pip[0]                        # з count, за індексом
azurerm_linux_virtual_machine.vm["web"]         # з for_each, за ключем
module.network.azurerm_virtual_network.this     # ресурс у модулі
data.azurerm_client_config.current              # data source
```

Де використовується:

- `terraform state list` — список адрес усіх ресурсів;
- вивід `plan`: `# azurerm_virtual_network.vnet will be created`;
- `state show`, `state rm`, `state mv`, `import`, `apply -replace=...`, `plan -target=...`;
- блоки `moved` і `import` (`from`, `to`).

### 6. Змінні, locals, outputs

```hcl
variable "location" {
  type        = string
  default     = "swedencentral"
  description = "Регіон для всіх ресурсів"

  validation {
    condition     = contains(["swedencentral", "northeurope"], var.location)
    error_message = "Дозволені лише swedencentral і northeurope."
  }
}

variable "admin_password" {
  type      = string
  sensitive = true    # не показується в plan і логах, але в стейті лежить відкрито
}

locals {
  prefix = "demo"
  tags = {
    project = "azure-demo"
    env     = "dev"
  }
}

output "rg_name" {
  value = azurerm_resource_group.rg.name
}
```

Типи змінних: `string`, `number`, `bool`, `list(...)`, `set(...)`, `map(...)`, `object({...})`, `tuple([...])`.

### 7. Звідки береться значення змінної

Від найнижчого пріоритету до найвищого (кожне наступне перекриває попереднє):

1. `default` у блоці `variable`
2. змінні оточення `TF_VAR_<ім'я>`
3. `terraform.tfvars`
4. `terraform.tfvars.json`
5. `*.auto.tfvars` (в алфавітному порядку)
6. `-var` і `-var-file` у командному рядку (в порядку, як написано)

Якщо значення немає ніде, Terraform питає інтерактивно. У CI це означає зависання, тому там завжди `-input=false`.

**У моєму проєкті:** локально `ssh_public_key` береться з `terraform.tfvars`, а в CI з `TF_VAR_ssh_public_key` (секрет `SSH_PUBLIC_KEY`).

### 8. Залежності

- **Неявні:** якщо ресурс посилається на атрибут іншого (`subnet_id = azurerm_subnet.subnet.id`), Terraform сам створить їх у правильному порядку.
- **Явні:** `depends_on = [...]` лише тоді, коли залежність є, але посилання немає. Наприклад, VM має чекати, поки з'явиться роль RBAC.
- Незалежні ресурси Terraform створює паралельно (за замовчуванням до 10 одночасно).

`terraform graph` виводить граф залежностей у форматі DOT.

### 9. Провайдери

#### Як влаштований Terraform

```
Terraform core                        Провайдери (плагіни)
─────────────────                     ─────────────────────
читає .tf файли                       azurerm  → Azure ARM API
будує граф залежностей         ──►    azuread  → Microsoft Graph API
порівнює код зі стейтом               random   → нічого, генерує значення
вирішує: create/update/delete         github   → GitHub API
```

**Core** нічого не знає про Azure, він вирішує, **що** зробити. **Провайдер** знає, **як**: які API викликати, які поля потрібні, як чекати завершення операції. Тому той самий Terraform працює з Azure, AWS, GitHub і Cloudflare.

#### Звідки береться провайдер

- `source = "hashicorp/azurerm"` — адреса в Terraform Registry: `<namespace>/<назва>`.
- `terraform init` завантажує його з registry.terraform.io у `.terraform/providers/`. Тому `.terraform/` у `.gitignore`: це бінарники, а не код.
- Провайдер має **власну версію**, незалежну від версії Terraform.
- Префікс типу ресурсу показує провайдера: `azurerm_resource_group` → `azurerm`, `random_string` → `random`.
- Мажорні версії (3 → 4 → 5) ламають сумісність. Про обмеження версій і lock-файл див. розділи 3 і 4.

#### Блок `provider`

```hcl
provider "azurerm" {
  features {}                 # обов'язковий для azurerm, навіть порожній
  subscription_id = "..."     # в azurerm 4.x+ обов'язковий
}
```

- У `features {}` налаштовують поведінку, наприклад `resource_group { prevent_deletion_if_contains_resources = false }`. Саме ця перевірка не дала `destroy` видалити групу, в якій лишився `cae-demo`.
- В azurerm 3.x `subscription_id` можна не вказувати, тоді він береться з `az` або `ARM_SUBSCRIPTION_ID`.

#### Як `azurerm` входить в Azure

| Спосіб | Де |
|---|---|
| `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` | мій CI зараз |
| OIDC (`ARM_USE_OIDC=true`) | тиждень 8 |
| managed identity (`ARM_USE_MSI=true`) | Terraform на VM в Azure |
| Azure CLI (`az login`) | локально на Mac |

Тому локально Terraform працює під моїм акаунтом, а в CI під `github-actions-terraform`.

#### Кілька провайдерів: `alias`

```hcl
provider "azurerm" {
  features {}
}

provider "azurerm" {
  alias           = "prod"
  features {}
  subscription_id = "<інша підписка>"
}

resource "azurerm_resource_group" "prod_rg" {
  provider = azurerm.prod
  ...
}
```

Так з одного коду керують кількома підписками чи регіонами.

#### Провайдери в Azure-проєктах

| Провайдер | Для чого |
|---|---|
| `azurerm` | ресурси Azure через ARM |
| `azuread` | Entra ID: app registrations, групи, користувачі (через Microsoft Graph) |
| `azapi` | будь-який ресурс Azure напряму через ARM API, навіть новий, якого ще немає в `azurerm` |
| `random` | випадкові імена, суфікси, паролі |
| `tls` | ключі та сертифікати |

`azurerm` проти `azuread` — та сама різниця, що й `az group` проти `az ad`: ARM проти Microsoft Graph.

## Команди напам'ять

```
terraform init
terraform init -upgrade          # оновити провайдери в межах обмежень
terraform fmt -recursive
terraform validate
terraform plan
terraform plan -var="location=northeurope"
terraform apply -auto-approve -input=false
terraform output
terraform output -raw vm_public_ip
terraform console                # інтерактивна перевірка виразів
terraform providers              # які провайдери потрібні і звідки
```

## Типові помилки

- Порожній блок `backend {}` або змінна без значення: у CI Terraform чекає вводу і висить.
- Обмеження версії без верхньої межі (`>=`): несподіваний перехід на нову мажорну версію.
- `sensitive = true` не шифрує значення в стейті, а лише ховає його з виводу.
- Lock-файл у `.gitignore`: у різних середовищах різні версії провайдерів.

## Перевірка себе

Без документації напишіть з нуля RG + VNet + subnet зі змінною `location`, тегами через `locals` і output з ID підмережі. Поясніть кожен рядок.

## Питання співбесіди

- Що робить `terraform init`?
- Навіщо lock-файл і чому його комітять?
- `~> 3.0` проти `>= 3.0`: що може статися з другим варіантом?
- У якому порядку Terraform бере значення змінних?
- `resource` проти `data`: різниця?
- Коли потрібен `depends_on`?
- Що означає `-/+` у плані і чому це небезпечно?
- Чи захищає `sensitive = true` секрет у стейті?
- Що таке провайдер і як він пов'язаний з Terraform core?
- Звідки Terraform бере провайдер і де він зберігається?
- Як провайдер `azurerm` автентифікується в Azure?
- Як керувати двома підписками з одного коду?
- Що робити, якщо потрібного ресурсу ще немає в `azurerm`?
