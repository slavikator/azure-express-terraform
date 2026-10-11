# Тиждень 1. Фундамент Azure

Що треба знати напам'ять перед тим, як іти далі.

## Абревіатури

| Абревіатура | Розшифровка | Що це, одним реченням |
|---|---|---|
| **ARM** | Azure Resource Manager | Єдиний API Azure, через який працюють портал, `az` і Terraform |
| **RG** | Resource Group | Логічний контейнер для ресурсів. Видалення RG видаляє все всередині |
| **RBAC** | Role-Based Access Control | Права за схемою «хто + роль + scope» |
| **SP** | Service Principal | Обліковий запис для програми (CI, скрипт), а не для людини |
| **MI** | Managed Identity | SP, яким керує Azure, без секретів. Працює лише для ресурсів в Azure |
| **Entra ID** | колишній **Azure AD (AAD)** | Каталог користувачів і застосунків. Обидві назви трапляються |
| **AZ** | Availability Zone | Фізично окремий дата-центр у межах регіону |
| **OIDC** | OpenID Connect | Вхід за токеном без пароля. Так GitHub входить в Azure без секрету |
| **MFA** | Multi-Factor Authentication | Вхід з другим фактором. Саме через нього CI не може входити під вашим акаунтом |
| **CLI** | Command-Line Interface | Тут це `az` |

## Поняття, які треба вміти пояснити своїми словами

### 1. Ієрархія

```
Tenant (Entra ID)
└── Management Group      ← необов'язковий рівень
    └── Subscription      ← рахунок і межа лімітів
        └── Resource Group
            └── Resource
```

Гроші рахуються на рівні subscription.

### 2. RBAC: три складові

- **Security principal** — хто: user, group, SP, MI;
- **Role** — що можна робити;
- **Scope** — де: management group, subscription, RG або окремий ресурс.

Права **успадковуються вниз**: роль на subscription діє на всі RG у ній.

### 3. Три базові ролі

| Роль | Ресурси | Видавати ролі |
|---|---|---|
| **Owner** | ✅ все | ✅ |
| **Contributor** | ✅ все | ❌ |
| **Reader** | лише перегляд | ❌ |

Плюс **User Access Administrator**: видає ролі, але не керує ресурсами.

### 4. App registration і service principal

| | App registration (application object) | Service principal |
|---|---|---|
| Що це | «Паспорт» застосунку | «Екземпляр» застосунку в конкретному tenant'і |
| Що зберігає | Ім'я, **секрети**, сертифікати, federated credentials | **Ролі RBAC** |
| У моєму проєкті | `github-actions-terraform`, тут лежить `AZURE_CLIENT_SECRET` | Той самий `appId`, але тут видано роль Contributor |

Тому `az ad sp show` показує порожній `passwordCredentials`: секрет лежить в app registration (`az ad app credential list --id <appId>`).

Три ідентифікатори, які легко сплутати:

| Назва | Де трапляється |
|---|---|
| `appId` (client ID) | `ARM_CLIENT_ID`, `principalName` у списку ролей |
| object ID самого SP | `principalId` у списку ролей, `caller` в activity log |
| tenant ID | `ARM_TENANT_ID` |

Як SP доводить, хто він:

1. **Client secret**, тобто пароль. Найпростіший і найменш безпечний спосіб.
2. **Сертифікат.** Безпечніший, але незручний в адмініструванні.
3. **Federated credential (OIDC).** Пароля немає, Azure довіряє токену від GitHub. Рекомендований спосіб.

### 5. Service principal чи managed identity

- Код працює **в Azure** (VM, App Service, Function) → **managed identity**.
- Код працює **поза Azure** (GitHub Actions, ноутбук) → **service principal**, бажано з OIDC.

### 6. Регіон, availability zone, пара регіонів

- **Регіон** — географічна локація (`swedencentral`).
- **AZ** — окремі дата-центри в регіоні, захищають від аварії одного з них.
- **Пара регіонів** — для disaster recovery.

### 7. ARM як єдиний вхід

Портал, `az` і Terraform перетворюються на запит до ARM API. Тому ресурс, створений у порталі, Terraform не бачить, поки не зробити `import`, і саме тому стейт може розійтися з реальністю.

## Команди `az` напам'ять

```
az login
az account show                  # під ким я і в якій підписці
az account set -s <id>           # переключити підписку
az group list -o table
az role assignment list --assignee <id> -o table
az monitor activity-log list --offset 7d -o table
```

- Структура команди: `az <сервіс> <ресурс> <дія> --параметри`. Якщо не пам'ятаєте дію, допишіть `--help`.
- Довгі параметри завжди через `--`: `--id`, а не `-id`.
- `activity-log list` без `--offset` показує лише останні 6 годин.
- `--query` (JMESPath) вибирає поля, `-o table`/`json`/`tsv` задає формат.

## Перевірка себе

Поясніть вголос за 2 хвилини, без підглядання:

> Що відбувається, коли GitHub Actions запускає `terraform apply`? Як він входить в Azure, звідки знає, що має право, і куди йде запит?

Відповідь має пройти ланцюжок: SP → токен від Entra ID → запит до ARM → перевірка RBAC → resource provider створює ресурс.

## Питання співбесіди

- Чим tenant відрізняється від subscription?
- Чим app registration відрізняється від service principal?
- Service principal чи managed identity: коли що?
- Як успадковуються ролі RBAC?
- Чому Contributor не може видавати ролі?
- Чому OIDC краще за client secret?
- Як дізнатися, хто видалив ресурс? (Activity log, поле `caller`.)
