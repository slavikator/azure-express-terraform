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

#### Tenant чи subscription: як відповісти на співбесіді

> Tenant — це екземпляр Entra ID, межа ідентичності: там живуть користувачі, групи, service principals, і там відбувається автентифікація. Subscription — це межа ресурсів і білінгу: там створюються ресурси, рахуються витрати і діють квоти. Один tenant може мати багато підписок, але кожна підписка довіряє лише одному tenant'у. Доступ до ресурсів дають ролі Azure RBAC на підписці чи нижче. Ролі Entra ID, як-от Global Administrator, керують ідентичностями і самі по собі доступу до ресурсів не дають.

Якщо інтерв'юер хоче глибше:

- підписку можна перенести в інший tenant, але тоді всі призначення ролей зникнуть, бо principal'и старого tenant'а для неї більше не існують;
- Global Administrator може тимчасово дати собі доступ до всіх підписок через «Elevate access». Ця опція існує саме тому, що за замовчуванням такого доступу немає.

Дві окремі системи ролей, які легко сплутати:

| | Entra ID roles | Azure RBAC roles |
|---|---|---|
| Де діють | в tenant'і (Entra ID) | на ресурсах: management group, підписка, RG, ресурс |
| Приклади | Global Administrator, User Administrator | Owner, Contributor, Reader |
| Чим керують | користувачами, групами, застосунками | ресурсами Azure |

Підписки **не** успадковують ролі від tenant'а. RBAC успадковується через management groups: роль на Tenant Root Group діє на всі підписки під нею.

### 2. RBAC: три складові

Кожне призначення ролі відповідає на три питання:

| Питання | Відповідь |
|---|---|
| **Хто?** | security principal (user, group, SP, MI) |
| **Що може?** | role (Reader, Contributor, Owner) |
| **Де?** | scope (підписка, група, ресурс) |

Права **успадковуються вниз**: роль на subscription діє на всі RG у ній. Вгору не діють: Contributor на RG не може створити нову RG, бо групи створюються на рівні підписки.

**Security principal** — загальна назва для будь-кого, кому можна видати роль:

```
Security principal
├── User               людина: slavikator@gmail.com
├── Group              група людей або інших principal
├── Service principal  програма: github-actions-terraform
└── Managed identity   ресурс Azure (VM, App Service); технічно теж service principal
```

- **Security principal** — категорія, **service principal** — один з її видів.
- У `az role assignment list` вид показує поле `principalType` (`User`, `Group`, `ServicePrincipal`), а `principalId` — object ID цього principal.
- На практиці ролі видають **групам**, а не окремим людям: доступ додається і забирається через членство в групі.

#### Успадкування ролей RBAC: як відповісти на співбесіді

```
Management group  →  Subscription  →  Resource group  →  Resource
```

> Ролі RBAC успадковуються зверху вниз за ієрархією: management group → subscription → resource group → resource. Призначення ролі на будь-якому рівні діє на цей рівень і на все під ним. Права з різних призначень сумуються: якщо в мене Reader на підписці і Contributor на групі, у цій групі я маю Contributor. Обмежити успадковане право на нижчому рівні не можна, переважають лише deny assignments, які ставить сам Azure. Призначення ролі живе на своєму scope: при видаленні групи зникають призначення на ній і на її ресурсах, а призначення на підписці лишаються.

Що легко сплутати:

- **Роль** (role definition, наприклад Contributor) і **призначення ролі** (role assignment: «цей principal має Contributor на цьому scope»). При видаленні групи зникають призначення, а не самі ролі.
- Група знаходиться **в підписці**, а не навпаки. Тому видалення групи не чіпає призначень на рівні підписки.

У вправі «Обмежений робот» це видно: Reader і Contributor робота на `rg-practice-rbac` зникли разом з групою, а Contributor двох старих SP на підписці лишився.

Принцип **least privilege**: видавати роль на найнижчому достатньому рівні. Наприклад, Contributor на одну RG проєкту, а не на всю підписку.

### 3. Три базові ролі

| Роль | Ресурси | Видавати ролі |
|---|---|---|
| **Owner** | ✅ все | ✅ |
| **Contributor** | ✅ все | ❌ |
| **Reader** | лише перегляд | ❌ |

Плюс **User Access Administrator**: видає ролі, але не керує ресурсами.

#### Чому Contributor не може видавати ролі: як відповісти на співбесіді

