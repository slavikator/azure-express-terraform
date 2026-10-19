# Week 5. Expressions and meta-arguments

How to write flexible code without copy-paste.

## Terms

| Term | What it is, in one sentence |
|---|---|
| **Meta-argument** | An argument that works on any resource: `count`, `for_each`, `depends_on`, `lifecycle`, `provider` |
| **`count`** | Create N identical copies of a resource, addressed by index `[0]`, `[1]` |
| **`for_each`** | Create a copy for each element of a map or set, addressed by key `["web"]` |
| **`dynamic`** | Generate nested blocks (e.g. `security_rule`) from a collection |
| **`lifecycle`** | Settings for how Terraform creates, changes and deletes a resource |
| **Splat** | The expression `resource.name[*].id`, which collects an attribute from all copies |

## Concepts you need to explain in your own words

### 1. `count`

```hcl
resource "azurerm_public_ip" "pip" {
  count               = 2
  name                = "pip-${count.index}"
  ...
}
# addresses: azurerm_public_ip.pip[0], azurerm_public_ip.pip[1]
```

Conditional creation:
```hcl
count = var.create_bastion ? 1 : 0
```

**The problem with `count` over a list:**
```hcl
variable "names" { default = ["web", "api", "db"] }
count = length(var.names)
```
If you remove `"web"`, `api` moves from `[1]` to `[0]`, and `db` from `[2]` to `[1]`. Terraform will **recreate** both, because their indexes changed.

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
# addresses: azurerm_linux_virtual_machine.vm["web"], ...["api"]
```

Removing `web` affects only `web`, because the address is tied to the key, not the position.

- `for_each` takes a **map** or a **set of strings**, not a list: `for_each = toset(var.names)`.
- The keys must be known during `plan`, so they can't come from attributes that are only known after `apply`.

**The rule:** `count` for "0 or 1" and for fully identical copies. `for_each` for everything else.

### 3. `dynamic`

Generates nested blocks inside **one** resource:

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

The difference: `for_each` on a resource creates **several resources**, while `dynamic` creates **several blocks in one resource**.

### 4. Expressions

```hcl
# conditional expression
size = var.env == "prod" ? "Standard_D2s_v5" : "Standard_B1s"

# for: transform a collection
upper_names = [for n in var.names : upper(n)]
name_to_id  = { for k, v in azurerm_subnet.this : k => v.id }
only_prod   = [for n in var.envs : n if n != "dev"]

# splat
pip_ids = azurerm_public_ip.pip[*].id
```

### 5. Useful functions

| Function | Example | Result |
|---|---|---|
| `merge` | `merge(local.tags, { role = "web" })` | merge maps |
| `lookup` | `lookup(var.sizes, var.env, "Standard_B1s")` | a value from a map, or a default |
| `cidrsubnet` | `cidrsubnet("10.0.0.0/16", 8, 2)` | `10.0.2.0/24` |
| `try` | `try(var.config.port, 80)` | the value, or a fallback if there's an error |
| `coalesce` | `coalesce(var.name, "default")` | the first non-empty value |
| `format` | `format("vm-%s-%02d", "web", 1)` | `vm-web-01` |
| `jsonencode` | `jsonencode({ a = 1 })` | a JSON string |
| `base64encode` | for `custom_data` | |
| `file`, `templatefile` | `templatefile("init.sh", { port = 3000 })` | file contents with substitution |
| `toset`, `tolist`, `tomap` | type conversions | |

`terraform console` is a convenient place to test expressions.

### 6. `lifecycle`

```hcl
lifecycle {
  create_before_destroy = true
  prevent_destroy       = true
  ignore_changes        = [tags, custom_data]
  replace_triggered_by  = [azurerm_key_vault_secret.app.version]
}
```

| Argument | What it does | When |
|---|---|---|
| `create_before_destroy` | Creates the new resource first, then deletes the old one | To minimize downtime on replace. Needs unique names |
| `prevent_destroy` | `plan` fails if the resource would be deleted | Databases, the state storage, Key Vault |
| `ignore_changes` | Ignore changes to the listed attributes | Attributes someone else changes: tags from policies, an image deployed by CI |
| `replace_triggered_by` | Recreate the resource when another resource changes | Restart a VM after a configuration change |

**In my project:** `ignore_changes = [custom_data]` on the VM. Without it, changing the `custom_data` text would recreate the VM, because cloud-init can't be changed on a machine that's already running. But for the same reason, text changes never reached the VM.

### 7. Checks

```hcl
variable "env" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  ...
  lifecycle {
    precondition {
      condition     = var.env != "prod" || var.vm_size != "Standard_B1s"
      error_message = "prod needs a bigger VM."
    }
  }
}
```

- `validation`: a check on an input variable.
- `precondition`: a check before the resource is created.
- `postcondition`: a check afterwards, with access to `self`.

## Check yourself

Rewrite your project's NSG with `dynamic` from a map in a variable. Create two VMs with `for_each`. Remove one from the map and make sure `plan` touches only that one.

## Interview questions

- `count` vs `for_each`: what's the difference, and when to use which?
- Why does removing an item from a `count` list affect other resources?
- `dynamic` vs `for_each` on a resource?
- When is `ignore_changes` appropriate? Give an example.
- What does `create_before_destroy` do, and what are its limitations?
- How do you protect a critical resource from accidental deletion?
- What does `replace_triggered_by` do?
- Why must `for_each` keys be known during `plan`?
