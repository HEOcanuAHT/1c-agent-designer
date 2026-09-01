# После обновления шаблона в живом проекте

После `Sync-1cTemplate.ps1 -Action sync` сверь конфиг с актуальным шаблоном.  
`project.json` / `project.local.json` sync **не перезаписывает** (кроме `template.version`).

Канон полей: [`.1c/README.md`](../.1c/README.md) и `.1c/project.json.example`.  
Новые breaking-changes — `upgradeNotes` в `.1c/template-manifest.json` (скрипт печатает `UPGRADE …`).

Проекты **без** `.cursor/skills` в git: не sync, а обновление плагина (`git pull` шаблона + Reload Window).

Инварианты 1С живут в skill **`1c-invariants`** плагина (не копировать `.mdc` в проект). В `AGENTS.md` проекта должна быть строка «сразу прочитай skill `1c-invariants`»; если ещё «rule `1c-invariants`» — замени (bootstrap/sync подтянет новый `AGENTS.md`).

### 2026.09.01.7 — CLI служебной ИБ

`1c-runtime/scripts/Invoke-1cServiceIb.ps1 -Action ensure` (без apply). Не dotsource `Ensure-ServiceIb` через `-Command`. `Invoke-1cValidateQuery -Action ensure` — только для query-validate (apply).

### 2026.09.01.6 — MCP quotes

`cmd /c` вызывает `mcp-serve.cmd` без вложенных кавычек вокруг `-File`.

### 2026.09.01.5 — MCP shim

Запуск через `%LOCALAPPDATA%\\1c-agent-designer\\mcp-serve.ps1`. `%PLUGIN_ROOT%` Cursor в env не ставит.

### 2026.09.01.4 — MCP spawn path

`mcp.json` не использует `./`: Cursor раскрывает `.` относительно workspace. Запуск через `cmd.exe` и `%PLUGIN_ROOT%`.

### 2026.09.01.3 — MCP target version

Общий MCP без `BSL_CTX_TARGET_VERSION` на старте. Совместимость: агент, `since` vs `CompatibilityMode` проекта. `${workspaceFolder}` на процесс не вешать.

### 2026.09.01.2 — marketplace.json

UI «подключить локально» требует `.cursor-plugin/marketplace.json`. Junction в `plugins/local` Cursor отвергает.

### 2026.09.01.1 — справка платформы

Skill `1c-syntax`, команды `/1c-syntax-index` и `/1c-syntax-status`, MCP `bsl-syntax`. Нужен `uv`. База в `%LOCALAPPDATA%\bsl-ctx\`, не в git. Reload Window после установки плагина.

### 2026.08.31.1 — новые объекты

Живая конфа: не `meta-compile` / `cf-edit add-childObject`. Пустышка в Конфигураторе → dump → заполнение. Канон в skill `1c-invariants` (plugin-rule `1c-meta-stubs` может не попасть в чат).

## Порядок

1. `check` → `sync` (сначала `-DryRun` по желанию).
2. Сверить `.1c/project.json` с `.1c/project.json.example` и `.1c/README.md`.
3. Проверить `project.local.json` на plaintext `auth.password` → CredMgr (skill `1c-template-sync`).
4. `ping` выбранным dump-инструментом.
5. Отдельный коммит tooling (не смешивать с `src/`).

## Для разработчиков шаблона

При breaking change для живых проектов:

1. Поднять `version` в `.1c/template-manifest.json` (+ `template.version` в example, `version` в `plugin.json`).
2. Обновить **этот файл** — только дельта «что сделать после sync», без копии схемы из `.1c/README.md`.
3. Краткий пункт в `upgradeNotes` манифеста (для одного вывода `UPGRADE` после sync).
