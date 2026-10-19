# Week 1 practice: "The restricted robot"

**Goal:** create a service principal that can only work in one resource group, and make sure it's powerless outside it.

**Topics:** service principal, app registration, RBAC, scope, activity log.

**Time:** 30–40 minutes. **Cost:** free (resource groups and VNets aren't billed).

---

## Step 1. Preparation

Create a resource group for the exercise:

```
az group create -n rg-practice-rbac -l swedencentral
```

Save the subscription ID in a variable:

```
SUB_ID=$(az account show --query id -o tsv)
```

## Step 2. A service principal with the Reader role on this group only

```
az ad sp create-for-rbac --name sp-practice \
  --role Reader \
  --scopes /subscriptions/$SUB_ID/resourceGroups/rg-practice-rbac
```

Save `appId`, `password` and `tenant` from the output. The password is shown only once.

> ❓ **1.** Which two objects were just created in Entra ID?

## Step 3. Sign in as the robot

```
az login --service-principal -u <appId> -p <password> --tenant <tenant>
az account show
```

> ❓ **2.** What does the `user.type` field show now?

## Step 4. Check the Reader permissions

```
az group list -o table
az network vnet create -g rg-practice-rbac -n vnet-test --address-prefix 10.10.0.0/16
```

> ❓ **3.** Which group does the robot see in `az group list`, and why doesn't it see the others?
>
> ❓ **4.** What happened when creating the VNet, and what was the error?

## Step 5. Switch back to yourself and raise the role

```
az login
az role assignment create --assignee <appId> --role Contributor \
  --scope /subscriptions/$SUB_ID/resourceGroups/rg-practice-rbac
```

## Step 6. As the robot again

Sign in as the SP (step 3) and try creating the VNet again. Then try to create a group:

```
az group create -n rg-should-fail -l swedencentral
```

> ❓ **5.** Why was the VNet created but the group wasn't, even though the role is Contributor?

## Step 7. Check the trail in the log

Switch back to yourself (`az login`) and find out who created the VNet:

```
az monitor activity-log list -g rg-practice-rbac --offset 1h \
  --query "[].{time:eventTimestamp, op:operationName.value, status:status.value, caller:caller}" -o table
```

> ❓ **6.** What's in `caller` for the VNet creation? Whose ID is it: the `appId` or the object ID?

## Step 8. Cleanup

Delete the group and the app registration (the SP is deleted along with it):

```
az group delete -n rg-practice-rbac --yes
az ad app delete --id <appId>
```

Check that no robots with roles are left:

```
az role assignment list --all \
  --query "[?principalType=='ServicePrincipal'].{id:principalName, role:roleDefinitionName, scope:scope}" -o table
```

> ❓ **7.** Were any "orphaned" role assignments left after the SP was deleted?

---

## Outcome

After the exercise you should be able to explain, without looking:

- the difference between Reader and Contributor;
- what a scope is and how it limits permissions;
- why a Contributor on an RG can't create a new RG;
- how to find out who did what through the activity log.

## My answers

1.
2.
3.
4.
5.
6.
7.
