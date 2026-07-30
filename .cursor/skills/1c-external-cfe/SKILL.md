---
name: 1c-external-cfe
description: >-
  Расширения конфигурации (.cfe): scaffold XML, dump из .cfe, pack в .cfe.
  Служебная файловая ИБ (.1c/ib-ext, та же что у EPF) — import конфы без apply.
  Use when user asks расширение, cfe, создай расширение, собрать cfe, разобрать cfe.
disable-model-invocation: true
---

# Расширения конфигурации (XML ↔ .cfe)

## Цель

Работать с **расширениями** отдельно от основной конфигурации и внешек:

1. `scaffold` — пустое расширение в `src/_extensions/<Name>/` (через create+export на служебной ИБ)
2. `dump` — `.cfe` → XML
3. правки BSL/XML (свои объекты с `NamePrefix`, заимствования)
4. `pack` → `artifacts/cfe/<Name>.cfe`

Стандарты кода: `coding-standards`, `std-*`. Служебная ИБ **та же**, что у `1c-external-epf` (`ext.serviceIb` → `.1c/ib-ext`).

## Каталоги

| Путь | Назначение |
|------|------------|
| `src/_extensions/<Name>/` | Hierarchical XML расширения (`Configuration.xml` + объекты) |
| `artifacts/cfe/` | собранные `.cfe` (gitignore) |
| `.1c/incoming/` | временные `.cfe` из чата перед dump |

Папка `_extensions` **не** входит в dump/load основной конфы (preserve + фильтр designer-agent). Не клади расширения в корень `src/` как будто это основная конфигурация.

Структура:

```
src/_extensions/
  <Name>/
    Configuration.xml
    ConfigDumpInfo.xml
    CommonModules/...
    ...
```

## Конфиг

`.1c/project.json`:

- `cfe.dir` — дефолт `src/_extensions`
- `cfe.artifacts` — дефолт `artifacts/cfe`
- `ext.serviceIb` — **общая** служебная ИБ с внешками (import `src/` без apply)

Пример — `project.json.example` рядом со skill.

## Служебная ИБ

Перед `scaffold` / `dump` / `pack` (если `ext.serviceIb.enabled` ≠ false):

1. Файловая ИБ `.1c/ib-ext` (та же, что для EPF).
2. `ibcmd config import` основной конфы из `src/` — **без `config apply`**.
3. `ibcmd config extension create` → `import`/`load`/`export`/`save` с `--extension=<Name>`.

Боевую ИБ не трогать. `apply` / КБД на служебной — **никогда**.

Нужен `src/Configuration.xml` (дамп основной конфы) — иначе служебную ИБ не собрать.

## Команды

```powershell
…\Invoke-1cExternalCfe.ps1 -Action scaffold -Name "МоёРасширение" -Prefix "Моё_" -Synonym "Моё расширение" -ProjectRoot "<repo>"
…\Invoke-1cExternalCfe.ps1 -Action dump -CfePath "C:\path\file.cfe" -Name "МоёРасширение"
…\Invoke-1cExternalCfe.ps1 -Action pack -Name "МоёРасширение"
…\Invoke-1cExternalCfe.ps1 -Action pack -Name "…" -RefreshServiceIb
```

| Action | Параметры | Результат |
|--------|-----------|-----------|
| `scaffold` | `-Name` [`-Prefix`] [`-Synonym`] [`-Purpose`] | `src/_extensions/<Name>/` |
| `dump` | `-CfePath` `-Name` | XML в `cfe.dir/<Name>/` |
| `pack` | `-Name` или `-XmlDir` | `.cfe` в `cfe.artifacts` |

`-Purpose`: `Customization` (дефолт) / `AddOn` / `Patch`.  
`-Prefix` по умолчанию: `<Name>_`. Для `pack` читается из `Configuration.xml`, если не задан.

Перед операциями закрой Конфигуратор на `.1c/ib-ext`, если открывали.

## Сценарии для агента

**Правки кода/форм/метаданных** — `/implementer`. `scaffold` / `pack` / `dump` — оркестратор (rule `1c-orchestrator`).

### Новое расширение

1. Уточни имя, префикс, назначение (Customization/AddOn/Patch).
2. Оркестратор: `scaffold` → `/implementer` правит объекты/модули.
3. Оркестратор: `pack` → отдай `artifacts/cfe/<Name>.cfe`.

### Прислали `.cfe`

1. Сохрани в `.1c/incoming/<file>.cfe`.
2. `dump -CfePath … -Name …` (`-Name` = имя расширения внутри файла).
3. Править XML; по запросу — `pack`.

### Сборка после правок

`pack -Name …`. Лог: `.1c/cfe-*.log`. При смене `src/Configuration.xml` — `-RefreshServiceIb` или авто-wipe по stamp.

## Правила

1. Не коммитить `.cfe` / `artifacts/`.
2. Исходники только в `src/_extensions/` — не смешивать с основной выгрузкой.
3. Dump/pack/scaffold — через **служебную** `.1c/ib-ext` (не боевая ИБ).
4. На служебной ИБ **никогда** `config apply` / `update-db-cfg` / `/UpdateDBCfg`.
5. Установка расширения в боевую ИБ — вручную пользователем (не через этот skill).
