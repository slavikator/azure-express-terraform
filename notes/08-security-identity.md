# Тиждень 8. Безпека та ідентичність

Як прибрати секрети з пайплайна і дати кожному компоненту лише потрібні права.

## Терміни

| Абревіатура / термін | Розшифровка | Що це, одним реченням |
|---|---|---|
| **KV** | Key Vault | Сховище секретів, ключів і сертифікатів |
| **MI** | Managed Identity | Ідентичність ресурсу Azure без секретів |
| **OIDC** | OpenID Connect | Протокол, за яким GitHub видає токен, а Azure йому довіряє |
| **WIF** | Workload Identity Federation | Механізм Entra ID «довіряти зовнішньому токену» замість пароля |
| **Federated credential** | | Налаштування на app registration: якому зовнішньому токену довіряти |
| **PoLP** | Principle of Least Privilege | Давати лише мінімально потрібні права |
| **Azure Policy** | | Правила, що забороняють або перевіряють конфігурацію ресурсів |
| **CMK** | Customer-Managed Key | Шифрування власним ключем з Key Vault замість ключа Microsoft |
| **PIM** | Privileged Identity Management | Видача адмінських ролей на обмежений час за запитом |

## Поняття, які треба вміти пояснити своїми словами

### 1. Managed identity

| | System-assigned | User-assigned |
|---|---|---|
| Створюється | разом з ресурсом | окремим ресурсом |
| Живе | поки живе ресурс | незалежно |
| Скільки ресурсів | один | можна прив'язати до багатьох |
| Коли | одна VM читає один Key Vault | кілька ресурсів з однаковими правами, або права потрібні ще до створення ресурсу |

```hcl
resource "azurerm_linux_virtual_machine" "vm" {
  ...
  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "vm_kv" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.vm.identity[0].principal_id
}
```

### 2. Key Vault

- Зберігає **secrets** (паролі, рядки підключення), **keys** (криптографічні ключі), **certificates**.
- Модель доступу: **Azure RBAC** (рекомендовано) або старі **access policies**. Ролі: `Key Vault Administrator`, `Key Vault Secrets Officer` (запис), `Key Vault Secrets User` (читання).
- **Soft delete** (увімкнено завжди): видалений vault і секрети можна відновити протягом 7–90 днів. Через це ім'я видаленого vault не можна одразу використати знову.
- **Purge protection:** заборонити остаточне видалення до кінця строку. Обов'язково для prod.
- Мережа: firewall і private endpoint.

### 3. Секрети в Terraform

Проблема: усе, що Terraform знає про ресурс, лежить у стейті відкритим текстом.

| Спосіб | Що дає |
|---|---|
| `sensitive = true` | ховає значення з виводу `plan` і логів. **У стейті лишається** |
| Не генерувати секрети в Terraform | секрет створюють поза ним, Terraform лише посилається на Key Vault |
| `data "azurerm_key_vault_secret"` | читає секрет із KV, але значення все одно потрапляє в стейт |
| **Ephemeral resources** (Terraform 1.10+) | значення використовується під час запуску і **не записується** в стейт чи план |
| **Write-only arguments** (Terraform 1.11+) | аргумент передається в ресурс і не зберігається в стейті |
| Managed identity | секрету немає взагалі. Найкращий варіант |

Плюс захист самого стейту: приватний storage account, RBAC, мінімум доступу.

### 4. OIDC для GitHub Actions

**Як зараз у моєму проєкті:** `AZURE_CLIENT_SECRET` лежить у GitHub Secrets. Пароль має строк дії, його можна вкрасти, і його доводиться ротувати.

**З OIDC:**
1. GitHub для кожного запуску видає короткоживучий токен з даними: репозиторій, гілка, environment.
2. Azure перевіряє токен за налаштованим federated credential.
3. Якщо subject збігається, Azure видає свій токен доступу. Пароля немає ніде.

Federated credential на app registration:
```
Issuer:   https://token.actions.githubusercontent.com
Subject:  repo:slavikator/azure-express-terraform:ref:refs/heads/main
Audience: api://AzureADTokenExchange
```

Інші варіанти subject: `repo:<owner>/<repo>:environment:production`, `repo:<owner>/<repo>:pull_request`.

Workflow:
```yaml
permissions:
  id-token: write     # дозволити GitHub видати OIDC-токен
  contents: read

env:
  ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  ARM_USE_OIDC: true
  # ARM_CLIENT_SECRET більше не потрібен
```

Для `az` у workflow: `azure/login` з `client-id`, `tenant-id`, `subscription-id`, без `creds`.

Для бекенду `azurerm` також потрібен `use_oidc = true` (або `ARM_USE_OIDC`), і SP має мати доступ до storage account зі стейтом.

### 5. Мінімальні права для Terraform

- Не давати Contributor на всю підписку, якщо проєкт живе в одній RG. Краще Contributor лише на RG.
- Якщо Terraform створює `azurerm_role_assignment`, йому потрібна роль з правом видавати ролі: **User Access Administrator** або **Role Based Access Control Administrator** з умовами (обмежити, які ролі можна видавати).
- Окремі SP для dev і prod.
- Окремий SP з правом лише на `plan` (Reader + доступ до стейту) для PR, і окремий з правом на `apply` для main.

**У моєму проєкті:** два SP з Contributor на всю підписку, один з них більше не використовується.

### 6. Azure Policy

- **Definition** — правило (наприклад, «дозволені лише ці регіони»).
- **Initiative** — набір правил.
- **Assignment** — призначення на scope (management group, subscription, RG).
- Ефекти: `Deny` (заборонити створення), `Audit` (лише позначити), `Modify` / `DeployIfNotExists` (виправити автоматично), `Append`.

Приклади: allowed locations, обов'язковий тег `owner`, заборона публічних IP, обов'язкове шифрування.

Політика з ефектом `Deny` зупинить і `terraform apply`. Помилка буде `RequestDisallowedByPolicy`.

### 7. Принципи

- **Least privilege:** мінімальні права на мінімальному scope.
- **No secrets in code:** жодних паролів у `.tf`, `.tfvars` у git, змінних workflow.
- **Short-lived credentials:** OIDC і managed identity замість довгоживучих паролів.
- **Defense in depth:** кілька рівнів захисту (мережа, ідентичність, шифрування, моніторинг).

## Команди напам'ять

```
az ad app federated-credential create --id <appId> --parameters cred.json
az ad app federated-credential list --id <appId> -o table
az ad app credential list --id <appId> -o table      # client secrets і строк дії
az role assignment create --assignee <id> --role "Key Vault Secrets User" --scope <kv id>
az keyvault secret set --vault-name <kv> -n app-password --value ...
az keyvault secret show --vault-name <kv> -n app-password --query value -o tsv
az policy assignment list -o table
```

## Перевірка себе

Переведіть свій workflow на OIDC і видаліть `AZURE_CLIENT_SECRET` з GitHub. Створіть Key Vault, дайте VM managed identity з роллю `Key Vault Secrets User` і прочитайте секрет з VM без жодного пароля.

## Питання співбесіди

- Чому OIDC краще за client secret?
- Як працює workload identity federation для GitHub Actions?
- System-assigned чи user-assigned identity: коли що?
- Як не засвітити секрет у стейті Terraform?
- Які права реально потрібні Terraform SP і як їх обмежити?
- Key Vault: RBAC чи access policies?
- Навіщо soft delete і purge protection?
- Що таке Azure Policy і чим вона відрізняється від RBAC?
