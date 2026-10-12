# Тиждень 4. Мережі Azure

Як побудована мережа в Azure і як пояснити, куди йде пакет.

## Терміни

| Абревіатура / термін | Розшифровка | Що це, одним реченням |
|---|---|---|
| **VNet** | Virtual Network | Ізольована приватна мережа в Azure, прив'язана до одного регіону |
| **Subnet** | | Діапазон адрес усередині VNet, куди підключаються ресурси |
| **CIDR** | Classless Inter-Domain Routing | Запис діапазону адрес: `10.0.0.0/16` |
| **NSG** | Network Security Group | Фаєрвол з правилами allow/deny на рівні subnet або NIC |
| **NIC** | Network Interface Card | Мережева карта VM, через неї VM підключена до subnet |
| **PIP** | Public IP | Публічна IP-адреса, яку прив'язують до NIC або балансувальника |
| **LB** | Load Balancer | Балансувальник рівня L4 (TCP/UDP) |
| **App Gateway** | Application Gateway | Балансувальник рівня L7 (HTTP), може мати WAF |
| **WAF** | Web Application Firewall | Захист від атак на вебзастосунки (SQL injection, XSS) |
| **NAT GW** | NAT Gateway | Вихід в інтернет для приватних ресурсів через фіксовану IP |
| **UDR** | User-Defined Route | Власне правило маршрутизації (route table) |
| **PE** | Private Endpoint | Приватна IP у вашій VNet для PaaS-сервісу (Storage, Key Vault) |
| **ASG** | Application Security Group | Логічна група VM, яку можна вказати в правилі NSG замість IP |

## Поняття, які треба вміти пояснити своїми словами

### 1. CIDR

Число після `/` показує, скільки перших бітів адреси зафіксовано. IPv4 має 32 біти.

```
10.0.0.0/16   зафіксовано 16 біт  →  2^(32−16) = 65 536 адрес
10.0.1.0/24   зафіксовано 24 біти →  2^(32−24) =    256 адрес
```

Чим більше число після `/`, тим менша мережа.

| Префікс | Адрес усього | Доступно в Azure |
|---|---|---|
| `/16` | 65 536 | 65 531 |
| `/24` | 256 | 251 |
| `/27` | 32 | 27 |
| `/28` | 16 | 11 |
| `/29` | 8 | 3, найменша підмережа |

### 2. П'ять зарезервованих адрес

У кожній підмережі Azure забирає 5 адрес. Для `10.0.1.0/24`:

| Адреса | Для чого |
|---|---|
| `10.0.1.0` | адреса мережі |
| `10.0.1.1` | шлюз за замовчуванням |
| `10.0.1.2`, `10.0.1.3` | DNS Azure |
| `10.0.1.255` | broadcast |

Тому перша VM отримує `10.0.1.4`.

### 3. NSG

Правило має: пріоритет (100–4096, менше число = вищий пріоритет), напрямок, протокол, порти, джерело, призначення, allow або deny. Перше правило, що підійшло, перемагає.

Правила за замовчуванням (пріоритет 65000+, їх не видалити, можна лише перекрити):
- **Inbound:** дозволено з VNet, дозволено від Azure Load Balancer, **решта заборонена**.
- **Outbound:** дозволено у VNet, **дозволено в інтернет**, решта заборонена.

**NSG на subnet і на NIC одночасно:**
- вхідний трафік: спочатку NSG підмережі, потім NSG карти;
- вихідний трафік: спочатку NSG карти, потім NSG підмережі.

Трафік проходить, лише якщо дозволений **обома**. У моєму проєкті NSG прив'язано і до subnet, і до NIC, тож правила збігаються.

**Service tags** замість IP: `Internet`, `VirtualNetwork`, `AzureLoadBalancer`, `Storage`, `AzureCloud`.

### 4. Public IP

