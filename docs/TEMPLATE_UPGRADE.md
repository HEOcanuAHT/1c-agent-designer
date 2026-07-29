# Обновление tooling шаблона в живом проекте

После `Sync-1cTemplate.ps1 -Action sync` скрипт печатает `UPGRADE …` для пропущенных версий.  
Агент: выполни шаги **по порядку**, `project.json` / `project.local.json` — **вручную** (sync их не трогает, кроме `template.version`).

## Общий порядок (любое обновление)

1. `check` → `sync` (сначала `-DryRun` по желанию).
2. Прочитать вывод `UPGRADE` / этот файл для пропущенных версий.
3. Проверить `.1c/project.json` по `.1c/project.json.example` и `.1c/README.md`.
4. Проверить `project.local.json` на plaintext `auth.password` → CredMgr (skill `1c-template-sync`).
5. `ping` выбранным dump-инструментом.
6. Отдельный коммит tooling (не смешивать с `src/`).

**Не делаем:** цепочку автоматических «обработчиков» как в конфигурации 1С — слишком мало breaking changes, `project.json` у каждого свой. Автоматизируем только безопасное (CredMgr, подсказки).

---

## ≥ 2026.07.29.1 — UTF-8 BOM у Sync-скрипта

**Симптом:** `Sync-1cTemplate.ps1` на Windows PowerShell 5.1 — ошибка парсинга (часто вокруг `Write-Host` с `;` в строке).  
**Причина:** файл без UTF-8 BOM; PS 5.1 иначе ломает разбор.  
**Фикс:** в шаблоне скрипт сохранён с BOM. Первый sync после этой версии — клоном шаблона (локальный битый скрипт пилота не запускать).

---

## ≥ 2026.07.28.4 — единый `infobase`

**Зачем:** одно описание ИБ; agent и ibcmd читают разные поля из одного блока.

### Проверить `infobase`

| `type` | Нужные поля | Кто что берёт |
|--------|-------------|---------------|
| `file` | `path` | agent `/F`, ibcmd `--db-path` |
| `ibname` | `name` + `dbms` | agent `/IBName`, ibcmd SQL |
| `server` | `server` + `dbms` | agent `/S`, ibcmd SQL |

### Миграция конфига (ручная)

1. **`dbms` только в `infobase`**, не в `ibcmd`:
   - было `ibcmd.dbms` → перенести в `infobase.dbms`, удалить из `ibcmd`.
   - было `infobase.dbms` при `type: file` — убрать `dbms` (файловой ИБ SQL не нужен).

2. **Серверная ИБ** — не смешивать file и C/S:
   ```json
   "infobase": {
     "type": "ibname",
     "name": "Имя из списка 1С",
     "dbms": {
       "kind": "MSSQLServer",
       "server": "sql-host",
       "name": "db_name",
       "windowsAuth": true
     }
   }
   ```
   Без доступа к SQL: `tools.preferredDump: "agent"`, `dbms` не заполнять.

3. **`ibcmd`** — только инструмент: `dataDir`, `stagingDir`, `parkDir`, `preservePaths` (без подключения к ИБ).

4. Свериться с `.1c/README.md`.

### ibcmd staging / park (≥ 2026.07.28.3, park ≥ 2026.07.29.2)

Полный `export` требует пустой каталог — `Invoke-1cIbcmdDump.ps1` сам делает staging в `.1c/ibcmd-dump-staging/` и сохраняет `README.md` / `_extDataProcessors/`. Инкремент: preserve → `.1c/ibcmd-dump-park/`, `--sync` сразу в `src/`. Менять `src/` вручную не нужно.

### ibcmd: два auth (≥ 2026.07.29.3)

`auth.credentialTarget` — только пользователь **1С**. SQL: `infobase.dbms.windowsAuth` (или при `false` — `dbms.credentialTarget` / `dbms.user`). Не подставлять CredMgr 1С в `--db-user`.


---

## ≥ 2026.07.28.2 — auth в Credential Manager

Если в `project.local.json` есть `auth.password` → предложить `Migrate-1cAuthToCredMgr.ps1`.  
В JSON оставить `auth.credentialTarget`, не plaintext.

---

## ≥ 2026.07.28.1 — `tools.preferredDump`

Если нет `tools.preferredDump` — добавить `"ibcmd"` (при доступе к SQL/файлу) или `"agent"`.

---

## Для разработчиков шаблона

Новый breaking change для живых проектов:

1. Поднять `version` в `.1c/template-manifest.json`.
2. Добавить секцию **сюда** (заголовок `≥ YYYY.MM.DD.N`).
3. Дублировать краткий пункт в `template-manifest.json` → `upgradeNotes` (для вывода sync).
