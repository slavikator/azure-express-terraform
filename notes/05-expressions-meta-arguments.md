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

## Going deeper

### 8. The `count` problem, step by step

Why removing one list item touches others: with `count`, the **address** of each copy is its **position**.

```hcl
variable "names" { default = ["a", "b", "c"] }

resource "azurerm_public_ip" "pip" {
  count = length(var.names)
  name  = "pip-${var.names[count.index]}"
  ...
}
```

| Address | Before: `["a","b","c"]` | After removing `"a"`: `["b","c"]` | Plan |
|---|---|---|---|
| `pip[0]` | `pip-a` | `pip-b` | `-/+`: the name changes, so it's recreated |
| `pip[1]` | `pip-b` | `pip-c` | `-/+` |
| `pip[2]` | `pip-c` | gone | `-` |

You wanted to delete one IP; Terraform deletes three and creates two. Every `-/+` on a public IP also means a **new IP address**. With `for_each`, the address is the **key** (`pip["a"]`), so removing `"a"` touches only `pip["a"]`.

### 9. Referring to copies

| | `count` | `for_each` |
|---|---|---|
| One copy | `azurerm_public_ip.pip[0].id` | `azurerm_public_ip.pip["a"].id` |
| All copies, as a list | `azurerm_public_ip.pip[*].id` | `values(azurerm_public_ip.pip)[*].id` |
| All copies, as a map | `{ for i, p in azurerm_public_ip.pip : i => p.id }` | `{ for k, p in azurerm_public_ip.pip : k => p.id }` |
| Inside the block | `count.index` | `each.key`, `each.value` |

- A resource with `for_each` is a **map** of objects, so `[*]` doesn't work on it directly. Use `values(...)` or a `for` expression.
- With `for_each` over a **set**, `each.key` and `each.value` are the same string.
- `count` and `for_each` can't be used on the same resource.
- One copy referring to a matching copy of another resource: `network_interface_ids = [azurerm_network_interface.nic[each.key].id]`.

### 10. `for` expressions in detail

```hcl
[for s in var.list : upper(s)]                    # list → list
[for k, v in var.map : "${k}=${v}"]               # map → list
{ for s in var.list : s => length(s) }            # list → map
{ for k, v in var.map : k => v if v != "" }       # filter with if
{ for vm in var.vms : vm.env => vm.name... }      # group: "..." collects duplicates into lists
```

- Square brackets produce a **list**, curly braces a **map**.
- In a map, every key must be unique, unless you use `...` to group.

### 11. Omitting an argument with `null`

`null` means "as if this argument wasn't written":

```hcl
public_ip_address_id = var.public ? azurerm_public_ip.pip[0].id : null
```

This is how you make arguments conditional without duplicating the whole block.

### 12. `dynamic` details

- Inside `content`, the iterator is named after the block (`security_rule.key`, `security_rule.value`). Rename it with `iterator = rule`.
- `dynamic` blocks can be nested.
- **Don't overuse it.** A `dynamic` block with two static items is harder to read than two plain blocks. Use it when the list really comes from a variable.
- Refactoring rules into `dynamic` should produce **`No changes`**. If the plan shows changes, the generated blocks differ from the old ones (a different name, priority or port).

### 13. `lifecycle` gotchas

- **`prevent_destroy` only works while the block is in the code.** If someone deletes the whole resource block, the protection is deleted with it, and Terraform plans the destroy. It also doesn't stop deletion from the Portal. For real protection, add an Azure **resource lock** (`CanNotDelete`), as on `rg-tfstate`.
- **`create_before_destroy` needs unique names:** the new copy exists next to the old one, so a fixed `name` collides. Terraform also applies it automatically to the resources the replaced one depends on.
- **`ignore_changes = all`:** Terraform creates the resource and never updates it afterwards.
- **`replace_triggered_by`** can only reference managed resources or their attributes, not variables. To trigger on a variable, put it in a `terraform_data` resource (`input = var.x`) and reference that.

### 14. Validation, conditions and `check`

| | Where | When | On failure |
|---|---|---|---|
| `validation` | `variable` block | start of `plan` | error, stops |
| `precondition` | `lifecycle` of a resource or output | before the resource is planned | error, stops |
| `postcondition` | `lifecycle` of a resource | after it's created or read; can use `self` | error, stops |
| `check` block (1.5+) | top level | end of `plan` and `apply` | **warning only**, doesn't stop |

`check` is useful for health checks, e.g. "the website returns 200", that should be reported but shouldn't block deployment.

### 15. Common errors

| Error | Cause | Fix |
|---|---|---|
| `The "for_each" value depends on resource attributes that cannot be determined until apply` | `for_each` keys come from a computed value (an ID, an IP) | build keys from variables or constants; computed values can go in `each.value` |
| `Invalid for_each argument ... a set of strings` | a list was passed to `for_each` | `toset(var.list)` |
| `Missing resource instance key` | referring to a resource with `count`/`for_each` without `[...]` | add the index or key |
| `Duplicate object key` in a `for` | two items produce the same map key | make keys unique, or group with `...` |

