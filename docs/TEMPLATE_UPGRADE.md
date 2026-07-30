# После sync шаблона в живом проекте

После `Sync-1cTemplate.ps1 -Action sync` сверь конфиг с актуальным шаблоном.  
`project.json` / `project.local.json` sync **не перезаписывает** (кроме `template.version`).

## Порядок

1. `check` → `sync` (сначала `-DryRun` по желанию).
2. Сверить `.1c/project.json` с `.1c/project.json.example` и `.1c/README.md`.
3. Проверить `project.local.json` на plaintext `auth.password` → CredMgr (skill `1c-template-sync`).
4. `ping` выбранным dump-инструментом.
5. Отдельный коммит tooling (не смешивать с `src/`).

## Ожидаемая форма `project.json` (текущая версия)

### `tools.preferredDump`

`"ibcmd"` при доступе к SQL/файловой ИБ, иначе `"agent"`.

### `infobase` — один блок для agent и ibcmd

| `type` | Поля | designer-agent | ibcmd |
|--------|------|----------------|-------|
| `file` | `path` | `/F` | `--db-path` |
| `ibname` | `name` + `dbms` | `/IBName` | SQL через `dbms` |
| `server` | `server` + `dbms` | `/S` | SQL через `dbms` |

`dbms` — только в `infobase`, не в `ibcmd`. Для файловой ИБ блок `dbms` не нужен.

Пример серверной ИБ:

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
}
```

### Auth — два слоя (не путать)

| Слой | Где | Назначение |
|------|-----|------------|
| SQL | `infobase.dbms.windowsAuth` / `dbms.credentialTarget` | только ibcmd → СУБД |
| 1С | `auth.credentialTarget` (CredMgr) | пользователь ИБ в ibcmd и designer-agent |

`auth.credentialTarget` — **не** логин SQL. Пароль 1С — в Credential Manager, не в git.

### `ibcmd` — только настройки инструмента

`dataDir`, `stagingDir`, `parkDir`, `preservePaths` — без подключения к ИБ.

Полный `export` в непустой `src/`: скрипт сам делает staging (`.1c/ibcmd-dump-staging/`) и сохраняет `README.md`, `_extDataProcessors/`, `_extensions/`.  
Инкремент: preserve → `.1c/ibcmd-dump-park/`, `--sync` сразу в `src/`.

### Внешние обработки и расширения

```json
"ext": {
  "dir": "src/_extDataProcessors",
  "artifacts": "artifacts/ext",
  "serviceIb": { "enabled": true, "dbPath": ".1c/ib-ext", "dataDir": ".1c/ib-ext-data" }
},
"cfe": {
  "dir": "src/_extensions",
  "artifacts": "artifacts/cfe"
}
```

Дефолты совпадают — блоки опциональны.

### Роли агентов

- `/implementer` — только BSL/XML в репозитории.
- Основной агент — scaffold/pack/dump, load конфы (rule `1c-orchestrator`).

## Для разработчиков шаблона

При breaking change для живых проектов:

1. Поднять `version` в `.1c/template-manifest.json` (+ `template.version` в example).
2. Обновить **этот файл** — актуальная форма конфига, без истории версий.
3. Краткий пункт в `upgradeNotes` манифеста (для одного вывода `UPGRADE` после sync).
