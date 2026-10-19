# Week 1. Azure fundamentals

What you need to know by heart before moving on.

## Abbreviations

| Abbreviation | Stands for | What it is, in one sentence |
|---|---|---|
| **ARM** | Azure Resource Manager | Azure's single API, used by the portal, `az` and Terraform |
| **RG** | Resource Group | A logical container for resources. Deleting an RG deletes everything inside |
| **RBAC** | Role-Based Access Control | Permissions in the form "who + role + scope" |
| **SP** | Service Principal | An account for a program (CI, a script), not a person |
| **MI** | Managed Identity | An SP managed by Azure, with no secrets. Works only for resources in Azure |
| **Entra ID** | formerly **Azure AD (AAD)** | The directory of users and applications. You'll see both names |
| **AZ** | Availability Zone | A physically separate datacenter within a region |
| **OIDC** | OpenID Connect | Token-based sign-in without a password. This is how GitHub signs in to Azure without a secret |
| **MFA** | Multi-Factor Authentication | Sign-in with a second factor. This is exactly why CI can't sign in as your account |
| **CLI** | Command-Line Interface | Here it means `az` |

## Concepts you need to explain in your own words

### 1. Hierarchy

```
Tenant (Entra ID)
└── Management Group      ← optional level
    └── Subscription      ← billing account and limits boundary
        └── Resource Group
            └── Resource
```

Costs are counted at the subscription level.

#### Tenant vs subscription: how to answer in an interview

> A tenant is an instance of Entra ID, the identity boundary: users, groups and service principals live there, and authentication happens there. A subscription is the resource and billing boundary: resources are created there, costs are counted, and quotas apply. One tenant can have many subscriptions, but each subscription trusts only one tenant. Access to resources is granted by Azure RBAC roles at the subscription level or below. Entra ID roles, such as Global Administrator, manage identities and don't grant access to resources by themselves.

If the interviewer wants to go deeper:

- a subscription can be moved to another tenant, but then all role assignments disappear, because the old tenant's principals no longer exist for it;
- a Global Administrator can temporarily give themselves access to all subscriptions through "Elevate access". This option exists precisely because there's no such access by default.

Two separate role systems that are easy to mix up:

| | Entra ID roles | Azure RBAC roles |
|---|---|---|
| Where they apply | in the tenant (Entra ID) | on resources: management group, subscription, RG, resource |
| Examples | Global Administrator, User Administrator | Owner, Contributor, Reader |
| What they manage | users, groups, applications | Azure resources |

Subscriptions do **not** inherit roles from the tenant. RBAC is inherited through management groups: a role on the Tenant Root Group applies to all subscriptions under it.

### 2. RBAC: three parts

Every role assignment answers three questions:

| Question | Answer |
|---|---|
| **Who?** | security principal (user, group, SP, MI) |
| **What can they do?** | role (Reader, Contributor, Owner) |
| **Where?** | scope (subscription, group, resource) |

Permissions are **inherited downward**: a role on a subscription applies to every RG in it. They don't apply upward: a Contributor on an RG can't create a new RG, because groups are created at the subscription level.

**Security principal** is the general name for anything that can be given a role:

```
Security principal
├── User               a person: slavikator@gmail.com
├── Group              a group of people or other principals
├── Service principal  a program: github-actions-terraform
└── Managed identity   an Azure resource (VM, App Service); technically also a service principal
```

- **Security principal** is the category, and a **service principal** is one kind of it.
- In `az role assignment list`, the kind is shown in the `principalType` field (`User`, `Group`, `ServicePrincipal`), and `principalId` is that principal's object ID.
- In practice, roles are given to **groups** rather than individuals: access is added and removed through group membership.

#### RBAC role inheritance: how to answer in an interview

```
Management group  →  Subscription  →  Resource group  →  Resource
```

> RBAC roles are inherited top-down through the hierarchy: management group → subscription → resource group → resource. A role assignment at any level applies to that level and everything below it. Permissions from different assignments add up: if I have Reader on the subscription and Contributor on a group, I have Contributor in that group. You can't restrict an inherited permission at a lower level; only deny assignments, which Azure itself sets, take precedence. A role assignment lives at its scope: when a group is deleted, the assignments on it and its resources disappear, but assignments on the subscription remain.

What's easy to mix up:

- A **role** (role definition, e.g. Contributor) and a **role assignment** ("this principal has Contributor on this scope"). When a group is deleted, the assignments disappear, not the roles themselves.
- The group is **inside the subscription**, not the other way around. So deleting a group doesn't touch subscription-level assignments.

You can see this in the "Restricted robot" exercise: the robot's Reader and Contributor on `rg-practice-rbac` disappeared along with the group, while the Contributor of the two old SPs on the subscription stayed.

The **least privilege** principle: grant a role at the lowest sufficient level. For example, Contributor on one project RG, not on the whole subscription.

### 3. Three basic roles

| Role | Resources | Assign roles |
|---|---|---|
| **Owner** | ✅ everything | ✅ |
| **Contributor** | ✅ everything | ❌ |
| **Reader** | view only | ❌ |

Plus **User Access Administrator**: assigns roles but doesn't manage resources.