> Щоб запобігти підвищенню привілеїв: якби Contributor міг видавати ролі, він видав би собі Owner, і різниця між ролями зникла б. Тому в Contributor дозволено все, крім дій `Microsoft.Authorization/*/Write` і `Delete`, тобто керування доступом. Це також реалізує розділення обов'язків: керування ресурсами окремо від керування доступом. Видавати ролі можуть Owner, User Access Administrator і Role Based Access Control Administrator, причому останню можна обмежити умовами, які саме ролі дозволено видавати.

Терміни: **privilege escalation** — підвищення власних привілеїв; **separation of duties** — розділення обов'язків.

Як це влаштовано: у Contributor `actions: ["*"]`, а в `notActions` винятки, головні з яких:

```
Microsoft.Authorization/*/Write
Microsoft.Authorization/*/Delete
Microsoft.Authorization/elevateAccess/Action
```

Перевірити: `az role definition list --name Contributor --query "[].permissions[].notActions" -o json`

Хто може видавати ролі:

| Роль | Ресурси | Ролі |
|---|---|---|
| **Owner** | ✅ | ✅ |
| **User Access Administrator** | ❌ | ✅ |
| **Role Based Access Control Administrator** | ❌ | ✅, можна обмежити умовами (які ролі і кому) |
| **Contributor** | ✅ | ❌ |

**Наслідок для Terraform:** SP з роллю Contributor не зможе створити `azurerm_role_assignment` — `apply` впаде з `AuthorizationFailed` на `Microsoft.Authorization/roleAssignments/write`. Найбезпечніше рішення — додати Terraform SP роль Role Based Access Control Administrator з умовою, яка дозволяє видавати лише потрібні ролі.

### 4. App registration і service principal

| | App registration (application object) | Service principal |
|---|---|---|
| Що це | «Паспорт» застосунку | «Екземпляр» застосунку в конкретному tenant'і |
| Що зберігає | Ім'я, **секрети**, сертифікати, federated credentials | **Ролі RBAC** |
| У моєму проєкті | `github-actions-terraform`, тут лежить `AZURE_CLIENT_SECRET` | Той самий `appId`, але тут видано роль Contributor |

Тому `az ad sp show` показує порожній `passwordCredentials`: секрет лежить в app registration (`az ad app credential list --id <appId>`).

#### App registration чи service principal: як відповісти на співбесіді

> App registration — це глобальне визначення застосунку, його «паспорт»: ім'я, `appId`, секрети, сертифікати, federated credentials. Він існує в одному home tenant'і. Service principal — це локальний екземпляр застосунку в конкретному tenant'і, його «акаунт». Саме йому видають ролі RBAC, і саме під ним застосунок діє. Вони мають спільний `appId`, але різні object ID. Для single-tenant застосунку вони йдуть парою, і `az ad sp create-for-rbac` створює обидва одразу. Для multi-tenant застосунку на один app registration буде по service principal у кожному tenant'і, де його використовують.

Якщо інтерв'юер хоче глибше:

- видалення app registration видаляє і його service principal;
- managed identity має **лише** service principal, без app registration, тому секретів у неї немає взагалі.

У вправі «Обмежений робот» це видно: `sp-practice` мав `appId` `0dc751b6-...` і в app registration, і в service principal, а object ID service principal був окремий, `48907eff-...`.

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

#### Чому OIDC краще за client secret: як відповісти на співбесіді

> Немає довгоживучого секрету, який можна вкрасти. Замість пароля GitHub для кожного запуску видає короткоживучий токен, а Azure перевіряє його за federated credential: хто видав токен (issuer) і для якого репозиторію, гілки чи environment (subject). Токен живе хвилини і приймається лише з дозволеного місця, тож навіть перехоплений він майже марний. До того ж не треба зберігати й ротувати пароль, і CI не зламається через прострочений секрет. У GitHub лежать лише несекретні ідентифікатори: client ID, tenant ID, subscription ID.

| | Client secret | OIDC |
|---|---|---|
| Що зберігається в GitHub | пароль | лише ID: client, tenant, subscription |
| Строк дії | місяці | хвилини |
| Звідки можна використати | звідки завгодно | лише з вказаного репо, гілки чи environment |
| Ротація | вручну, інакше CI зламається | не потрібна |

Federated credential — правило з трьох полів:

| Поле | Приклад |
|---|---|
| Issuer | `https://token.actions.githubusercontent.com` |
| Subject | `repo:slavikator/azure-express-terraform:ref:refs/heads/main` |
| Audience | `api://AzureADTokenExchange` |

Детальніше і як налаштувати — у `08-security-identity.md`, розділ 4.

### 5. Service principal чи managed identity

- Код працює **в Azure** (VM, App Service, Function) → **managed identity**.
- Код працює **поза Azure** (GitHub Actions, ноутбук) → **service principal**, бажано з OIDC.

