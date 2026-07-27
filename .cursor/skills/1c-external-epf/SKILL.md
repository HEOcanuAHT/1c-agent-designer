---
name: 1c-external-epf
description: >-
  Внешние обработки (.epf): scaffold XML, dump из .epf, вынос из DataProcessors,
  pack в .epf. Исходники в src/_extDataProcessors. Use when user asks внешняя
  обработка, epf, вынести обработку, разобрать epf, собрать epf.
disable-model-invocation: true
---

# Внешние обработки (XML ↔ .epf)

## Цель

Работать с **внешними** обработками отдельно от метаданных конфигурации:

1. `scaffold` — новый каркас в `src/_extDataProcessors`
2. `dump` — `.epf` → XML (в т.ч. файл из чата)
3. `extract-from-config` — копия `DataProcessors/<Name>` → `_extDataProcessors` (без удаления из конфы)
4. правки BSL/XML
5. `pack` → `artifacts/ext/<Name>.epf`

Стандарты кода: `coding-standards`, `std-*`. Имя без слова «Обработка» (`std-metadata`).

## Каталоги

| Путь | Назначение |
|------|------------|
| `src/_extDataProcessors/` | Hierarchical XML внешек (в git) |
| `artifacts/ext/` | собранные `.epf` (gitignore) |
| `.1c/incoming/` | временные `.epf` из чата перед dump |

Папка `_extDataProcessors` **не** входит в `/LoadConfigFromFiles` (фильтр в `1c-designer-agent`). Не клади внешки в `DataProcessors/` без явной просьбы пользователя.

Структура одной обработки:

```
src/_extDataProcessors/
  <Name>.xml
  <Name>/
    Ext/ObjectModule.bsl
    Forms/...
```

## Конфиг

`.1c/project.json` (+ `project.local.json` для auth):

- `platformVersion` / `designer` — как у dump/load конфы
- `infobase` + `auth` — **нужны** для dump/pack (ссылочные типы из конфы)
- `ext.dir` — дефолт `src/_extDataProcessors`
- `ext.artifacts` — дефолт `artifacts/ext`

Пример полей — `project.json.example` рядом со skill.

## Команды

```powershell
…\Invoke-1cExternalEpf.ps1 -Action scaffold -Name "СписокЗависшихЗадач" -ProjectRoot "<repo>"
…\Invoke-1cExternalEpf.ps1 -Action dump -EpfPath "C:\path\file.epf"
…\Invoke-1cExternalEpf.ps1 -Action extract-from-config -Name "ИмяИзКонфы"
…\Invoke-1cExternalEpf.ps1 -Action pack -Name "СписокЗависшихЗадач"
```

| Action | Вход | Результат |
|--------|------|-----------|
| `scaffold` | `-Name` [`-Synonym`] | каркас из `templates/minimal` |
| `dump` | `-EpfPath` | XML в `ext.dir` (Hierarchical) |
| `extract-from-config` | `-Name` | копия + трансформ корня в ExternalDataProcessor |
| `pack` | `-Name` или `-RootXml` | `.epf` в `ext.artifacts` |

Перед dump/pack на файловой ИБ закрой обычный Конфигуратор (как для designer-agent).

## Сценарии для агента

### Новая обработка

1. Уточни имя (и синоним при необходимости).
2. `scaffold` → правки модулей/форм.
3. `pack` → отдай путь к `.epf`.

### Прислали `.epf` в чат

1. Сохрани в `.1c/incoming/<file>.epf`.
2. `dump -EpfPath …`.
3. Править XML; по запросу — `pack`.

### Вынос из конфигурации

1. `extract-from-config -Name …` (источник `src/DataProcessors/<Name>`).
2. Правки во `_extDataProcessors`.
3. `pack`. Удаление объекта из конфы — **только** если пользователь явно попросил.

### Сборка после правок

`pack -Name …`. При ошибке — лог `.1c/ext-*.log`; для extract при падении pack чини meta или предложи dump через `.epf` из Конфигуратора.

## Правила

1. Не коммитить `.epf` / содержимое `artifacts/`.
2. Dump/pack только через ИБ проекта (иначе ломаются `cfg:*` типы).
3. Не вызывать `update-db-cfg` / `/UpdateDBCfg` в этом skill.
4. Отчёты (`.erf`) — вне scope v1.
