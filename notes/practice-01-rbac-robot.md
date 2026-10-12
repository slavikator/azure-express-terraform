# Практика тижня 1. «Обмежений робот»

**Мета:** створити service principal, який може працювати лише в одній resource group, і переконатися, що за її межами він безсилий.

**Теми:** service principal, app registration, RBAC, scope, activity log.

**Час:** 30–40 хвилин. **Вартість:** безкоштовно (resource group і VNet не тарифікуються).

---

## Крок 1. Підготовка

Створіть resource group для вправи:

```
az group create -n rg-practice-rbac -l swedencentral
```

Збережіть ID підписки у змінну:

```
SUB_ID=$(az account show --query id -o tsv)
```

## Крок 2. Service principal з роллю Reader лише на цю групу

```
az ad sp create-for-rbac --name sp-practice \
  --role Reader \
  --scopes /subscriptions/$SUB_ID/resourceGroups/rg-practice-rbac
```

Збережіть із виводу `appId`, `password` і `tenant`. Пароль показується лише один раз.

> ❓ **1.** Які два об'єкти щойно створилися в Entra ID?

## Крок 3. Увійдіть як робот

```
az login --service-principal -u <appId> -p <password> --tenant <tenant>
az account show
```

> ❓ **2.** Що тепер показує поле `user.type`?

## Крок 4. Перевірте права Reader

```
az group list -o table
az network vnet create -g rg-practice-rbac -n vnet-test --address-prefix 10.10.0.0/16
```

> ❓ **3.** Яку групу бачить робот у `az group list` і чому не бачить решту?
>
> ❓ **4.** Що сталося зі створенням VNet і яка помилка?

## Крок 5. Поверніться до себе і підвищте роль

```
az login
az role assignment create --assignee <appId> --role Contributor \
  --scope /subscriptions/$SUB_ID/resourceGroups/rg-practice-rbac
```

## Крок 6. Знову як робот

Увійдіть як SP (крок 3) і повторіть створення VNet. Потім спробуйте створити групу:

```
az group create -n rg-should-fail -l swedencentral
```

> ❓ **5.** Чому VNet створилася, а група ні, хоча роль Contributor?

## Крок 7. Перевірте слід у журналі

Поверніться до себе (`az login`) і знайдіть, хто створив VNet:

```
az monitor activity-log list -g rg-practice-rbac --offset 1h \
  --query "[].{time:eventTimestamp, op:operationName.value, status:status.value, caller:caller}" -o table
```

> ❓ **6.** Що стоїть у `caller` для створення VNet? Чий це ID: `appId` чи object ID?

## Крок 8. Прибирання

Видаліть групу та app registration (разом з нею видалиться і SP):

```
az group delete -n rg-practice-rbac --yes
az ad app delete --id <appId>
```

Перевірте, що роботів з роллю не лишилося:

```
az role assignment list --all \
  --query "[?principalType=='ServicePrincipal'].{id:principalName, role:roleDefinitionName, scope:scope}" -o table
```

> ❓ **7.** Чи лишилися «осиротілі» призначення ролі після видалення SP?

---

## Результат

Після вправи ви маєте вміти без підглядання пояснити:

- різницю між Reader і Contributor;
- що таке scope і як вона обмежує права;
- чому Contributor на RG не може створити нову RG;
- як знайти через activity log, хто що зробив.

## Мої відповіді

1.
2.
3.
4.
5.
6.
7.