- **Basic** SKU знято з підтримки (30 вересня 2025). Використовуйте **Standard**.
- Standard за замовчуванням **закритий**: без NSG, що дозволяє трафік, нічого не пройде.
- `Static` — адреса не змінюється, `Dynamic` — може змінитися після deallocate (лише Basic).

### 5. Балансувальники: що обрати

| Сервіс | Рівень | Масштаб | Коли |
|---|---|---|---|
| **Load Balancer** | L4 (TCP/UDP) | регіон | будь-який TCP-трафік, VM, VMSS |
| **Application Gateway** | L7 (HTTP/S) | регіон | маршрутизація за URL, SSL termination, WAF |
| **Front Door** | L7 | глобальний | кілька регіонів, CDN, WAF на краю мережі |
| **Traffic Manager** | DNS | глобальний | розподіл за DNS між регіонами |

### 6. VNet peering і hub-spoke

- **Peering** з'єднує дві VNet напряму через магістраль Microsoft. Адреси не повинні перетинатися.
- **Peering нетранзитивний:** якщо A↔B і B↔C, то A не бачить C.
- **Hub-spoke:** центральна VNet (hub) зі спільними сервісами (фаєрвол, VPN gateway, Bastion), до неї під'єднані VNet застосунків (spokes). Spoke між собою ходять через фаєрвол у hub за допомогою UDR.

```
        spoke-app
            │
spoke-db ── hub ── on-premises (VPN / ExpressRoute)
            │
       spoke-mgmt
```

### 7. Доступ до PaaS-сервісів

| | Service endpoint | Private endpoint |
|---|---|---|
| Що це | Трафік з subnet до сервісу йде магістраллю Azure | Сервіс отримує приватну IP у вашій subnet |
| IP сервісу | лишається публічною | приватна, з вашої VNet |
| Доступ з on-premises | ні | так, через VPN / ExpressRoute |
| DNS | не потрібен | потрібна private DNS zone (`privatelink.blob.core.windows.net`) |
| Ціна | безкоштовно | платно |

Сьогодні рекомендують private endpoint.

### 8. Вихід в інтернет і доступ до VM

- **NAT Gateway:** вихідний трафік з приватних VM через фіксовану IP. Default outbound access для нових підмереж Azure поступово вимикає, тож явний вихід стає обов'язковим.
- **Azure Bastion:** SSH/RDP до VM через портал, без публічної IP на VM і без відкритого порту 22.

**У моєму проєкті** SSH (порт 22) відкритий для всього інтернету (`source_address_prefix = "*"`). Мінімальне виправлення — обмежити своєю IP.

## Terraform-приклад

```hcl
resource "azurerm_virtual_network" "main" {
  name                = "vnet-demo"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet("10.0.0.0/16", 8, 1)]   # 10.0.1.0/24
}
```

`cidrsubnet(prefix, newbits, netnum)`: до `/16` додаємо 8 біт → `/24`, номер підмережі 1 → `10.0.1.0/24`.

## Команди напам'ять

```
az network vnet list -o table
az network vnet subnet list -g <rg> --vnet-name <vnet> -o table
az network nsg rule list -g <rg> --nsg-name <nsg> -o table
az network nic list-effective-nsg -g <rg> -n <nic>
az network nic show-effective-route-table -g <rg> -n <nic> -o table
az network watcher test-ip-flow ...       # чи пропустить NSG конкретний пакет
```

## Перевірка себе

Намалюйте hub-spoke з NSG і поясніть, через що пройде HTTP-запит з інтернету до VM: public IP → NSG підмережі → NSG карти → VM. Порахуйте, скільки VM влізе в `/27`.

## Питання співбесіди

- Скільки придатних адрес у `/28` і чому?
- Як обробляються NSG, прикріплені і до subnet, і до NIC?
- Які правила NSG є за замовчуванням?
- Чому peering нетранзитивний і як це обходять?
- Private endpoint чи service endpoint: різниця?
- Load Balancer, Application Gateway чи Front Door: коли що?
- Як дати VM вихід в інтернет без публічної IP?
- Як безпечно дістатися до VM по SSH?
