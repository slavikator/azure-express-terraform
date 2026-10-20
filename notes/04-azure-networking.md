# Week 4. Azure networking

How networking is built in Azure, and how to explain where a packet goes.

## Terms

| Abbreviation / term | Stands for | What it is, in one sentence |
|---|---|---|
| **VNet** | Virtual Network | An isolated private network in Azure, tied to one region |
| **Subnet** | | An address range inside a VNet where resources connect |
| **CIDR** | Classless Inter-Domain Routing | Notation for an address range: `10.0.0.0/16` |
| **NSG** | Network Security Group | A firewall with allow/deny rules at the subnet or NIC level |
| **NIC** | Network Interface Card | A VM's network card; it connects the VM to a subnet |
| **PIP** | Public IP | A public IP address attached to a NIC or a load balancer |
| **LB** | Load Balancer | A layer 4 (TCP/UDP) load balancer |
| **App Gateway** | Application Gateway | A layer 7 (HTTP) load balancer, can have a WAF |
| **WAF** | Web Application Firewall | Protection against attacks on web apps (SQL injection, XSS) |
| **NAT GW** | NAT Gateway | Internet egress for private resources through a fixed IP |
| **UDR** | User-Defined Route | A custom routing rule (route table) |
| **PE** | Private Endpoint | A private IP in your VNet for a PaaS service (Storage, Key Vault) |
| **ASG** | Application Security Group | A logical group of VMs that can be used in an NSG rule instead of IPs |

## Concepts you need to explain in your own words

### 1. CIDR

The number after `/` shows how many leading bits of the address are fixed. IPv4 has 32 bits.

```
10.0.0.0/16   16 bits fixed  →  2^(32−16) = 65,536 addresses
10.0.1.0/24   24 bits fixed  →  2^(32−24) =    256 addresses
```

The bigger the number after `/`, the smaller the network.

| Prefix | Total addresses | Usable in Azure |
|---|---|---|
| `/16` | 65,536 | 65,531 |
| `/24` | 256 | 251 |
| `/27` | 32 | 27 |
| `/28` | 16 | 11 |
| `/29` | 8 | 3, the smallest subnet |

### 2. Five reserved addresses

Azure takes 5 addresses in every subnet. For `10.0.1.0/24`:

| Address | What it's for |
|---|---|
| `10.0.1.0` | network address |
| `10.0.1.1` | default gateway |
| `10.0.1.2`, `10.0.1.3` | Azure DNS |
| `10.0.1.255` | broadcast |

That's why the first VM gets `10.0.1.4`.

### 3. NSG

A rule has: a priority (100–4096, a lower number = higher priority), direction, protocol, ports, source, destination, allow or deny. The first matching rule wins.

Default rules (priority 65000+; they can't be deleted, only overridden):
- **Inbound:** allowed from the VNet, allowed from Azure Load Balancer, **everything else denied**.
- **Outbound:** allowed to the VNet, **allowed to the internet**, everything else denied.

**An NSG on both the subnet and the NIC:**
- inbound traffic: first the subnet's NSG, then the NIC's NSG;
- outbound traffic: first the NIC's NSG, then the subnet's NSG.

Traffic passes only if **both** allow it. In my project, the NSG is attached to both the subnet and the NIC, so the rules are the same.

**Service tags** instead of IPs: `Internet`, `VirtualNetwork`, `AzureLoadBalancer`, `Storage`, `AzureCloud`.

### 4. Public IP

- The **Basic** SKU is retired (September 30, 2025). Use **Standard**.
- Standard is **closed** by default: nothing gets through without an NSG that allows the traffic.
- `Static`: the address doesn't change. `Dynamic`: it can change after deallocation (Basic only).

### 5. Load balancers: what to choose

| Service | Layer | Scope | When |
|---|---|---|---|
| **Load Balancer** | L4 (TCP/UDP) | regional | any TCP traffic, VMs, VMSS |
| **Application Gateway** | L7 (HTTP/S) | regional | URL-based routing, SSL termination, WAF |
| **Front Door** | L7 | global | multiple regions, CDN, WAF at the network edge |
| **Traffic Manager** | DNS | global | DNS-based distribution between regions |

### 6. VNet peering and hub-spoke

- **Peering** connects two VNets directly over the Microsoft backbone. Address spaces must not overlap.
- **Peering is non-transitive:** if A↔B and B↔C, A doesn't see C.
- **Hub-spoke:** a central VNet (hub) with shared services (firewall, VPN gateway, Bastion), with application VNets (spokes) connected to it. Spokes talk to each other through the firewall in the hub, using UDRs.

```
        spoke-app
            │
spoke-db ── hub ── on-premises (VPN / ExpressRoute)
            │
       spoke-mgmt
```

### 7. Access to PaaS services

| | Service endpoint | Private endpoint |
|---|---|---|
| What it is | Traffic from the subnet to the service goes over the Azure backbone | The service gets a private IP in your subnet |
| The service's IP | stays public | private, from your VNet |
| Access from on-premises | no | yes, through VPN / ExpressRoute |
| DNS | not needed | needs a private DNS zone (`privatelink.blob.core.windows.net`) |
| Price | free | paid |

Today, private endpoints are recommended.

### 8. Internet egress and access to VMs

- **NAT Gateway:** outbound traffic from private VMs through a fixed IP. Azure is gradually turning off default outbound access for new subnets, so explicit egress is becoming mandatory.
- **Azure Bastion:** SSH/RDP to a VM through the portal, without a public IP on the VM and without an open port 22.

**In my project,** SSH (port 22) is open to the whole internet (`source_address_prefix = "*"`). The minimal fix is to restrict it to your own IP.

## Terraform example

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

`cidrsubnet(prefix, newbits, netnum)`: add 8 bits to `/16` → `/24`, subnet number 1 → `10.0.1.0/24`.

## Commands to know by heart

```
az network vnet list -o table
az network vnet subnet list -g <rg> --vnet-name <vnet> -o table
az network nsg rule list -g <rg> --nsg-name <nsg> -o table
az network nic list-effective-nsg -g <rg> -n <nic>
az network nic show-effective-route-table -g <rg> -n <nic> -o table
az network watcher test-ip-flow ...       # will the NSG let a specific packet through
```

## Check yourself

Draw a hub-spoke network with NSGs and explain what an HTTP request from the internet passes through on its way to a VM: public IP → subnet NSG → NIC NSG → VM. Work out how many VMs fit in a `/27`. The hands-on exercise is in [`practice-04-networking.md`](practice-04-networking.md).

## Interview questions

- How many usable addresses are in a `/28`, and why?
- How are NSGs attached to both the subnet and the NIC evaluated?
- What are the default NSG rules?
- Why is peering non-transitive, and how do people work around it?
- Private endpoint or service endpoint: what's the difference?
- Load Balancer, Application Gateway or Front Door: when to use which?
- How do you give a VM internet egress without a public IP?
- How do you safely reach a VM over SSH?
