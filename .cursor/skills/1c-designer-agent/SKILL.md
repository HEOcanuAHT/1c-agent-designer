---
name: 1c-designer-agent
description: >-
  Полный/инкрементальный dump XML и load-changed по git diff через локальный
  конфигуратор (batch /DumpConfigToFiles по умолчанию). Use when user asks
  dump-config-to-files, load-changed-from-git, designer dump/load.
disable-model-invocation: true
---

# 1C dump / load-changed (PowerShell)

## Цель

1. `dump-full` / `dump-update` → XML в `src/`
2. правки в git
3. `load-changed` → в ИБ только файлы из `git diff`

**Не делает:** хранилище, захват/помещение.

Транспорт по умолчанию: **batch** (`/DumpConfigToFiles`, `/LoadConfigFromFiles`).  
AgentMode+SSH — experimental (`designerAgent.transport: agent` или `-UseAgent`).

Быстрый dump/load через **ibcmd**: skill `1c-ibcmd-pack` → `Invoke-1cIbcmdDump.ps1`.  
Оба инструмента читают **`infobase`**: agent — `path`/`name`/`server`; ibcmd — `path` (файл) или `dbms` (C/S, быстрее).  
Если в проекте `tools.preferredDump: "ibcmd"` — по умолчанию используй ibcmd, не agent.
**И dump, и import** — только **основная** конфигурация; `config apply` / КБД не трогать (как и этот skill без `update-db-cfg`).

## Два «только отличия»

| Режим | Сравнивает |
|--------|------------|
| `dump-update` (`-update`) | ИБ ↔ `ConfigDumpInfo.xml` |
| `dump-objects` | список объектов → выгрузка из ИБ в `src/` |
| `load-changed` | `git diff BaseRef..HeadRef` под `src/` |

## Конфиг

- `.1c/project.json` — `infobase.path`, `src`, `platformVersion`
- `.1c/project.local.json` — `auth.user` / `auth.password`
- `designerAgent.transport`: `batch` (дефолт) | `agent`

Путь к файловой ИБ — со слэшами: `C:/Users/.../InfoBase8`.

## Команды

`SkillHome` = каталог этого SKILL.md. `-ProjectRoot` = workspace.

```powershell
…\Invoke-1cDesignerAgent.ps1 -Action dump-full -ProjectRoot "<workspace>"
…\Invoke-1cDesignerAgent.ps1 -Action load-changed -ProjectRoot "<workspace>" -BaseRef main
```

| Action | Что |
|--------|-----|
| `dump-full` | полная выгрузка |
| `dump-update` | инкремент vs ConfigDumpInfo |
| `dump-objects` | точечная выгрузка / откат файлов объекта из ИБ (`-ListFile` / `-Objects`) |
| `load-changed` | git → `-listFile` → load |
| `ping` | проверить designer + auth |

## AgentMode и каталог `0\`

AgentMode всегда работает из `AgentBaseDir\<userDir>` (часто `0\`, см. `agentbasedir.json`).  
Скрипт передаёт `--dir=../src` и `--list-file=../.1c/...`, чтобы XML писались/читались в реальный `src/` репозитория, а не в `0\src\`.  
Папку `0\` и `agentbasedir.json` лучше держать в `.gitignore`.

## Правила

1. Не авто-помещать в хранилище.
2. Секреты только в `project.local.json` / env (в лог пароль не писать).
3. Перед dump/load закрыть обычный конфигуратор и старый AgentMode на этой ИБ.
4. После `dump-*` / `load-changed` / `ping` агент гасится (kill по `.1c/agent.pid`), если не `designerAgent.keepAlive: true`. `start` оставляет процесс жить; `stop` — ручная остановка.
5. **Загрузка (частичная и полная) — только в основную конфигурацию.** Не вызывать `update-db-cfg` / `/UpdateDBCfg`. Принятие в конфигурацию БД — вручную в Конфигураторе.
6. **Ошибка захвата в хранилище** при load (`не захвачен в хранилище`, `ConfigFilesError`): коротко скажи пользователю, что объект **не захвачен в хранилище**, и назови объект (например `Catalog.Номенклатура`). Не разворачивай полный traceback. Дальше — захватить объект в Конфигураторе и повторить load.
7. **Auth / пользователи ИБ** (проверено, в т.ч. файловая):
   - ИБ **с пользователями** + верные `auth.user`/`password` → dump/load-changed **OK** (в т.ч. инкремент). Логин SSH к AgentMode = учётка ИБ.
   - ИБ **без пользователей** → `auth.required: false` (без `/N` `/P`, SSH с пустым логином).
   - Пользователи **есть**, `auth.required: false` / без `/N` `/P` → SSH `Authentication failed` (~несколько секунд). Конфу без учётки не выгрузить.
   - Неверный пользователь/пароль → тот же `Authentication failed` (иногда `transport shut down or saw EOF`).  
     **Сказать:** проверь логин/пароль ИБ в `project.local.json`; если пользователей нет — `auth.required: false`. Не разворачивай traceback paramiko.
8. **ibcmd** при тех же auth-проблемах: см. skill `1c-ibcmd-pack` (`Идентификация пользователя не выполнена`, `Требуется экспортировать конфигурацию полностью`).

### AgentMode: `/IBName`, auth

При старте агента скрипт передаёт `/N` `/P` (и `/UC` из `auth.uc` / `1C_IB_UC` при необходимости), **только если** `auth.required=true` или задан `auth.user`.  
Для ИБ **без пользователей** — `auth.required: false`: ключи `/N` `/P` не передаются.  
Кавычки в имени ИБ экранируются удвоением `""` (не `\"`). Для `/S` и `/IBName` обратный слэш не заменяется на `/`.

### Когда операция закончена

Агент отдаёт JSON `"type":"success"` — это основной отбойник (в логе `SUCCESS+MARKER` / `SUCCESS (no marker)`).  
Для dump с `--marker-file` маркер — `ConfigDumpInfo.xml` (обновляется и при инкременте, когда `Configuration.xml` не меняется).  
Запасной путь — стабильность `ConfigDumpInfo.xml` (~5 с) после success, даже если mtime маркера ещё не сдвинулся.  
После операции агент гасится по `.1c/agent.pid` (вторая SSH-сессия shutdown больше не используется).

`load-changed -ListFile <path>` — явный список путей относительно `src/` (удобно для незакоммиченных файлов).

`dump-objects` — выгрузить из ИБ только указанные объекты (откат правок агента на диске без git). Список: пути относительно `src/` и/или имена (`Catalog.Name`). Designer: `/DumpConfigToFiles -listFile`. Не путать с `dump-update`: инкремент не видит правки файлов, пока `configVersion` совпадает с ИБ. Спрашивай пользователя перед перезаписью.

Пути под `src/_extDataProcessors/` и `src/_extensions/` (старый layout) **исключаются** из list-file. Актуальные внешки/расширения лежат в `ext/` и `cfe/` — в `src/` их нет.

## Параллель с открытым Конфигуратором (файловая ИБ)

Проверено (один и тот же / другой пользователь ИБ — без разницы): второй процесс `/AgentMode` **стартует** и открывает порт, но SSH-логин падает:

`Authentication failed: transport shut down or saw EOF`

Дамп при открытом Designer на той же файловой ИБ **не работает**. Нужно закрыть пользовательский конфигуратор.

То же для **ibcmd** на файловой ИБ: `Ошибка исключительной блокировки информационной базы` → закрыть Конфигуратор (skill `1c-ibcmd-pack`).
