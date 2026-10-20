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
| `10.0.1.0` | network address: identifies the subnet itself in routing |
| `10.0.1.1` | default gateway: a virtual gateway provided by Azure's SDN, not a real router |
| `10.0.1.2`, `10.0.1.3` | reserved to map Azure DNS into the VNet |
| `10.0.1.255` | broadcast: reserved by the standard, even though VNets don't support broadcast |

That's why the first VM gets `10.0.1.4`.

- The DNS resolver VMs actually use is **`168.63.129.16`**, a virtual IP that's the same in every VNet. Azure also uses it for DHCP and VM agent health signals.
- **No broadcast or multicast** in VNets: software that relies on them for discovery or clustering doesn't work as-is.
- On a VM: `ip route` shows `default via 10.0.1.1`, and `resolvectl status` shows `168.63.129.16`.

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

**Peering** connects two VNets so their resources talk over **private IPs**, through the Microsoft backbone: no internet, no gateway, no encryption overhead, the same latency as inside one VNet.

**It's always two links, one per direction:**

```
vnet-demo ──(peering demo→peer)──► vnet-peer
vnet-demo ◄──(peering peer→demo)── vnet-peer
```

| State | Meaning |
|---|---|
| `Initiated` | only one side exists. **No traffic flows** |
| `Connected` | both sides exist. Traffic flows |
| `Disconnected` | the other side was deleted. Delete and recreate this side |

In Terraform this is two `azurerm_virtual_network_peering` resources:

```hcl
resource "azurerm_virtual_network_peering" "demo_to_peer" {
  name                      = "demo-to-peer"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.main.name
  remote_virtual_network_id = azurerm_virtual_network.peer.id
}

resource "azurerm_virtual_network_peering" "peer_to_demo" {
  name                      = "peer-to-demo"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.peer.name
  remote_virtual_network_id = azurerm_virtual_network.main.id
}
```

**Settings on each link:**

| Setting | What it allows | Typical use |
|---|---|---|
| `allow_virtual_network_access` | traffic between the two VNets (on by default) | always |
| `allow_forwarded_traffic` | traffic that didn't originate in the remote VNet, e.g. forwarded by a firewall there | hub-spoke with a firewall in the hub |
| `allow_gateway_transit` | the remote VNet may use **my** VPN/ExpressRoute gateway | set on the **hub's** link |
| `use_remote_gateways` | **I** use the remote VNet's gateway to reach on-prem | set on the **spoke's** link |

**Rules and limits:**
- **Address spaces must not overlap.** Overlapping VNets can't be peered at all, which is why address planning matters (section 15).
- **Non-transitive:** if A↔B and B↔C, A can't reach C through B. Solutions: a firewall or NVA in the hub with UDRs, a full mesh of peerings, Azure Virtual Network Manager (creates mesh or hub-spoke for you), or Virtual WAN.
- **Regional** (same region) or **global** (different regions). Also works across subscriptions and tenants.
- **Billed per GB** in both directions; global peering costs more.
- The `VirtualNetwork` service tag **includes the peered VNet**, so the default `AllowVnetInBound` rule lets it in (section 10).
- **Azure-provided DNS doesn't resolve VM names across peerings.** Use a private DNS zone linked to both VNets.

**Peering vs VNet-to-VNet VPN:** peering is faster, cheaper and simpler. A VPN gateway connection is encrypted (IPsec) and can be transitive through BGP, but it's slower and costs more. Choose peering unless you specifically need encryption in transit between VNets.

**Hub-spoke:** a central VNet (hub) with shared services (firewall, VPN gateway, Bastion), with application VNets (spokes) connected to it. Spokes talk to each other through the firewall in the hub, using UDRs.

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

## Going deeper

Interviews rarely stop at definitions. The follow-up questions are about how traffic actually flows and how you troubleshoot it. Sections 9, 10 and 16 come up most often.

### 9. Routing: how Azure decides where a packet goes

Every subnet gets **system routes** automatically: inside the VNet, to peered VNets, and `0.0.0.0/0` → Internet. **UDRs** (route tables) override them.

When several routes match, Azure picks in two steps:
1. **The longest prefix wins:** `10.1.0.0/16` beats `0.0.0.0/0` for `10.1.2.3`.
2. With equal prefixes: **UDR > BGP > system route**.

Next hop types in effective routes: `VnetLocal`, `VNetPeering`, `Internet`, `VirtualNetworkGateway` (VPN/ExpressRoute), `VirtualAppliance` (a firewall), `None` (drop).

Classic hub-spoke: a UDR `0.0.0.0/0 → VirtualAppliance <firewall IP>` on every spoke subnet forces all traffic through the hub's firewall.

