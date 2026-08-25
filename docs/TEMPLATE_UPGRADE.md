# После sync шаблона в живом проекте

После `Sync-1cTemplate.ps1 -Action sync` сверь конфиг с актуальным шаблоном.  
`project.json` / `project.local.json` sync **не перезаписывает** (кроме `template.version`).

Проекты **без** `.cursor/skills` в git: не sync, а обновление плагина (`git pull` шаблона + Reload Window).

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

`dataDir`, `parkDir`, `preservePaths` — без подключения к ИБ. `stagingDir` больше не используется.

Полный `export` в непустой `src/`: спросить пользователя → `-WipeOutDir` (очистить `src/`, export сразу туда).  
Инкремент: `--sync` сразу в `src/`. Park только для хвостов старого layout внутри `src/`.

### Внешние обработки и расширения

Исходники **вне** `src/`:

```json
"ext": {
  "dir": "ext",
  "artifacts": "artifacts/ext",
  "serviceIb": { "enabled": true, "dbPath": ".1c/ib-ext", "dataDir": ".1c/ib-ext-data" }
},
"cfe": {
  "dir": "cfe",
  "artifacts": "artifacts/cfe"
}
```

Sync tooling **не** двигает папки и **не** правит `ext.dir` / `cfe.dir` в рабочем `project.json`. В живом проекте после обновления плагина (Reload Window) вставь агенту промпт ниже.

### Промпт агенту в живом проекте (≥ 2026.08.24.1)

```
Миграция раскладки шаблона 2026.08.24.1. Сделай сам, без лишних вопросов если пути старые есть на диске.

Цель:
- src/ — только XML основной конфы (дамп платформы). Без README.md, без _extDataProcessors, без _extensions.
- XML внешек → ext/  (ext.dir)
- XML расширений → cfe/  (cfe.dir)

Шаги:
1. Покажи что есть: src/_extDataProcessors, src/_extensions, src/README.md, блоки ext/cfe в .1c/project.json (и project.local.json, если там dir).
2. Если src/_extDataProcessors есть — git mv (или Move-Item, если не в git) в ext/. Если ext/ уже есть — смержи содержимое, не затирай чужое.
3. Если src/_extensions есть — то же в cfe/.
4. src/README.md удали, только если это каркас шаблона (про выгрузку/staging/_ext*), не произвольный файл проекта.
5. В .1c/project.json выставь "ext":{"dir":"ext"} и "cfe":{"dir":"cfe"} (остальные поля ext/cfe не трогай). Удали ibcmd.stagingDir, если есть. То же в project.local.json, только если там переопределены dir.
6. Не трогай XML конфы в src/ (Catalogs, Documents, Configuration.xml, …), .1c/ib-ext, artifacts, пароли.
7. git status: только перенос папок + правки json. Не коммить, пока не попрошу.

Если папок src/_ext* нет и dir уже ext/cfe — напиши «уже мигрировано» и ничего не меняй.
```

### CFE: CompatibilityMode и имена (≥ 2026.07.31.1)

При ошибке «режим совместимости… не соответствует версии ИБ» на scaffold/pack:  
`-AllowServiceIbApplyOnCompatMismatch` (apply **только** служебной `.1c/ib-ext`).  
Имена расширения для ibcmd — ASCII. Adopted XML: skill `1c-external-cfe` / `reference-adopted.md`.

### Роли агентов

- `/implementer` — только BSL/XML в репозитории.
- Основной агент — scaffold/pack/dump, load конфы (rule `1c-orchestrator`).

### Knowledge / XML (с 2026.07.31.2)

После sync появятся skills: `1c-forms`, `1c-metadata-manage`, `std-anti-patterns`, `std-extension-patterns`, `std-dcs-design`, `std-registers-design`, `std-architecture`, `std-logging`, `std-integrations`, …  
Роутер — обновлённый `coding-standards`.  
**Не** используют upstream dump/load/`UpdateDBCfg`/epf-build — канон по-прежнему `1c-ibcmd-pack` / `1c-designer-agent` / `1c-external-*`.

## Для разработчиков шаблона

При breaking change для живых проектов:

1. Поднять `version` в `.1c/template-manifest.json` (+ `template.version` в example).
2. Обновить **этот файл** — актуальная форма конфига, без истории версий.
3. Краткий пункт в `upgradeNotes` манифеста (для одного вывода `UPGRADE` после sync).
