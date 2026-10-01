---
name: 1c-external-cfe
description: >-
  Расширения конфигурации (.cfe): scaffold XML, dump из .cfe, pack в .cfe.
  Pack на служебной ИБ (.1c/ib-ext) проверяет, что платформа приняла расширение
  (ibcmd config import --extension); боевую ИБ не трогает. Use when user asks
  расширение, cfe, создай/собери/разбери cfe, проверь расширение, применимость,
  подключение к базе, check cfe.
disable-model-invocation: true
---

# Расширения конфигурации (XML ↔ .cfe)

## Цель

1. `scaffold` — пустое расширение в `cfe/<Name>/`
2. `dump` — `.cfe` → XML
3. правки BSL/XML — `/implementer` (Adopted XML: `reference-adopted.md`)
4. `pack` → `artifacts/cfe/<Name>.cfe` (тот же action — проверка, что платформа приняла XML на `.1c/ib-ext`)

Служебная ИБ **та же**, что у `1c-external-epf` (`.1c/ib-ext`).

## Каталоги

| Путь | Назначение |
|------|------------|
| `cfe/<Name>/` | Hierarchical XML |
| `artifacts/cfe/` | `.cfe` (gitignore) |
| `.1c/cfe-*.log` | логи scaffold/dump/pack (UTF-8) |

`cfe/` не входит в dump/load основной конфы.

## Конфиг

- `cfe.dir` / `cfe.artifacts` — дефолты `cfe`, `artifacts/cfe`
- `ext.serviceIb` — общая служебная ИБ с внешками

## Служебная ИБ

Та же `.1c/ib-ext`, что у `1c-external-epf` (`1c-runtime/scripts/Common-ServiceIb.ps1`). Отдельно собрать (без pack): `Invoke-1cServiceIb.ps1 -Action ensure` (без apply). Только `-File`.

По умолчанию: create → **загрузка конфы без apply** → extension create/import/export/save.

Источник метаданных:

- **C/S** (`infobase.dbms`) и **файловая боевая ИБ**: `config save` с боевой → `config load` в служебную. `.cf` с живой ИБ, не из XML `src/`.
- **XML import** из `src/` — fallback, если боевой ИБ нет. На больших дампах import может hang — не гонять «для проверки».

`config apply` на служебной — **только** `-AllowServiceIbApplyOnCompatMismatch`. На боевую — никогда.

### CompatibilityMode vs платформа

Если основная конфа со старым `CompatibilityMode` (например `Version8_3_10` на платформе 8.3.23), после загрузки конфы без apply:

> Режим совместимости основной конфигурации не соответствует версии ИБ

→ `extension create` падает.

**Обход (только `.1c/ib-ext`, не боевая ИБ):**

```powershell
…\Invoke-1cExternalCfe.ps1 -Action scaffold -Name FixDbmsType -Prefix Fix_ `
  -AllowServiceIbApplyOnCompatMismatch -RefreshServiceIb
```

Флаг делает одноразовый `ibcmd config apply --force` на служебной ИБ после загрузки конфы.  
На боевую ИБ / `update-db-cfg` проекта — **никогда**.

## Имена: латиница предпочтительнее

`-Name` / `-Prefix` с кириллицей через PowerShell→cmd→ibcmd часто приходят кракозябрами.

**Рекомендация:** ASCII-идентификаторы (`FixDbmsType`, префикс `Fix_`). Синоним можно кириллицей в XML после scaffold.  
Скрипт пишет Warning, если Name/Prefix не ASCII.

## XML-инструменты (borrow / patch / validate)

Файловый XML расширений (не pack/dump ИБ):

- skill `1c-metadata-manage` → [docs/cfe-manage.md](../1c-metadata-manage/docs/cfe-manage.md) / tools `1c-cfe-manage`
- Adopted / protected `.bin` — `reference-adopted.md` рядом с этим SKILL
- BSL-перехватчики — `std-extension-patterns`

Каркас нового расширения «с нуля» для агента — **этот** skill (`scaffold`), не `cfe-init` без ТЗ оркестратора.

## Команды

`SkillHome` = каталог этого SKILL.md. `-ProjectRoot` = workspace.

```powershell
…\Invoke-1cExternalCfe.ps1 -Action scaffold -Name "FixDbmsType" -Prefix "Fix_" -Synonym "Фикс типа СУБД" -ProjectRoot "<workspace>"
…\Invoke-1cExternalCfe.ps1 -Action dump -CfePath "C:\path\file.cfe" -Name "FixDbmsType"
…\Invoke-1cExternalCfe.ps1 -Action pack -Name "FixDbmsType"
…\Invoke-1cExternalCfe.ps1 -Action pack -Name "…" -AllowServiceIbApplyOnCompatMismatch -RefreshServiceIb
```

Проверка языка запросов — skill **`1c-query-validate`** (не этот skill).

| Action | Параметры | Результат |
|--------|-----------|-----------|
| `scaffold` | `-Name` [`-Prefix`] [`-Synonym`] [`-Purpose`] | `cfe/<Name>/` + явный `NamePrefix` |
| `dump` | `-CfePath` `-Name` | XML в `cfe.dir/<Name>/` |
| `pack` | `-Name` или `-XmlDir` | `.cfe` в `cfe.artifacts`; import на `.1c/ib-ext` |

После scaffold пустой `<NamePrefix/>` скрипт заполняет из `-Prefix`.

## Сценарии

**Код/формы/заимствования** — `/implementer` + `reference-adopted.md`.  
**scaffold / pack / dump / проверка применимости** — оркестратор (не `/implementer`).

### Проверка «подключится ли» (служебная ИБ)

«Проверь расширение / применимость / можно ли подключить к базе» → **этот** skill, `-Action pack`. Не `cfe-validate` (это только статический XML, skill `1c-metadata-manage`).

- ИБ: только `.1c/ib-ext` (копия основной конфы). Боевую не трогать, `.cfe` туда не ставить.
- Смысл: `ibcmd infobase config import --extension=…`. Успех = платформа XML приняла. Побочный файл: `artifacts/cfe/<Name>.cfe`. Ошибки: `.1c/cfe-pack.log`.
- Это не команда Конфигуратора «Проверить возможность применения» и не `config apply` расширения (КБД).
- Compat mismatch на `extension create`: `-AllowServiceIbApplyOnCompatMismatch -RefreshServiceIb` (apply только на служебной).

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
2. Исходники только в `cfe/`.
3. Dump/pack/scaffold — служебная `.1c/ib-ext`.
4. `config apply` на служебной — **только** с `-AllowServiceIbApplyOnCompatMismatch`. На боевой ИБ — никогда.
5. Установка `.cfe` в боевую ИБ — вручную пользователем.