### 10. NSG details

- **Stateful:** if inbound SSH is allowed, the reply goes out automatically. No return rule needed.
- A rule matches the **5-tuple**: source IP, source port, destination IP, destination port, protocol.
- Default rule names: `AllowVnetInBound`, `AllowAzureLoadBalancerInBound`, `DenyAllInBound`, `AllowVnetOutBound`, `AllowInternetOutBound`, `DenyAllOutBound`.
- **The `VirtualNetwork` tag includes peered VNets and on-prem ranges** from a VPN gateway, not just your own VNet. So `AllowVnetInBound` lets them in too.
- **ASGs** (application security groups): rules like "web → db on 5432" without IPs. VMs join an ASG through their NIC.

### 11. Outbound internet access: SNAT

A VM with only a private IP reaches the internet through **SNAT** (source address translation to a public IP). In order of precedence:

1. **NAT Gateway** on the subnet: wins over everything else for outbound;
2. a **public IP on the VM's NIC**;
3. **Load Balancer outbound rules**;
4. **default outbound access**: an implicit IP Azure picks for you. It's being retired, and new subnets are moving to "private by default".

**SNAT port exhaustion:** many outbound connections to the same destination use up the ports of one public IP, and new connections fail intermittently. The fix: a NAT Gateway (many more ports, scales with extra IPs), or connection reuse in the app.

### 12. DNS and the private endpoint trap

- VMs use Azure DNS at `168.63.129.16` by default.
- **Private DNS zones** give names to private resources and must be **linked** to every VNet that needs them.
- **The most common private endpoint failure:** the app still connects to the public IP. `mystorage.blob.core.windows.net` must resolve to the private IP through the `privatelink.blob.core.windows.net` zone, and that zone isn't linked to the VNet, or on-prem DNS doesn't forward to Azure. **A private endpoint without correct DNS doesn't work.**
- Hybrid DNS (on-prem ↔ Azure): **Azure DNS Private Resolver**.

### 13. Special subnets

| Service | Required subnet name | Size |
|---|---|---|
| VPN / ExpressRoute gateway | `GatewaySubnet` | `/27` recommended |
| Azure Bastion | `AzureBastionSubnet` | `/26` or larger |
| Azure Firewall | `AzureFirewallSubnet` | `/26` |

Some PaaS services need **subnet delegation** (App Service VNet integration, Container Apps, some databases): the subnet is dedicated to that service.

### 14. Hybrid connectivity

- **VPN Gateway:** site-to-site (office ↔ Azure over IPsec, through the internet) or point-to-site (individual laptops).
- **ExpressRoute:** a private line through a provider, not the internet. More predictable, more expensive.
- Spokes reach on-prem through the hub's gateway with **gateway transit** (section 6).

### 15. Address planning

- **Never overlap** with on-prem or with any VNet you might peer. Overlapping networks can't be peered, and fixing it means rebuilding.
- Use private ranges (RFC 1918): `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.
- Leave room: a `/16` per VNet, subnets sized for growth. Resizing a subnet with resources in it is hard or impossible.

### 16. Troubleshooting: "the VM can't reach X"

Answer in this order:

1. **Effective NSG rules** on the NIC: `az network nic list-effective-nsg`. Is something denying it?
2. **Effective routes:** `az network nic show-effective-route-table`. Where does the packet go?
3. **Network Watcher:** *IP flow verify* (would this packet be allowed, and by which rule), *Next hop* (where a packet to this IP goes), *Connection troubleshoot* (end-to-end test).
4. **DNS:** does the name resolve to the expected IP (section 12)?
5. **Flow logs:** what actually passed or was dropped. NSG flow logs are being retired in favor of **VNet flow logs**.

### 17. Terraform gotchas

- **Inline vs separate resources:** subnets inline in a VNet vs `azurerm_subnet`, rules inline in an NSG vs `azurerm_network_security_rule`. Never mix both styles for the same object: each will keep reverting the other.
- **Inline NSG rules are authoritative:** a rule added by hand is deleted on the next `apply` (Week 3, topic 7).
- **Peering is two resources**, one per direction (section 6).
- **Associations** (NSG ↔ subnet, NSG ↔ NIC) are separate Terraform resources, but not separate Azure objects, so they have no tags.

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
- How does Azure choose a route when several match?
- Is an NSG stateful? What does that mean for return traffic?
- What is SNAT port exhaustion, and how do you fix it?
- A private endpoint is set up, but the app still uses the public IP. Why?
- What do `allow_gateway_transit` and `use_remote_gateways` do?
- Why does peering need two links, and what does the `Initiated` state mean?
- A VM can't reach a database. Walk me through your troubleshooting.
