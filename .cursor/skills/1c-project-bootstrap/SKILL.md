---
name: 1c-project-bootstrap
description: >-
  Первичная настройка репозитория конфигурации 1С после clone/копии шаблона:
  интерактивный чеклист (короткие вопросы), предпочтение ibcmd, fallback
  designer-agent, зависимости, .1c/project.json и project.local.json, тип ИБ.
  Use when user clones template, asks setup/инициализация/настройка окружения,
  or .1c/project.json is missing.
---

# Bootstrap проекта конфигурации 1С

## Когда запускать

- Клон/копия шаблона без рабочего `.1c/project.json`
- Пользователь: настройка окружения / инициализация / bootstrap / «подключи ИБ»
- Правило `1c-project-bootstrap` предложило setup — только после согласия

Не запускать повторно, если `.1c/project.json` уже заполнен и пользователь не просит перенастроить.

## Цель

1. Интерактивный мини-опрос (один короткий вопрос за раз) + Todo-чеклист.
2. Записать `.1c/project.json` / `project.local.json`.
3. **Предпочтительный dump/load = ibcmd**; designer-agent — запасной путь.
4. Опционально ping / первый dump ([docs/INITIAL_DUMP.md](../../../docs/INITIAL_DUMP.md)).

## Поведение агента (обязательно)

1. После согласия на setup — **сразу** создай TodoWrite-чеклист (см. ниже) и веди отметки по ходу.
2. Вопросы — **короткие**, один за раз; варианты нумерованным списком (1/2/3) или AskQuestion, если доступен.
3. Не пиши конфиги молча до ответов. Не ставь софт без согласия.  
   Пароли ИБ: **Windows Credential Manager** (`Set-1cIbCredential.ps1`), не в чат и не в git. В JSON — только `credentialTarget`.
4. Dump/load: load **без** `update-db-cfg`. Не смешивать с SDMS / feature-pipeline.

### Todo-чеклист (создать в начале)

| id | content |
|----|---------|
| `boot-env` | Проверка окружения (платформа / ibcmd / Python) |
| `boot-ib-type` | Тип ИБ (file / server / ibname) |
| `boot-ib-conn` | Параметры подключения ИБ |
| `boot-auth` | Пользователи ИБ и auth |
| `boot-tool` | Выбор dump-инструмента (ibcmd / agent) |
| `boot-dbms` | СУБД для ibcmd (если client-server) |
| `boot-write` | Запись project.json + project.local.json |
| `boot-ping` | Проверка связи (по согласию) |

Пункты `boot-dbms` / `boot-ping` можно `cancelled`, если не нужны по ответам.

---

## Шаг 0 — корень

Каталог с `.cursor/skills` и `.1c/`. Пути относительно него.

## Шаг 1 — окружение (`boot-env`)

```powershell
…\.cursor\skills\1c-project-bootstrap\scripts\Check-1cDevEnv.ps1 -ProjectRoot "<repo>"
```

| Компонент | Зачем |
|-----------|--------|
| `1cv8.exe` + **`ibcmd.exe`** | Предпочтительный dump/load + pack |
| Python + `paramiko` (или plink) | Только если нужен AgentMode (fallback) |
| Git | `load-changed` по diff |

Кратко покажи missing → предложи установку → выполняй только с согласия.  
Для **только ibcmd** (файловая или C/S + SQL) Python не обязателен.

## Шаг 2 — вопросы (мини-чат)

### Q1. Тип ИБ? (`boot-ib-type`)

1. Файловая → `infobase.type=file`
2. Серверная (кластер `/S`) → `server`
3. По имени в списке баз → `ibname`

### Q2. Параметры подключения (`boot-ib-conn`)

Только нужное поле:

| type | Спросить | JSON |
|------|----------|------|
| file | путь каталога ИБ (`C:/…` или `.1c/ib-dev`) | `path` |
| server | строка как для `/S` | `server` |
| ibname | имя из списка 1С | `name` |

Также: `platformVersion` (можно из Check).

### Q3. Пользователи **1С** в ИБ есть? (`boot-auth`)

Это учётка **конфигуратора/ИБ** (`--user` / `/N`), не SQL.

1. **Нет** → `auth.required: false` (CredMgr не нужен)
2. **Да** → `auth.required: true` + **Windows Credential Manager** для логина 1С

При «Да»:

1. Target: `auth.credentialTarget` или `1c-ib/<имя-проекта>`.
2. В терминале (пароль не в чат):

```powershell
…\1c-project-bootstrap\scripts\Set-1cIbCredential.ps1 -ProjectRoot "<repo>"
```

3. В JSON только `"credentialTarget"` — без пароля.

Fallback: env `1C_IB_*` или legacy `auth.user`/`password` в local.

