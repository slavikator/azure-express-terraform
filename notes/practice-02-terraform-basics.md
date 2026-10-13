# Практика тижня 2. «Наводимо лад у коді»

**Мета:** переписати власний проєкт за правилами з тижня 2: lock-файл у git, змінні з перевіркою, спільні теги, data source і output. І щоразу перед `apply` передбачити, що покаже `plan`.

**Теми:** lock-файл, змінні, `validation`, пріоритет значень змінних, `locals`, `data`, `output`, граф залежностей.

**Час:** 1,5–2 години, можна за два заходи. **Вартість:** близько $0,05 на годину, поки працює VM. Наприкінці буде `destroy`.

**Конспект:** [`02-terraform-basics.md`](02-terraform-basics.md)

---

## Правило всієї практики

Перед кожним `terraform plan` **спершу вгадайте**, що він покаже: скільки ресурсів, `+`, `~` чи `-/+`. Потім порівняйте з реальним виводом. Саме так тренується читання плану.

---

## Крок 0. Підніміть інфраструктуру

Щоб бачити, як зміни в коді впливають на ресурси, вони мають існувати.

```
terraform init
terraform plan
terraform apply
```

> ❓ **1.** Скільки ресурсів створив `apply`? Знайдіть їх усі у виводі `terraform state list`.

## Крок 1. Lock-файл у git

Відкрийте `.gitignore` і видаліть рядок `.terraform.lock.hcl`. Потім подивіться, що всередині файлу:

```
cat .terraform.lock.hcl
git status
```

> ❓ **2.** Яка версія `azurerm` зафіксована? Що означають рядки `h1:` і `zh:`?
>
> ❓ **3.** Що станеться в CI, якщо lock-файлу в репо немає, а HashiCorp випустить нову версію провайдера в межах `~> 3.0`?

Lock-файл, створений на Mac, може не містити всіх хешів для Linux, де працює CI. Додайте їх явно:

```
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64
```

## Крок 2. Змінні з перевіркою

Створіть у `variables.tf` дві змінні:

- `location` з типом `string`, значенням за замовчуванням `"swedencentral"` і `validation`, що дозволяє лише `swedencentral` і `northeurope`;
- `vm_size` з типом `string` і значенням за замовчуванням `"Standard_B2ls_v2"`.

Замініть ними жорстко прописані значення: `location` у resource group (`network.tf`) і `size` у VM (`compute.tf`). Інші ресурси вже беруть регіон з `azurerm_resource_group.rg.location`, їх не чіпайте.

```
terraform plan
```

> ❓ **4.** Що показав `plan` і чому?

Перевірте `validation`:

```
terraform plan -var="location=mars"
```

> ❓ **5.** Яку помилку ви отримали? Чи дійшов Terraform до звернення в Azure?

## Крок 3. Звідки береться значення змінної

Спробуйте по черзі і щоразу дивіться лише на рядок `Plan:` і на позначку біля resource group:

```
TF_VAR_location=northeurope terraform plan
TF_VAR_location=northeurope terraform plan -var="location=swedencentral"
```

> ❓ **6.** Яке значення перемогло в другій команді і чому?
>
> ❓ **7.** У першій команді біля resource group стоїть `-/+`. Чому зміна регіону вимагає пересоздання? Що буде з рештою ресурсів?

**Не робіть `apply` з `northeurope`.**

## Крок 4. Спільні теги через `locals`

Створіть `locals.tf`:

```hcl
locals {
  tags = {
    project = "azure-demo"
    env     = "dev"
    owner   = "slavikator"
  }
}
```

Додайте `tags = local.tags` до кожного ресурсу, який підтримує теги. Перевіряйте документацію ресурсу на registry.terraform.io, якщо не впевнені.

> ❓ **8.** Які ресурси вашого проєкту **не** підтримують теги і чому?

```
terraform plan
```

> ❓ **9.** Скільки ресурсів буде змінено і з якою позначкою: `~` чи `-/+`? Чому теги не вимагають пересоздання?

```
terraform apply
az group show -n rg-devops-demo-swe --query tags
```

## Крок 5. `data` і `output`

Додайте в код:

```hcl
data "azurerm_client_config" "current" {}
```

І в будь-який файл (краще створити `outputs.tf` і перенести туди `vm_public_ip`) додайте два outputs: `subscription_id` і `tenant_id` з цього data source.

```
terraform plan
terraform apply
terraform output
terraform output -raw subscription_id
```

> ❓ **10.** Чим `data "azurerm_client_config"` відрізняється від `resource`? Чи створює він щось в Azure?
>
> ❓ **11.** Під ким увійшов Terraform, тобто чий `client_id` віддасть цей data source локально і чий у CI?

## Крок 6. Граф залежностей

```
terraform graph > graph.dot
```

Вставте вміст `graph.dot` у будь-який онлайн-рендерер Graphviz (наприклад, пошук «graphviz online») або встановіть локально: `brew install graphviz`, потім `dot -Tsvg graph.dot > graph.svg` і відкрийте `graph.svg`.

> ❓ **12.** Знайдіть ланцюжок від resource group до VM. Через які ресурси він проходить?
>
> ❓ **13.** Які ресурси не залежать один від одного і тому створюються паралельно?

`graph.dot` і `graph.svg` у git не додавайте.

## Крок 7. Перевірка і пуш

```
terraform fmt -recursive
terraform validate
terraform plan
```

Останній `plan` має показати `No changes`. Закомітьте все: зміни в коді, `.gitignore` і `.terraform.lock.hcl`.

```
git add -A && git commit -m "refactor: variables, tags, outputs, lock file" && git push
```

Відкрийте лог кроку **Terraform Plan** у GitHub Actions.

> ❓ **14.** Що показав `plan` у CI і чому саме це? Зверніть увагу: CI бере ті ж змінні зі значеннями за замовчуванням, а `ssh_public_key` із секрету.

## Крок 8. Прибирання

```
terraform destroy
az group exists -n rg-devops-demo-swe
```

---

## Результат

Після практики ви маєте вміти без підглядання пояснити:

- навіщо комітити lock-файл;
- як працює `validation` і коли вона спрацьовує;
- у якому порядку Terraform бере значення змінних;
- різницю між `~` і `-/+` у плані і що її викликає;
- різницю між `resource` і `data`;
- як Terraform визначає порядок створення ресурсів.

## Мої відповіді

1.
2.
3.
4.
5.
6.
7.
8.
9.
10.
11.
12.
13.
14.
