# Тиждень 6. Модулі та середовища

Як організувати код так, як у реальній команді.

## Терміни

| Термін | Що це, одним реченням |
|---|---|
| **Module** | Папка з файлами `.tf`, яку можна викликати з іншого коду з параметрами |
| **Root module** | Папка, де ви запускаєте `terraform`. Має бекенд і провайдер |
| **Child module** | Модуль, який викликають з root через блок `module` |
| **Module source** | Звідки брати модуль: локальна папка, git, Terraform Registry |
| **AVM** | Azure Verified Modules, офіційні модулі Microsoft для Azure |
| **Workspace** | Кілька окремих стейтів для однієї конфігурації |
| **Environment** | Середовище: dev, staging, prod |
| **DRY** | Don't Repeat Yourself, не повторюватися |
| **Terragrunt** | Обгортка над Terraform для DRY-конфігурації середовищ і бекендів |

## Поняття, які треба вміти пояснити своїми словами

### 1. Структура модуля

```
modules/network/
├── main.tf         # ресурси
├── variables.tf    # входи
├── outputs.tf      # виходи
└── versions.tf     # required_providers (без блоку provider і без backend)
```

Модуль **не** містить блоку `backend`, а блок `provider` у ньому вважається поганою практикою. Їх задає root module.

### 2. Виклик модуля

```hcl
module "network" {
  source = "./modules/network"

  name          = "vnet-demo"
  address_space = ["10.0.0.0/16"]
  location      = azurerm_resource_group.rg.location
  rg_name       = azurerm_resource_group.rg.name
}

module "vm" {
  source    = "./modules/vm"
  subnet_id = module.network.subnet_id    # вихід одного модуля → вхід іншого
}
```

Після додавання або зміни `source` потрібен `terraform init`.

### 3. Джерела модулів

```hcl
source = "./modules/network"                                          # локально
source = "git::https://github.com/org/tf-modules.git//network?ref=v1.2.0"   # git з тегом
source = "Azure/avm-res-network-virtualnetwork/azurerm"               # Registry
version = "~> 0.4"                                                    # лише для Registry
```

- Для git версію фіксують через `?ref=<тег>`.
- Для Registry через `version`.
- Без фіксації версії оновлення модуля може зламати всі середовища одночасно.

### 4. Що віддавати в outputs

- **Так:** ID, імена, адреси, які потрібні іншим модулям (`subnet_id`, `vnet_id`).
- **Ні:** весь ресурс цілком, секрети без `sensitive = true`, проміжні дані.

Входи модуля мають бути мінімальними й зрозумілими: краще 5 змінних з типами та описом, ніж 30 «на всякий випадок».

### 5. Перенесення ресурсів у модуль без пересоздання

Ресурс змінює адресу з `azurerm_virtual_network.vnet` на `module.network.azurerm_virtual_network.this`. Без підказки Terraform видалить старий і створить новий.

```hcl
moved {
  from = azurerm_virtual_network.vnet
  to   = module.network.azurerm_virtual_network.this
}
```

`plan` має показати `has moved to`, а не `destroy`.

### 6. Середовища: три підходи

**Workspaces**
```
terraform workspace new prod
terraform workspace select prod
```
- Один код, окремі стейти (`env:/prod/...`).
- Мінуси: легко зробити `apply` не в тому workspace, однаковий бекенд і права для всіх середовищ, різницю між середовищами доводиться писати через `terraform.workspace` у коді.

**Окремі директорії**
```
envs/
├── dev/
│   ├── main.tf          # викликає modules/*
│   ├── backend.tf       # key = "dev.tfstate"
│   └── terraform.tfvars
└── prod/
    ├── main.tf
    ├── backend.tf       # key = "prod.tfstate"
    └── terraform.tfvars
modules/
├── network/
└── vm/
```
- Явно видно, куди йде `apply`. Можна дати різні права і навіть різні підписки.
- Мінус: дублювання `main.tf` між середовищами (саме це вирішує Terragrunt).

**Один код + різні tfvars і backend-config**
```
terraform init -backend-config=env/prod.backend.hcl
terraform apply -var-file=env/prod.tfvars
```
- Мало коду, але легко переплутати файли.

**Що обирають у командах:** найчастіше окремі директорії або окремі репозиторії для prod, з модулями в окремому репозиторії з тегами. Workspaces радять для тимчасових копій (наприклад, середовище для PR), а не для dev/prod.

### 7. Як розділяти стейти

- Окремий стейт для кожного середовища.
- Часто також окремі стейти за шарами: мережа, бази, застосунки. Тоді помилка в застосунку не зачепить мережу, і `plan` працює швидше.
- Читання виходів іншого стейту: `data "terraform_remote_state"`.

## Команди напам'ять

```
terraform init                     # після зміни source модуля
terraform get -update              # оновити модулі
terraform workspace list
terraform workspace new <name>
terraform workspace select <name>
terraform state list | grep module.network
```

## Перевірка себе

Винесіть мережу свого проєкту в `modules/network`, а VM у `modules/vm`. Перенесіть існуючі ресурси блоками `moved` так, щоб `plan` не показав жодного `destroy`. Підніміть dev і prod з різними стейтами.

## Питання співбесіди

- Що таке модуль і навіщо він потрібен?
- Чому в child module не пишуть `backend` і `provider`?
- Workspaces чи окремі директорії для dev/prod: що оберете і чому?
- Як версіонувати модулі для кількох команд?
- Як перенести ресурси в модуль без пересоздання?
- Що має бути в outputs модуля?
- Як розділити один великий стейт і навіщо?
- Що таке Terragrunt і яку проблему він вирішує?