### 16. Migrating `count` → `for_each` without recreation

Changing the meta-argument changes every address: `pip[0]` → `pip["a"]`. Use `moved` blocks so nothing is recreated:

```hcl
moved {
  from = azurerm_public_ip.pip[0]
  to   = azurerm_public_ip.pip["a"]
}
```

One block per copy. The plan should show `has moved to` and no `-/+`.

## Check yourself

Rewrite your project's NSG with `dynamic` from a map in a variable. Create two VMs with `for_each`. Remove one from the map and make sure `plan` touches only that one. The hands-on exercise is in [`practice-05-expressions.md`](practice-05-expressions.md).

## Terraform types for JavaScript developers

| Terraform | JavaScript / TypeScript |
|---|---|
| `list(string)` | `string[]` |
| `set(string)` | `Set<string>`, but sorted and without indexes |
| `map(string)` | a plain object `Record<string, string>`: string keys, **one** value type, iterated in **sorted** key order |
| `object({ a = string, b = number })` | a TypeScript interface: fixed fields, each with its own type |
| `tuple([string, number])` | `[string, number]` |
| `[for x in list : ...]` | `array.map(...)` |
| `lookup(m, k, "def")` | `m[k] ?? "def"` (a plain `m[k]` on a missing key is an **error** in Terraform) |
| `merge(a, b)` | `{ ...a, ...b }` |
| `cond ? a : b` | the same |

## Interview answers

**What are meta-arguments?**
> Arguments built into Terraform that work on any resource regardless of provider: `count`, `for_each`, `depends_on`, `lifecycle` and `provider`. They control how Terraform creates and manages the resource rather than its cloud configuration, so they're never sent to Azure. Modules accept `count`, `for_each`, `depends_on` and `providers`.

**`count` vs `for_each`?**
> With `count`, a copy's address is its position, so removing an item from the middle of a list shifts every later item and recreates them. With `for_each` over a map or set, the address is the key, so only the removed key is affected. I use `count` for "0 or 1" or truly identical copies, and `for_each` for everything else. Switching between them changes every address, so it needs `moved` blocks.

**Why does `for_each` need a set or a map?**
> Each key becomes part of a copy's address, so keys must be unique. A list can contain duplicates and has positions, so it's converted with `toset()`, which removes duplicates. Keys must also be known at plan time, so they can't come from attributes computed during apply.

**How do you refer to all copies of a `for_each` resource?**
> A `for_each` resource is a map, so the splat `[*]` doesn't work on it directly. I use a `for` expression, `{ for k, r in azurerm_x.y : k => r.id }`, which keeps the keys, or `values(azurerm_x.y)[*].id` for a plain list.

**`dynamic` vs `for_each` on a resource?**
> `for_each` on a resource creates several resources. A `dynamic` block creates several nested blocks inside one resource, like NSG rules from a map, with the current item named after the block (`security_rule.key`, `.value`). Moving existing blocks into `dynamic` must produce `No changes`.

**`validation` vs `precondition`?**
> Both stop at `plan`, before anything reaches Azure. A `validation` belongs to a variable and checks its value for every use. A `precondition` belongs to a resource, can use other variables, resources and data sources, and expresses a rule about that specific resource, like "this VM must be B-series". A `check` block only warns.

**Does `prevent_destroy` fully protect a resource?**
> No. It makes `plan` fail if the resource would be destroyed, but only while the block is in the code: deleting the whole resource block deletes the protection too, and it doesn't stop deletion from the Portal. Real protection is an Azure resource lock (`CanNotDelete`); using both catches code mistakes early and everything else in Azure.

**Conditional expressions and `lookup`?**
> `cond ? a : b` picks a value, both sides of the same type; combined with `count = cond ? 1 : 0` it creates a resource conditionally, and `null` omits an argument. With more than two options, a map with `lookup(map, key, default)` is clearer than nested conditionals.

## Interview questions

- `count` vs `for_each`: what's the difference, and when to use which?
- Why does removing an item from a `count` list affect other resources?
- `dynamic` vs `for_each` on a resource?
- When is `ignore_changes` appropriate? Give an example.
- What does `create_before_destroy` do, and what are its limitations?
- How do you protect a critical resource from accidental deletion?
- What does `replace_triggered_by` do?
- Why must `for_each` keys be known during `plan`?
- How do you migrate a resource from `count` to `for_each` without recreating it?
- How do you refer to all copies of a resource created with `for_each`?
- How do you make an argument optional in a resource without duplicating the block?
- Does `prevent_destroy` fully protect a resource? What else would you use?
- `validation`, `precondition`, `postcondition`, `check`: what's the difference?
