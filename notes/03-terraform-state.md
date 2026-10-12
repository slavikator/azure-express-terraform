# Тиждень 3. Стейт

Найважливіша тема на співбесіді. Що таке стейт, як він ламається і як його лагодити.

## Терміни

| Термін | Що це, одним реченням |
|---|---|
| **State** | JSON-файл, де Terraform зберігає зв'язок «ресурс у коді ↔ реальний об'єкт в Azure» |
| **Backend** | Де зберігається стейт: локально чи віддалено (Azure Storage, S3, Terraform Cloud) |
| **Remote state** | Стейт у спільному сховищі, доступний CI і команді |
| **State lock** | Блокування, яке не дає двом процесам змінювати стейт одночасно |
| **Lease** | Механізм блокування blob'а в Azure Storage. Так працює lock бекенду `azurerm` |
| **Drift** | Розбіжність між стейтом і реальним станом Azure (хтось змінив щось руками) |
| **Refresh** | Перечитування реального стану ресурсів перед plan і apply |
| **Import** | Взяти під керування Terraform ресурс, створений поза ним |
| **Taint / replace** | Позначити ресурс для пересоздання |

## Поняття, які треба вміти пояснити своїми словами

### 1. Навіщо стейт

Terraform не шукає ресурси в Azure за іменами. Він знає про ресурс лише тому, що той записаний у стейті з ID:

```
azurerm_resource_group.rg  →  /subscriptions/.../resourceGroups/rg-devops-demo-swe
```

`plan` порівнює три речі: **код** (що має бути), **стейт** (що Terraform створив) і **реальний Azure** (що є зараз).

Що зберігає стейт:
- ID і всі атрибути кожного ресурсу;
- залежності між ресурсами;
- значення outputs;
- **секрети**: паролі, ключі, connection strings відкритим текстом.

