# `.1c/project.json` — описание информационной базы

**Канон полей** для агента и живых проектов. Таблицы отсюда не копировать в `AGENTS.md` / `WORKFLOW.md`.

Рабочий файл: `project.json.example` → `project.json`. Секреты: `project.local.json` (не в git).  
Bootstrap: skill `1c-project-bootstrap`. Sync tooling: skill `1c-template-sync`.

## `infobase` — одна база, разные инструменты

Блок описывает **саму ИБ**. Скрипты берут из него своё:

| `type` | Поля | designer-agent | ibcmd |
|--------|------|----------------|-------|
| `file` | `path` | `/F` | `--db-path` |
| `ibname` | `name` + **`dbms`** | `/IBName` | `dbms` → SQL (быстрее) |
| `server` | `server` + **`dbms`** | `/S` | `dbms` → SQL |

`dbms` нужен только для **серверной** ИБ и только если используешь **ibcmd** (прямой доступ к СУБД).  
Без доступа к SQL — `tools.preferredDump: agent`, `dbms` можно не заполнять.

### Файловая

```json
"infobase": { "type": "file", "path": "C:/Users/.../InfoBase8" },
"ibcmd": { "dataDir": ".1c/ibcmd-data" }
```

### Серверная (client-server)

```json
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
"tools": { "preferredDump": "ibcmd" }
```

ibcmd через SQL обычно **заметно быстрее** agent; для этого попроси доступ к СУБД у админов.

### Прочее

- `ibcmd` — только настройки **инструмента**: `dataDir`, `parkDir`, `preservePaths` (не подключение к ИБ). `stagingDir` больше не используется.
- `tools.preferredDump`: `ibcmd` | `agent`.
- `ext.dir` — внешние обработки (skill `1c-external-epf`).
- `ext.serviceIb` — служебная файловая ИБ для pack/dump внешек и расширений (save `.cf` с боевой + load, без apply; XML import — fallback; не коммитить). CLI: `1c-runtime/scripts/Invoke-1cServiceIb.ps1 -Action ensure`.
- `cfe.dir` / `cfe.artifacts` — расширения `.cfe` (skill `1c-external-cfe`).
- Проверка языка запросов — skill `1c-query-validate` (COM на `.1c/ib-ext`; opt-in).
- Справка платформы — skill `1c-syntax` (MCP из `shcntx_ru.hbk` через bsl-ctx). Поле в JSON не нужно: берётся `platformVersion`. sqlite в `%LOCALAPPDATA%\bsl-ctx\`.

### Два входа (не путать)

| Слой | Поля | Кто |
|------|------|-----|
| **SQL** | `infobase.dbms.windowsAuth: true` → доменная учётка процесса; при `false` → `dbms.credentialTarget` или `dbms.user` | только **ibcmd** |
| **1С** | `auth.credentialTarget` (CredMgr) → пользователь ИБ | ibcmd `--user` и designer-agent |

`auth.credentialTarget` — **не** логин SQL. Путь CredMgr уже задаётся здесь (`1c-ib/<project>`); для SQL при Windows auth отдельный CredMgr **не нужен**.

```powershell
powershell -NoProfile -File "<SkillHome-1c-project-bootstrap>/scripts/Check-1cDevEnv.ps1" -ProjectRoot "<workspace>"
```