#### Why Contributor can't assign roles: how to answer in an interview

> To prevent privilege escalation: if a Contributor could assign roles, they'd give themselves Owner, and the difference between the roles would disappear. So Contributor is allowed everything except `Microsoft.Authorization/*/Write` and `Delete` actions, i.e. access management. This also implements separation of duties: managing resources is separate from managing access. Roles can be assigned by Owner, User Access Administrator and Role Based Access Control Administrator, and the last one can be restricted with conditions on which roles it may assign.

Terms: **privilege escalation** means raising your own privileges; **separation of duties** means splitting responsibilities.

How it works: Contributor has `actions: ["*"]`, and `notActions` lists exceptions, the main ones being:

```
Microsoft.Authorization/*/Write
Microsoft.Authorization/*/Delete
Microsoft.Authorization/elevateAccess/Action
```

To check: `az role definition list --name Contributor --query "[].permissions[].notActions" -o json`

Who can assign roles:

| Role | Resources | Roles |
|---|---|---|
| **Owner** | ✅ | ✅ |
| **User Access Administrator** | ❌ | ✅ |
| **Role Based Access Control Administrator** | ❌ | ✅, can be restricted with conditions (which roles, and to whom) |
| **Contributor** | ✅ | ❌ |

**The consequence for Terraform:** an SP with the Contributor role can't create an `azurerm_role_assignment`. `apply` fails with `AuthorizationFailed` on `Microsoft.Authorization/roleAssignments/write`. The safest fix is to give the Terraform SP the Role Based Access Control Administrator role, with a condition that only allows assigning the roles you need.

### 4. App registration and service principal

| | App registration (application object) | Service principal |
|---|---|---|
| What it is | The application's "passport" | The application's "instance" in a specific tenant |
| What it stores | Name, **secrets**, certificates, federated credentials | **RBAC roles** |
| In my project | `github-actions-terraform`, where `AZURE_CLIENT_SECRET` lives | The same `appId`, but this is where the Contributor role is assigned |

That's why `az ad sp show` shows an empty `passwordCredentials`: the secret is in the app registration (`az ad app credential list --id <appId>`).

#### App registration vs service principal: how to answer in an interview

> An app registration is the global definition of an application, its "passport": name, `appId`, secrets, certificates, federated credentials. It exists in one home tenant. A service principal is the application's local instance in a specific tenant, its "account". This is what RBAC roles are assigned to, and what the application acts as. They share an `appId` but have different object IDs. For a single-tenant application they come as a pair, and `az ad sp create-for-rbac` creates both at once. For a multi-tenant application, one app registration has a service principal in every tenant where it's used.

If the interviewer wants to go deeper:

- deleting an app registration also deletes its service principal;
- a managed identity has **only** a service principal, with no app registration, so it has no secrets at all.

You can see this in the "Restricted robot" exercise: `sp-practice` had the `appId` `0dc751b6-...` in both the app registration and the service principal, while the service principal's object ID was different, `48907eff-...`.

Three identifiers that are easy to mix up:

| Name | Where you see it |
|---|---|
| `appId` (client ID) | `ARM_CLIENT_ID`, `principalName` in the role list |
| the SP's own object ID | `principalId` in the role list, `caller` in the activity log |
| tenant ID | `ARM_TENANT_ID` |

How an SP proves who it is:

1. **Client secret**, i.e. a password. The simplest and least secure way.
2. **Certificate.** More secure, but inconvenient to administer.
3. **Federated credential (OIDC).** There's no password; Azure trusts a token from GitHub. The recommended way.

#### Why OIDC is better than a client secret: how to answer in an interview

> There's no long-lived secret that can be stolen. Instead of a password, GitHub issues a short-lived token for each run, and Azure checks it against the federated credential: who issued the token (issuer), and for which repository, branch or environment (subject). The token lives for minutes and is only accepted from the allowed place, so even if intercepted it's nearly useless. You also don't need to store and rotate a password, and CI won't break because of an expired secret. GitHub only stores non-secret identifiers: client ID, tenant ID, subscription ID.

| | Client secret | OIDC |
|---|---|---|
| What's stored in GitHub | a password | only IDs: client, tenant, subscription |
| Lifetime | months | minutes |
| Where it can be used from | anywhere | only from the specified repo, branch or environment |
| Rotation | by hand, or CI breaks | not needed |

A federated credential is a rule with three fields:

| Field | Example |
|---|---|
| Issuer | `https://token.actions.githubusercontent.com` |
| Subject | `repo:slavikator/azure-express-terraform:ref:refs/heads/main` |
| Audience | `api://AzureADTokenExchange` |

More detail and how to set it up: `08-security-identity.md`, section 4.

### 5. Service principal or managed identity

- The code runs **in Azure** (VM, App Service, Function) → **managed identity**.
- The code runs **outside Azure** (GitHub Actions, a laptop) → **service principal**, preferably with OIDC.

The criterion is **where the code runs**, not what it calls. Both MI and SP can access Key Vault, Storage, Microsoft Graph, and anything else that accepts Entra ID tokens.

#### Service principal or managed identity: how to answer in an interview

