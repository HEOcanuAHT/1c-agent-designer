---
name: 1c-external-cfe
description: >-
  Расширения конфигурации (.cfe): scaffold XML, dump из .cfe, pack в .cfe.
  Служебная файловая ИБ (.1c/ib-ext, та же что у EPF) — import конфы без apply
  (исключение: -AllowServiceIbApplyOnCompatMismatch). Use when user asks
  расширение, cfe, создай расширение, собрать cfe, разобрать cfe.
disable-model-invocation: true
---

# Расширения конфигурации (XML ↔ .cfe)

## Цель

1. `scaffold` — пустое расширение в `src/_extensions/<Name>/`
2. `dump` — `.cfe` → XML
3. правки BSL/XML — `/implementer` (Adopted XML: `reference-adopted.md`)
4. `pack` → `artifacts/cfe/<Name>.cfe`

Служебная ИБ **та же**, что у `1c-external-epf` (`.1c/ib-ext`).

## Каталоги

| Путь | Назначение |
|------|------------|
| `src/_extensions/<Name>/` | Hierarchical XML |
| `artifacts/cfe/` | `.cfe` (gitignore) |
| `.1c/cfe-*.log` | логи scaffold/dump/pack (UTF-8) |

`_extensions` не входит в dump/load основной конфы.

## Конфиг

- `cfe.dir` / `cfe.artifacts` — дефолты `src/_extensions`, `artifacts/cfe`
- `ext.serviceIb` — общая служебная ИБ с внешками

## Служебная ИБ

По умолчанию: create → **import без apply** → extension create/import/export/save.

### CompatibilityMode vs платформа

Если основная конфа со старым `CompatibilityMode` (например `Version8_3_10` на платформе 8.3.23), после import без apply:

> Режим совместимости основной конфигурации не соответствует версии ИБ

→ `extension create` падает.

**Обход (только `.1c/ib-ext`, не боевая ИБ):**

```powershell
…\Invoke-1cExternalCfe.ps1 -Action scaffold -Name FixDbmsType -Prefix Fix_ `
  -AllowServiceIbApplyOnCompatMismatch -RefreshServiceIb
```

Флаг делает одноразовый `ibcmd config apply --force` на служебной ИБ после import.  
На боевую ИБ / `update-db-cfg` проекта — **никогда**.

## Имена: латиница предпочтительнее

`-Name` / `-Prefix` с кириллицей через PowerShell→cmd→ibcmd часто приходят кракозябрами.

**Рекомендация:** ASCII-идентификаторы (`FixDbmsType`, префикс `Fix_`). Синоним можно кириллицей в XML после scaffold.  
Скрипт пишет Warning, если Name/Prefix не ASCII.

## Команды

```powershell
…\Invoke-1cExternalCfe.ps1 -Action scaffold -Name "FixDbmsType" -Prefix "Fix_" -Synonym "Фикс типа СУБД"
…\Invoke-1cExternalCfe.ps1 -Action dump -CfePath "C:\path\file.cfe" -Name "FixDbmsType"
…\Invoke-1cExternalCfe.ps1 -Action pack -Name "FixDbmsType"
…\Invoke-1cExternalCfe.ps1 -Action pack -Name "…" -AllowServiceIbApplyOnCompatMismatch -RefreshServiceIb
```

### Проверка языка запросов (служебная ИБ)

Пример расширения: `examples/QueryValidate` (HTTP `/hs/qv/validate`).

```powershell
…\Invoke-1cValidateQuery.ps1 -Action ensure
…\Invoke-1cValidateQuery.ps1 -QueryText "ВЫБРАТЬ 1"
…\Invoke-1cValidateQuery.ps1 -Action stop
```

См. `examples/QueryValidate/README.md`. На `.1c/ib-ext` выполняется apply (нужен runtime HTTP).

**Режим агента (opt-in):** rule `1c-query-validate` — по умолчанию выкл.; фраза «проверяй запросы» → `.1c/query-validate.mode=on`, после правок запросов вызывать `Invoke-1cValidateQuery.ps1`. «не проверяй запросы» → `off`.

| Action | Параметры | Результат |
|--------|-----------|-----------|
| `scaffold` | `-Name` [`-Prefix`] [`-Synonym`] [`-Purpose`] | `src/_extensions/<Name>/` + явный `NamePrefix` |
| `dump` | `-CfePath` `-Name` | XML в `cfe.dir/<Name>/` |
| `pack` | `-Name` или `-XmlDir` | `.cfe` в `cfe.artifacts` |

После scaffold пустой `<NamePrefix/>` скрипт заполняет из `-Prefix`.

## Сценарии

**Код/формы/заимствования** — `/implementer` + `reference-adopted.md`.  
**scaffold / pack / dump** — оркестратор.

### Новое расширение

1. ASCII-имя и префикс; при compat-ошибке — `-AllowServiceIbApplyOnCompatMismatch`.
2. `scaffold` → implementer (объекты, `&Вместо`, Adopted).
3. Перед pack — чеклист ниже.
4. `pack` → `artifacts/cfe/<Name>.cfe`. Лог ошибок: `.1c/cfe-pack.log`.

### Заимствования (Adopted)

Ручной XML хрупкий. Предпочтительно:

1. Заимствовать объект в Конфигураторе на служебной/дев ИБ и сделать `dump` расширения, **или**
2. Копировать минимальный шаблон из `reference-adopted.md` (CommonModule / DataProcessor).

Не копировать uuid/`GeneratedType` 1:1 с основной без проверки.

## Чеклист перед pack

- [ ] `Configuration.xml`: непустой `<NamePrefix>…</NamePrefix>`
- [ ] У Adopted-объектов: `ObjectBelonging=Adopted`, `ExtendedConfigurationObject`, `InternalInfo`/`GeneratedType`, `<ChildObjects/>` (хотя бы пустой)
- [ ] Модули расширения: `PropertyState` ObjectModule/Module = `Extended`, где нужно
- [ ] CommonModule: uuid в расширении ≠ обязательно копировать как `ExtendedConfigurationObject` основной (см. reference)
- [ ] Нет кириллицы в Name расширения, если раньше ломался ibcmd
- [ ] При ошибке import — читать `.1c/cfe-pack.log` (UTF-8)

## Правила

1. Не коммитить `.cfe` / `artifacts/`.
2. Исходники только в `src/_extensions/`.
3. Dump/pack/scaffold — служебная `.1c/ib-ext`.
4. `config apply` на служебной — **только** с `-AllowServiceIbApplyOnCompatMismatch`. На боевой ИБ — никогда.
5. Установка `.cfe` в боевую ИБ — вручную пользователем.
