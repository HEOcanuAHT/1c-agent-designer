---
name: 1c-external-epf
description: >-
  Внешние обработки (.epf): scaffold XML, dump из .epf, вынос из DataProcessors,
  pack в .epf. Служебная файловая ИБ (.1c/ib-ext) для cfg:* типов:
  save .cf с боевой ИБ + load (без apply); XML import — fallback.
  Use when user asks внешняя обработка, epf, создай внешку, вынести обработку,
  разобрать epf, собрать epf.
disable-model-invocation: true
---

# Внешние обработки (XML ↔ .epf)

## Цель

Работать с **внешними** обработками отдельно от метаданных конфигурации:

1. `scaffold` — новый каркас в `ext`
2. `dump` — `.epf` → XML (в т.ч. файл из чата)
3. `extract-from-config` — копия `DataProcessors/<Name>` → `ext/` (без удаления из конфы)
4. правки BSL/XML
5. `pack` → `artifacts/ext/<Name>.epf`

Стандарты кода: `coding-standards`, `std-*`. Имя без слова «Обработка» (`std-metadata`).

## Каталоги

| Путь | Назначение |
|------|------------|
| `ext/` | Hierarchical XML внешек (в git) |
| `artifacts/ext/` | собранные `.epf` (gitignore) |
| `.1c/incoming/` | временные `.epf` из чата перед dump |

Папка `ext/` **не** входит в `/LoadConfigFromFiles`. Не клади внешки в `src/DataProcessors/` без явной просьбы пользователя. Старый `src/_extDataProcessors` фильтр designer-agent всё ещё отсекает.

Структура одной обработки:

```
ext/
  <Name>.xml
  <Name>/
    Ext/ObjectModule.bsl
    Forms/...
```

## Конфиг

`.1c/project.json` (+ `project.local.json` для auth):

- `platformVersion` / `designer` — как у dump/load конфы
- `ext.dir` — дефолт `ext`
- `ext.artifacts` — дефолт `artifacts/ext`
- `ext.serviceIb` — **служебная файловая ИБ** для dump/pack (см. ниже)

Пример полей — `project.json.example` рядом со skill.

## Служебная ИБ (dump/pack)

Dump/pack внешек требуют ИБ с **метаданными основной конфы** (`cfg:*` типы). Боевую ИБ **не** используем как цель pack: только как источник `.cf` (без `config apply`).

Служебная ИБ **общая** с расширениями `.cfe` (skill `1c-external-cfe`, общий модуль `Common-ServiceIb.ps1`).

Перед `dump` / `pack` скрипт (если `ext.serviceIb.enabled` ≠ false):

1. Файловая ИБ в `.1c/ib-ext` (+ `dataDir` `.1c/ib-ext-data`).
2. `ibcmd infobase create` (если нет или устарела / `-RefreshServiceIb`).
3. Загрузка метаданных **без `config apply`**:
   - **C/S** (есть `infobase.dbms` server+name): основной путь — `config save` с боевой ИБ → `.cf` во `%TEMP%\1c-agent-designer\…` (вне workspace) → `config load` в `.1c/ib-ext`.
   - **Файловая боевая ИБ** (есть `1Cv8.1CD`): тот же save→load. Конфигуратор по этой ИБ должен быть закрыт; иначе явная ошибка блокировки, не hang.
   - **XML `config import` из `src/`** — fallback, если боевой ИБ нет. На больших Hierarchical-дампах import может встать мёртво (1CD ~30 МБ, CPU=0). Не «лечить» копиями `src`, `.cursorignore` или hide `ConfigDumpInfo.xml`.
4. Designer batch (`/DumpExternal…`, `/LoadExternal…`) — **только** на эту служебную ИБ.

Штамп пересборки — `src/Configuration.xml`. `.cf` берётся с **живой ИБ**, не из XML `src/`. Для pack `cfg:*` это обычно то, что нужно. Если `src/` сильно разъехался с ИБ — ожидаемо (в служебной будет конфа ИБ).