> The criterion is where the code runs. If it's on an Azure resource (VM, App Service, Functions, Container Apps, AKS), I use a managed identity: Azure manages the credentials, there are no secrets, and nothing needs rotating. If the code runs outside Azure (GitHub Actions, on-premises, another cloud), managed identity isn't available, so I use a service principal, preferably with a federated credential (OIDC), to also avoid a password. Technically a managed identity is also a service principal, but without an app registration, and Azure manages it.

If the interviewer wants to go deeper:

- a **system-assigned** MI lives with its resource and is deleted with it; a **user-assigned** MI is a separate resource that can be attached to several resources;
- a GitHub Actions **self-hosted runner** running on a VM in Azure can use that VM's MI instead of an SP. Again, what decides is where the code runs.

### 6. Region, availability zone, region pair

- **Region**: a geographic location (`swedencentral`).
- **AZ**: separate datacenters within a region; they protect against the failure of one of them.
- **Region pair**: for disaster recovery.

### 7. ARM as the single entry point

The portal, `az` and Terraform all turn into a request to the ARM API. That's why Terraform doesn't see a resource created in the portal until you `import` it, and that's exactly why state can drift from reality.

### 8. Who deleted a resource

#### How to answer in an interview

> For Azure resources, the activity log: it records all control-plane operations through ARM. I filter for delete operations and look at the `caller` field. For a person it's an email; for a service principal or managed identity it's an object ID, which I resolve with `az ad sp show`. If it's the pipeline's SP, I then look for the matching CI run by time. The activity log is only kept for 90 days, so in production it's exported through diagnostic settings to Log Analytics and searched with a KQL query on the `AzureActivity` table. If data inside a resource was deleted (a blob, a secret), the activity log won't show it: you need resource logs. Deletions of users and applications are visible in the Entra ID audit logs. And to make sure critical things can't be deleted at all, I use resource locks and restrict permissions.

#### Activity log

```
az monitor activity-log list --offset 7d \
  --query "[?contains(operationName.value,'delete')].{time:eventTimestamp, op:operationName.value, resource:resourceId, status:status.value, caller:caller}" \
  -o table
```

- **`caller`**: who it was. An email for a person, an object ID for an SP or MI;
- **`operationName`**: what was done, e.g. `Microsoft.Compute/virtualMachines/delete`;
- **`correlationId`**: groups all records of one operation (deleting an RG produces dozens of records sharing a `correlationId`).

To resolve an object ID:

```
az ad sp show --id <objectId> --query displayName -o tsv            # SP or MI
az ad user show --id <objectId> --query userPrincipalName -o tsv    # a person
```

If it's the pipeline's SP, I look for the CI run by time (`gh run list`). In my project, this is how I found that the VM after `destroy` had been created by `github-actions-terraform` (`5cc14326-...`).

#### Limits of the activity log

| Limitation | What to do |
|---|---|
| Kept for only **90 days** | Export through **diagnostic settings** to **Log Analytics** or Storage |
| Doesn't see the **data plane**: blobs, Key Vault secrets, database records | **Resource logs** through diagnostic settings (`StorageBlobLogs`, `AzureDiagnostics`) |
| Doesn't see changes in **Entra ID**: users, app registrations | **Entra ID audit logs** |

The answer depends on **what** was deleted: a resource, data inside it, or an identity.

#### KQL in Log Analytics

```kusto
AzureActivity
| where OperationNameValue endswith "/delete"
| where ActivityStatusValue == "Success"
| project TimeGenerated, Caller, OperationNameValue, _ResourceId
| order by TimeGenerated desc
```

#### Prevention

- **Resource locks** (`CanNotDelete`, `ReadOnly`): even an Owner can't delete the resource until the lock is removed;
- **least privilege**: fewer principals with permission to delete;
- an **alert** on delete operations in the activity log;
- **soft delete** (Key Vault, Storage blobs, Recovery Services), so deleted items can be restored.

## `az` commands to know by heart

```
az login
az account show                  # who I am and which subscription I'm in
az account set -s <id>           # switch subscription
az group list -o table
az role assignment list --assignee <id> -o table
az monitor activity-log list --offset 7d -o table
```

- Command structure: `az <service> <resource> <action> --parameters`. If you don't remember the action, add `--help`.
- Long parameters always use `--`: `--id`, not `-id`.
- `activity-log list` without `--offset` shows only the last 6 hours.
- `--query` (JMESPath) selects fields, and `-o table`/`json`/`tsv` sets the format.

## Check yourself

Explain out loud in 2 minutes, without looking:

> What happens when GitHub Actions runs `terraform apply`? How does it sign in to Azure, how does it know it's allowed, and where does the request go?

The answer has to go through the chain: SP → token from Entra ID → request to ARM → RBAC check → resource provider creates the resource.

## Interview questions

- How does a tenant differ from a subscription?
- How does an app registration differ from a service principal?
- Service principal or managed identity: when to use which?
- How are RBAC roles inherited?
- Why can't a Contributor assign roles?
- Why is OIDC better than a client secret?
- How do you find out who deleted a resource? (Activity log, the `caller` field.)