### Q4. Чем выгружать / загружать XML? (`boot-tool`)

Сначала **рекомендация**, потом выбор:

| Ситуация | Рекомендация |
|----------|----------------|
| Файловая + есть `ibcmd` | **ibcmd** (быстрее; Конфигуратор на этой ИБ закрыть) |
| C/S + доступ к СУБД (SQL) | **ibcmd** + `infobase.dbms` в том же блоке, что `name`/`server` |
| C/S **без** доступа к SQL / только `/IBName` | **designer-agent** (ibcmd не умеет `/IBName`) |
| ibcmd нет в платформе | **designer-agent** |

Варианты ответа пользователя:

1. **ibcmd** (предпочтительно) → `tools.preferredDump: "ibcmd"`
2. **designer-agent** → `tools.preferredDump: "agent"`
3. **оба** (ibcmd основной, agent запасной) → `preferredDump: "ibcmd"`, настроить и agent

### Q5. Доступ к СУБД для ibcmd? (`boot-dbms`) — только если type ≠ file и выбрали ibcmd/оба

В **`infobase`** же, рядом с `name` / `server`. Только для ibcmd (прямой SQL); agent использует `name` или `server`.

1. **Да, есть** → `infobase.dbms`: `kind` / `server` / `name` (БД). Кратко: ibcmd через SQL **быстрее** agent.

   - **Windows auth к SQL** → `windowsAuth: true` (без SQL-пароля).
   - SQL-логин → `windowsAuth: false` + user/pwd в env (`1C_DB_*`).

2. **Нет доступа к SQL** → `preferredDump: agent`; `dbms` не заполнять.

Файловой ИБ `dbms` не нужен — только `path`.
### Q6. AgentMode как запасной? (если preferred = ibcmd и ещё не «оба»)

Коротко: «Настроить designer-agent на случай недоступности ibcmd?»  
Да → проверить/предложить Python+paramiko, `designerAgent.transport: agent`.  
Нет → `transport: batch` или оставить example; dump по умолчанию всё равно через ibcmd.

---

## Шаг 3 — запись конфигов (`boot-write`)

1. Нет `project.json` → копия с `project.json.example`.
2. Нет `project.local.json` → копия с example.
3. Записать ответы; сохранить блок `template` (для `1c-template-sync`).
4. `ibcmd.dataDir`: `.1c/ibcmd-data` (в `.gitignore`).
5. `tools.preferredDump`: `ibcmd` | `agent`.
6. Секреты 1С — Credential Manager / env; SQL при `windowsAuth: true` — без пароля. Не коммитить local.

### Фрагменты

**tools + file + ibcmd:**

```json
"tools": { "preferredDump": "ibcmd" },
"infobase": { "type": "file", "path": "C:/Users/.../InfoBase8" },
"ibcmd": { "dataDir": ".1c/ibcmd-data" },
"auth": { "required": false }
```

**C/S — одна `infobase`, agent + ibcmd:**

```json
"tools": { "preferredDump": "ibcmd" },
"infobase": {
  "type": "ibname",
  "name": "My Base",
  "dbms": {
    "kind": "MSSQLServer",
    "server": "sql-host",
    "name": "db_name",
    "windowsAuth": true
  }
},
"ibcmd": { "dataDir": ".1c/ibcmd-data" },
"auth": { "required": true, "credentialTarget": "1c-ib/my-base" }
```

(`dbms` — для ibcmd; agent берёт `name`. SQL-пароль не нужен при `windowsAuth: true`.)
**Только agent:**

```json
"tools": { "preferredDump": "agent" },
"designerAgent": { "transport": "agent", "baseDir": "C:/Users/.../repo" }
```

---

## Шаг 4 — проверка (`boot-ping`)

С согласия:

- если `preferredDump=ibcmd` → `Invoke-1cIbcmdDump.ps1 -Action ping`
- иначе / fallback → `Invoke-1cDesignerAgent.ps1 -Action ping`

Перед ping на **файловой** ИБ: обычный Конфигуратор закрыт.

Успех → предложи `dump-full` ([docs/INITIAL_DUMP.md](../../../docs/INITIAL_DUMP.md)).

---

## Как агент выбирает инструмент после bootstrap

При любых dump/load в этом репо:

1. Смотри `tools.preferredDump` в `project.json`.
2. `ibcmd` → skill **`1c-ibcmd-pack`** / `Invoke-1cIbcmdDump.ps1` (`infobase.path` или `infobase.dbms`).
3. `agent` или ibcmd недоступен → skill **`1c-designer-agent`**.
4. Пользователь явно сказал «через агент» / «через ibcmd» — слушай запрос, не только конфиг.