Временный `.cf` не оставлять в проекте (удаляется в `finally`).

| | Служебная ИБ | Боевая ИБ проекта |
|--|--------------|-------------------|
| Назначение | pack/dump внешек | разработка, dump/load конфы; для служебной — только `config save` |
| apply / КБД | **никогда** (кроме CFE-флага ниже) | вручную в Конфигураторе |
| Обновление | wipe→create→load `.cf` (или XML import) | не wipe / не apply этим skill |

**Не делать:** `config apply` на служебной ИБ по умолчанию — повторный import после apply зависает; при сомнениях `-RefreshServiceIb`.  
**Исключение для CFE:** skill `1c-external-cfe`, флаг `-AllowServiceIbApplyOnCompatMismatch` — одноразовый apply на `.1c/ib-ext` при несовпадении CompatibilityMode и платформы. На боевую ИБ не переносить.

`scaffold` / `extract-from-config` ИБ не требуют; `pack` / `dump` — готовят служебную ИБ автоматически.

## Команды

`SkillHome` = каталог этого SKILL.md. `-ProjectRoot` = workspace.

```powershell
…\Invoke-1cExternalEpf.ps1 -Action scaffold -Name "СписокЗависшихЗадач" -ProjectRoot "<workspace>"
…\Invoke-1cExternalEpf.ps1 -Action dump -EpfPath "C:\path\file.epf"
…\Invoke-1cExternalEpf.ps1 -Action extract-from-config -Name "ИмяИзКонфы"
…\Invoke-1cExternalEpf.ps1 -Action pack -Name "СписокЗависшихЗадач"
…\Invoke-1cExternalEpf.ps1 -Action pack -Name "…" -RefreshServiceIb   # принудительно пересоздать служебную ИБ
```

| Action | Вход | Результат |
|--------|------|-----------|
| `scaffold` | `-Name` [`-Synonym`] | каркас из `templates/minimal` |
| `dump` | `-EpfPath` | XML в `ext.dir` (Hierarchical) |
| `extract-from-config` | `-Name` | копия + трансформ корня в ExternalDataProcessor |
| `pack` | `-Name` или `-RootXml` | `.epf` в `ext.artifacts` |

Перед dump/pack закрой Конфигуратор **на служебной** `.1c/ib-ext` (если открывали).

### Сценарии для агента

**Правки кода/форм** — делегируй `/implementer` (только файлы). Каркас и `pack` — оркестратор (rule `1c-orchestrator`).

### Новая обработка («создай внешку»)

1. Уточни имя (и синоним при необходимости).
2. Оркестратор: `scaffold` → `/implementer` правит модули/формы.
3. Оркестратор: `pack` — скрипт сам подготовит служебную ИБ и соберёт `.epf`.
4. Отдай путь к `artifacts/ext/<Name>.epf`.

Не подключай боевую ИБ и не вызывай `update-db-cfg` / apply.

### Прислали `.epf` в чат

1. Сохрани в `.1c/incoming/<file>.epf`.
2. `dump -EpfPath …` (служебная ИБ с метаданными конфы).
3. Править XML; по запросу — `pack`.

### Вынос из конфигурации

1. `extract-from-config -Name …` (источник `src/DataProcessors/<Name>`).
2. Правки в `ext/`.
3. `pack`. Удаление объекта из конфы — **только** если пользователь явно попросил.

### Сборка после правок

`pack -Name …`. При ошибке — лог `.1c/ext-*.log`; для extract при падении pack чини meta или предложи dump через `.epf` из Конфигуратора.

## Правила

1. Не коммитить `.epf` / содержимое `artifacts/`.
2. Dump/pack — через **служебную** `.1c/ib-ext` (save `.cf` с боевой + load, без apply; XML import — fallback). Не боевая ИБ как цель.
3. На служебной ИБ **никогда** `config apply` / `update-db-cfg` / `/UpdateDBCfg` (кроме CFE `-AllowServiceIbApplyOnCompatMismatch`).
4. Отчёты (`.erf`) — вне scope v1.