### 2. Remote backend `azurerm`

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstate1791293035"
    container_name       = "tfstate"
    key                  = "demo-node.terraform.tfstate"
  }
}
```

- Стейт лежить як blob у storage account.
- Під час `plan` чи `apply` Terraform бере **lease** на цей blob. Другий процес побачить `Error acquiring the state lock` і не зіпсує стейт.
- У блоці `backend` **не можна** використовувати змінні. Тому значення або пишуть явно, або передають через `-backend-config`.

Часткова конфігурація:

```hcl
backend "azurerm" {}          # порожній блок
```

```
terraform init -backend-config=backend.hcl
# або
terraform init -backend-config="key=prod.tfstate"
```

**Історія з мого проєкту:** блок був порожній, а `-backend-config` у CI не передавали. `terraform init` чекав інтерактивного вводу, і CI зависав.

### 3. Як захистити стейт

- Окрема RG для стейту (`rg-tfstate`), щоб `destroy` проєкту його не видалив.
- Без публічного доступу до storage account, доступ через RBAC.
- **Blob versioning** або soft delete, щоб відновити зіпсований стейт.
- Мінімум людей з доступом: хто читає стейт, той бачить секрети.

### 4. Команди роботи зі стейтом

| Команда | Що робить | Чи чіпає Azure |
|---|---|---|
| `state list` | список ресурсів у стейті | ні |
| `state show <адреса>` | атрибути ресурсу зі стейту | ні |
| `state mv <стара> <нова>` | перейменувати адресу ресурсу | ні |
| `state rm <адреса>` | забути ресурс | ні, ресурс лишається в Azure |
| `import <адреса> <id>` | записати існуючий ресурс у стейт | лише читає |
| `force-unlock <lock id>` | зняти завислий lock | ні |
| `destroy` | видалити ресурси | **так, видаляє** |

Головна різниця: `state rm` прибирає ресурс лише зі стейту, а `destroy` видаляє його в Azure.

### 5. Import: блоком і командою

Старий спосіб, команда:
```
terraform import azurerm_resource_group.rg /subscriptions/<id>/resourceGroups/rg-manual
```

Новий спосіб (Terraform 1.5+), блок у коді, проходить через `plan`:
```hcl
import {
  to = azurerm_resource_group.rg
  id = "/subscriptions/<id>/resourceGroups/rg-manual"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-manual"
  location = "swedencentral"
}
```

`terraform plan -generate-config-out=generated.tf` може навіть згенерувати код ресурсу.

Після імпорту `plan` має показати `No changes`. Якщо показує зміни, код не збігається з реальністю, і їх треба вирівняти. **У моєму проєкті** після імпорту `cae-demo` план хотів прибрати `workload_profile`, бо Azure додав його сам.

### 6. `moved`: перейменування без пересоздання

Якщо перейменувати ресурс у коді, Terraform вирішить, що старий треба видалити, а новий створити. Щоб цього уникнути:

```hcl
moved {
  from = azurerm_virtual_network.vnet
  to   = azurerm_virtual_network.main
}
```

Те саме працює при перенесенні ресурсів у модуль (`to = module.network.azurerm_virtual_network.main`).

Є також блок `removed` (Terraform 1.7+): прибрати ресурс зі стейту через код, не видаляючи його в Azure.

### 7. Drift і refresh

Хтось змінив тег у порталі. Що буде:
- `terraform plan` покаже, що поверне тег як у коді;
- `terraform plan -refresh-only` покаже лише різницю між стейтом і Azure, нічого не плануючи змінювати;
- `terraform apply -refresh-only` запише в стейт реальний стан, не змінюючи Azure.

### 8. Пересоздання ресурсу

```
terraform apply -replace=azurerm_linux_virtual_machine.vm
```

Замінило старе `terraform taint`. Корисно, коли ресурс «зламаний», а код не змінився. **У моєму проєкті:** зміна тексту в `custom_data` не потрапляла на VM, бо cloud-init виконується лише при першому запуску.

### 9. Коли код, стейт і Azure розходяться

| Ситуація | Що робити |
|---|---|
| Ресурс є в Azure, немає в стейті | `import` |
| Ресурс є в стейті, видалений в Azure руками | `plan` сам побачить це після refresh і запропонує створити заново. Якщо ресурс більше не потрібен, `state rm` і прибрати з коду |
| Ресурс змінили в Azure руками | `plan -refresh-only`, потім або повернути через `apply`, або оновити код |
| Apply впав посередині | Запустити `plan` ще раз. Terraform пише в стейт усе, що встиг створити |
| Lock завис після Ctrl+C | `force-unlock <id>`, але лише якщо впевнені, що ніхто інший не працює |

**Історії з мого проєкту:**
- Azure повернув помилку нестачі потужностей, але створив environment пізніше. Ресурс був в Azure, але не в стейті.
- Провайдер не дочекався завершення видалення. Ресурс зник з Azure, але лишився в стейті. Допоміг повторний `destroy`: refresh побачив, що ресурсу вже немає.

## Команди напам'ять

```
terraform state list
terraform state show azurerm_resource_group.rg
terraform state mv <from> <to>
terraform state rm <address>
terraform import <address> <azure id>
terraform plan -refresh-only
terraform apply -replace=<address>
terraform force-unlock <lock id>
terraform state pull > backup.tfstate     # локальна копія стейту
```

## Перевірка себе

Навмисно розсинхронізуйте код, стейт і Azure трьома способами: створіть ресурс руками, видаліть ресурс руками, змініть атрибут руками. Відновіть кожен випадок і поясніть, що робили.

## Питання співбесіди

- Що таке стейт і навіщо він потрібен?
- Що станеться, якщо двоє одночасно запустять `apply`?
- Як працює блокування стейту в Azure?
- Ресурс створено руками. Як забрати його під керування Terraform?
- `state rm` проти `destroy`: у чому різниця?
- Чому стейт вважається секретом і як його захищати?
- Як перейменувати ресурс у коді, не пересоздаючи його?
- Apply впав посередині. Що робити?
- Що таке drift і як його виявляти?
- Чому в блоці `backend` не можна використовувати змінні?
