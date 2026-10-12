# Тиждень 7. Обчислення та PaaS

Основні сервіси для запуску застосунків і як обрати потрібний.

## Терміни

| Абревіатура / термін | Розшифровка | Що це, одним реченням |
|---|---|---|
| **IaaS** | Infrastructure as a Service | Ви керуєте ОС і всім вище. Приклад: VM |
| **PaaS** | Platform as a Service | Azure керує ОС, ви даєте код або контейнер. Приклад: App Service |
| **SaaS** | Software as a Service | Готовий продукт. Приклад: Microsoft 365 |
| **VM** | Virtual Machine | Віртуальна машина |
| **VMSS** | Virtual Machine Scale Set | Група однакових VM з автомасштабуванням |
| **ASP** | App Service Plan | «Залізо» під App Service: розмір і кількість інстансів |
| **ACR** | Azure Container Registry | Приватний реєстр Docker-образів |
| **ACA** | Azure Container Apps | Контейнери без керування Kubernetes, масштабування до нуля |
| **AKS** | Azure Kubernetes Service | Керований Kubernetes |
| **LRS / ZRS / GRS** | Locally / Zone / Geo-Redundant Storage | Варіанти реплікації даних у Storage |
| **SLA** | Service Level Agreement | Гарантований відсоток доступності |

## Поняття, які треба вміти пояснити своїми словами

### 1. Зона відповідальності

```
            On-prem   IaaS (VM)   PaaS (App Service)   SaaS
Застосунок    ви         ви            ви               Microsoft
Runtime       ви         ви            Microsoft        Microsoft
ОС            ви         ви            Microsoft        Microsoft
Залізо        ви      Microsoft        Microsoft        Microsoft
```

Чим вище по стеку, тим менше вам адмініструвати і тим менше контролю.

### 2. Віртуальні машини

- **Розміри:** серія показує призначення. `B` — burstable (дешеві, для невеликих навантажень, у вашому проєкті `Standard_B2ls_v2`), `D` — загального призначення, `E` — багато пам'яті, `F` — багато CPU.
- **Диски:** OS disk обов'язковий, data disks додаткові. Типи: Standard HDD, Standard SSD, Premium SSD, Ultra.
- **Stop vs deallocate:**
  - stop з ОС: VM вимкнена, але залізо закріплене, **гроші за обчислення йдуть**;
  - `az vm deallocate`: залізо звільнене, за обчислення не платите, за диски і статичну IP платите далі.
- **`custom_data` / cloud-init виконується лише під час першого запуску.** Оновлювати застосунок на працюючій VM треба інакше: SSH, Ansible, VM extensions, або пересоздати VM (`-replace`).

### 3. Доступність

| Варіант | Від чого захищає | SLA для VM |
|---|---|---|
| Одна VM з Premium SSD | | 99,9% |
| **Availability set** | збій стійки чи оновлення в одному дата-центрі | 99,95% |
| **Availability zones** | аварія цілого дата-центру | 99,99% |
| Кілька регіонів | аварія регіону | залежить від архітектури |

### 4. VMSS

- Група однакових VM з одного образу.
- **Autoscale:** додає або прибирає інстанси за метриками (CPU, черга) чи за розкладом.
- Зазвичай стоїть за Load Balancer або Application Gateway.
- Режими: Uniform (усі однакові) і Flexible (рекомендований зараз, підтримує зони й різні розміри).

### 5. App Service

- **App Service Plan** — це залізо (SKU: Free, Basic, Standard, Premium) і кількість інстансів. **Web App** — застосунок, що працює на плані. Кілька застосунків можуть ділити один план.
- Деплой: код (Node, Python, .NET, Java) або контейнер.
- Вбудовано: HTTPS, власні домени, deployment slots (staging → swap у production без простою), autoscale.

### 6. Контейнери

| | Container Apps (ACA) | AKS |
|---|---|---|
| Kubernetes | під капотом, не видно | повний доступ |
| Хто керує кластером | Azure | ви (Azure керує лише control plane) |
| Масштабування до 0 | так | ні (без додаткових інструментів) |
| Коли | мікросервіси, API, фонові задачі без потреби в Kubernetes | потрібні можливості Kubernetes, складні платформи, команда з досвідом K8s |

Терміни ACA з вашого проєкту:
- **Environment** — спільна межа для кількох застосунків: мережа, логи. На trial-підписці дозволено лише один.
- **Revision** — незмінна версія застосунку. Нова версія образу створює нову ревізію.
- **Ingress** — вхідний трафік, `target_port` має збігатися з портом застосунку.

**ACR:** приватний реєстр образів. Доступ: admin user (простіше, менш безпечно) або managed identity з роллю `AcrPull` (рекомендовано). `az acr build` збирає образ в Azure (ACR Tasks), але на trial-підписці це вимкнено.

### 7. Що обрати

| Задача | Сервіс |
|---|---|
| Повний контроль над ОС, старий софт | VM |
| Багато однакових VM з автомасштабуванням | VMSS |
| Вебзастосунок або API без адміністрування ОС | App Service |
| Контейнери без Kubernetes, оплата за використання | Container Apps |
| Платформа на Kubernetes | AKS |
| Короткі події, тригери, cron | Azure Functions |

### 8. Storage account

| Реплікація | Копій | Де | Захищає від |
|---|---|---|---|
| **LRS** | 3 | один дата-центр | збою диска чи сервера |
| **ZRS** | 3 | три зони регіону | аварії дата-центру |
| **GRS** | 6 | LRS + асинхронна копія в парному регіоні | аварії регіону |
| **GZRS** | 6 | ZRS + копія в парному регіоні | аварії дата-центру і регіону |
| **RA-GRS / RA-GZRS** | 6 | як GRS/GZRS + читання з другого регіону | |

Рівні доступу для blob: **Hot** (часто читаєте), **Cool** (рідко, від 30 днів), **Cold** (від 90 днів), **Archive** (дуже рідко, відновлення годинами).

### 9. Моніторинг

- **Azure Monitor** — загальна платформа метрик і логів.
- **Log Analytics workspace** — сховище логів, запити мовою **KQL**.
- **Diagnostic settings** — що і куди відправляти з ресурсу (логи NSG, Key Vault, App Service).
- **Alerts** — сповіщення за метрикою чи запитом до логів. Дії задає **action group** (email, webhook).
- **Application Insights** — моніторинг застосунку: запити, помилки, залежності.

## Команди напам'ять

```
az vm list -d -o table                       # з поточним станом
az vm deallocate -g <rg> -n <vm>
az vm start -g <rg> -n <vm>
az vm list-sizes -l swedencentral -o table
az webapp list -o table
az containerapp list -o table
az containerapp logs show -n <app> -g <rg>
az acr repository list -n <acr> -o table
```

## Перевірка себе

Для трьох застосунків оберіть сервіс і обґрунтуйте вибір через вартість, масштабування і зону відповідальності: (1) старий .NET Framework застосунок на Windows; (2) REST API з нерівномірним навантаженням; (3) 30 мікросервісів у команди з досвідом Kubernetes.

## Питання співбесіди

- IaaS, PaaS, SaaS: різниця на прикладах Azure?
- VM, VMSS, App Service, Container Apps, AKS: коли що?
- Availability set чи availability zone?
- Stop чи deallocate: різниця у вартості?
- LRS, ZRS, GRS: що обрати для стейту Terraform і чому?
- Як оновити застосунок на VM без пересоздання?
- Що таке deployment slot в App Service?
- Як дати App Service чи ACA доступ до ACR без пароля?
- Як налаштувати alert на високе навантаження CPU?