Критерій — **де працює код**, а не куди він звертається. І MI, і SP можуть ходити в Key Vault, Storage, Microsoft Graph і будь-що, що приймає токени Entra ID.

#### Service principal чи managed identity: як відповісти на співбесіді

> Критерій — де працює код. Якщо на ресурсі Azure (VM, App Service, Functions, Container Apps, AKS), беру managed identity: Azure сам керує обліковими даними, секретів немає, ротувати нічого не треба. Якщо код працює поза Azure (GitHub Actions, on-premises, інша хмара), managed identity недоступна, тому беру service principal, бажано з federated credential (OIDC), щоб теж обійтися без пароля. Технічно managed identity — це теж service principal, але без app registration, і керує ним Azure.

Якщо інтерв'юер хоче глибше:

- **system-assigned** MI живе разом з ресурсом і видаляється з ним; **user-assigned** — окремий ресурс, який можна прив'язати до кількох ресурсів;
- **self-hosted runner** GitHub Actions, запущений на VM в Azure, може використовувати MI цієї VM замість SP. Тобто знову вирішує те, де працює код.

### 6. Регіон, availability zone, пара регіонів

- **Регіон** — географічна локація (`swedencentral`).
- **AZ** — окремі дата-центри в регіоні, захищають від аварії одного з них.
- **Пара регіонів** — для disaster recovery.

### 7. ARM як єдиний вхід

Портал, `az` і Terraform перетворюються на запит до ARM API. Тому ресурс, створений у порталі, Terraform не бачить, поки не зробити `import`, і саме тому стейт може розійтися з реальністю.

### 8. Хто видалив ресурс

#### Як відповісти на співбесіді

> Для ресурсів Azure — activity log: він фіксує всі операції control plane через ARM. Фільтрую за операціями delete і дивлюся поле `caller`. Для людини там email, для service principal чи managed identity — object ID, який розшифровую через `az ad sp show`. Якщо це SP пайплайна, далі шукаю відповідний запуск CI за часом. Activity log зберігається лише 90 днів, тому в продакшні його експортують через diagnostic settings у Log Analytics і шукають KQL-запитом по таблиці `AzureActivity`. Якщо видалили дані всередині ресурсу (blob, секрет), activity log цього не покаже: потрібні resource logs. Видалення користувачів і застосунків видно в Entra ID audit logs. А щоб критичне взагалі не видалили, ставлю resource locks і обмежую права.

#### Activity log

```
az monitor activity-log list --offset 7d \
  --query "[?contains(operationName.value,'delete')].{time:eventTimestamp, op:operationName.value, resource:resourceId, status:status.value, caller:caller}" \
  -o table
```

- **`caller`** — хто: email для людини, object ID для SP чи MI;
- **`operationName`** — що зроблено, наприклад `Microsoft.Compute/virtualMachines/delete`;
- **`correlationId`** — об'єднує всі записи однієї операції (видалення RG дає десятки записів зі спільним `correlationId`).

Розшифрувати object ID:

```
az ad sp show --id <objectId> --query displayName -o tsv            # SP або MI
az ad user show --id <objectId> --query userPrincipalName -o tsv    # людина
```

Якщо це SP пайплайна, шукаю запуск CI за часом (`gh run list`). У моєму проєкті так знайшов, що VM після `destroy` створив `github-actions-terraform` (`5cc14326-...`).

#### Межі activity log

| Обмеження | Що робити |
|---|---|
| Зберігається лише **90 днів** | Експорт через **diagnostic settings** у **Log Analytics** або Storage |
| Не бачить **data plane**: blob, секрет у Key Vault, записи в БД | **Resource logs** через diagnostic settings (`StorageBlobLogs`, `AzureDiagnostics`) |
| Не бачить змін в **Entra ID**: користувачі, app registrations | **Entra ID audit logs** |

Відповідь залежить від того, **що** видалили: ресурс, дані в ньому чи ідентичність.

#### KQL у Log Analytics

```kusto
AzureActivity
| where OperationNameValue endswith "/delete"
| where ActivityStatusValue == "Success"
| project TimeGenerated, Caller, OperationNameValue, _ResourceId
| order by TimeGenerated desc
```

#### Профілактика

- **Resource locks** (`CanNotDelete`, `ReadOnly`): навіть Owner не видалить ресурс, поки не зніме lock;
- **least privilege**: менше principal'ів з правом видаляти;
- **alert** на операції видалення в activity log;
- **soft delete** (Key Vault, Storage blobs, Recovery Services), щоб видалене можна було відновити.

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
