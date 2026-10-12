# Тиждень 5. Вирази та мета-аргументи

Як писати гнучкий код без копіпасти.

## Терміни

| Термін | Що це, одним реченням |
|---|---|
| **Meta-argument** | Аргумент, який працює на будь-якому ресурсі: `count`, `for_each`, `depends_on`, `lifecycle`, `provider` |
| **`count`** | Створити N однакових копій ресурсу, адресація за індексом `[0]`, `[1]` |
| **`for_each`** | Створити копію для кожного елемента map або set, адресація за ключем `["web"]` |
| **`dynamic`** | Згенерувати вкладені блоки (наприклад, `security_rule`) з колекції |
| **`lifecycle`** | Налаштування того, як Terraform створює, змінює і видаляє ресурс |
| **Splat** | Вираз `resource.name[*].id`, що збирає атрибут з усіх копій |

## Поняття, які треба вміти пояснити своїми словами

### 1. `count`

```hcl
resource "azurerm_public_ip" "pip" {
  count               = 2
  name                = "pip-${count.index}"
  ...
}
# адреси: azurerm_public_ip.pip[0], azurerm_public_ip.pip[1]
```

Умовне створення:
```hcl
count = var.create_bastion ? 1 : 0
```

**Проблема `count` зі списком:**
```hcl
variable "names" { default = ["web", "api", "db"] }
count = length(var.names)
```
Якщо видалити `"web"`, то `api` переїде з `[1]` на `[0]`, а `db` з `[2]` на `[1]`. Terraform **пересоздасть** обидва, бо індекси змінилися.

### 2. `for_each`

```hcl
variable "vms" {
  default = {
    web = "Standard_B1s"
    api = "Standard_B2s"
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each = var.vms
  name     = "vm-${each.key}"
  size     = each.value
  ...
}
# адреси: azurerm_linux_virtual_machine.vm["web"], ...["api"]
```

Видалення `web` зачепить лише `web`, бо адреса прив'язана до ключа, а не до позиції.

- `for_each` приймає **map** або **set of strings**, не list: `for_each = toset(var.names)`.
- Ключі мають бути відомі під час `plan`, тому їх не можна брати з атрибутів, які стануть відомі лише після `apply`.

**Правило:** `count` для «0 або 1» і для повністю однакових копій. Для всього іншого `for_each`.

### 3. `dynamic`

Генерує вкладені блоки всередині **одного** ресурсу:

```hcl
variable "nsg_rules" {
  default = {
    ssh  = { priority = 1001, port = "22" }
    http = { priority = 1002, port = "80" }
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  dynamic "security_rule" {
    for_each = var.nsg_rules
    content {
      name                       = security_rule.key
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
}
```

Різниця: `for_each` на ресурсі створює **кілька ресурсів**, а `dynamic` створює **кілька блоків в одному ресурсі**.

### 4. Вирази

```hcl
# умовний вираз
size = var.env == "prod" ? "Standard_D2s_v5" : "Standard_B1s"

# for: перетворити колекцію
upper_names = [for n in var.names : upper(n)]
name_to_id  = { for k, v in azurerm_subnet.this : k => v.id }
only_prod   = [for n in var.envs : n if n != "dev"]

# splat
pip_ids = azurerm_public_ip.pip[*].id
```

### 5. Корисні функції

| Функція | Приклад | Результат |
|---|---|---|
| `merge` | `merge(local.tags, { role = "web" })` | об'єднати map |
| `lookup` | `lookup(var.sizes, var.env, "Standard_B1s")` | значення з map або default |
| `cidrsubnet` | `cidrsubnet("10.0.0.0/16", 8, 2)` | `10.0.2.0/24` |
| `try` | `try(var.config.port, 80)` | значення або запасне, якщо помилка |
| `coalesce` | `coalesce(var.name, "default")` | перше непорожнє |
| `format` | `format("vm-%s-%02d", "web", 1)` | `vm-web-01` |
| `jsonencode` | `jsonencode({ a = 1 })` | рядок JSON |
| `base64encode` | для `custom_data` | |
| `file`, `templatefile` | `templatefile("init.sh", { port = 3000 })` | зміст файлу з підстановкою |
| `toset`, `tolist`, `tomap` | перетворення типів | |

Перевіряти вирази зручно в `terraform console`.

### 6. `lifecycle`

```hcl
lifecycle {
  create_before_destroy = true
  prevent_destroy       = true
  ignore_changes        = [tags, custom_data]
  replace_triggered_by  = [azurerm_key_vault_secret.app.version]
}
```

| Аргумент | Що робить | Коли |
|---|---|---|
| `create_before_destroy` | Спершу створює новий ресурс, потім видаляє старий | Мінімізувати простій при replace. Потрібні унікальні імена |
| `prevent_destroy` | `plan` падає, якщо ресурс буде видалено | Бази даних, storage зі стейтом, Key Vault |
| `ignore_changes` | Не реагувати на зміни вказаних атрибутів | Атрибути, які змінює хтось інший: теги від політик, образ, який деплоїть CI |
| `replace_triggered_by` | Пересоздати ресурс, коли змінився інший ресурс | Перезапустити VM після зміни конфігурації |

**У моєму проєкті:** `ignore_changes = [custom_data]` на VM. Без нього зміна тексту в `custom_data` пересоздавала б VM, бо cloud-init не можна змінити на машині, що вже працює. Але тому ж зміни тексту й не доходили до VM.

### 7. Перевірки

```hcl
variable "env" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env має бути dev або prod."
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  ...
  lifecycle {
    precondition {
      condition     = var.env != "prod" || var.vm_size != "Standard_B1s"
      error_message = "Для prod потрібна більша VM."
    }
  }
}
```

- `validation`: перевірка вхідної змінної.
- `precondition`: перевірка перед створенням ресурсу.
- `postcondition`: перевірка після, з доступом до `self`.

## Перевірка себе

Перепишіть NSG свого проєкту через `dynamic` з map у змінній. Створіть дві VM через `for_each`. Видаліть одну з map і переконайтеся, що `plan` чіпає лише її.

## Питання співбесіди

- `count` проти `for_each`: різниця і коли що?
- Чому видалення елемента зі списку в `count` зачіпає інші ресурси?
- `dynamic` проти `for_each` на ресурсі?
- Коли доречний `ignore_changes`? Наведіть приклад.
- Що робить `create_before_destroy` і які в нього обмеження?
- Як захистити критичний ресурс від випадкового видалення?
- Що робить `replace_triggered_by`?
- Чому ключі `for_each` мають бути відомі під час `plan`?
