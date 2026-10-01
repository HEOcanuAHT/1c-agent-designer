# Плагин разработки конфигурации 1С

Cursor Plugin `1c-agent-designer` и каркас репозитория конфигурации:

- иерархическая выгрузка в `src/`
- skills стандартов ИТС (`coding-standards`, `std-*`)
- dump/load: skill **`1c-dump`** (`tools.preferredDump` → ibcmd или designer-agent)
- внешние обработки через `1c-external-epf` (`ext`)
- расширения через `1c-external-cfe` (`cfe` → `.cfe`)
- проверка языка запросов: skill `1c-query-validate` (opt-in)
- справка платформы: skill **`1c-syntax`** (MCP `bsl-syntax`, sqlite из `shcntx_ru.hbk` через bsl-ctx; `/1c-syntax-index`)
- общий runtime: `1c-runtime`; упаковка `.cf` — `1c-ibcmd-pack`
- субагент `/implementer` (только файлы; сборка и ИБ — основной агент)

Skills и rules живут в **плагине**. Репозиторий конфы — `src/` + `.1c/`. Skills в проект не копируются.

## Правки плагина

Отдельное окно Cursor с этим репозиторием. Процесс: [docs/TEMPLATE_MAINTENANCE.md](docs/TEMPLATE_MAINTENANCE.md).

Репозиторий конкретной конфигурации — **отдельный** workspace, не смешивать с правками плагина.

## Репозиторий

- GitHub: https://github.com/HEOcanuAHT/1c-agent-designer
- Clone: `https://github.com/HEOcanuAHT/1c-agent-designer.git`

## Локальная установка плагина

Junction / symlink в `~/.cursor/plugins/local` Cursor **отвергает** (target вне этой папки). MCP из плагина из-за этого не появляется.

**Вариант A (предпочтительно):** Customize → Plugins → добавить marketplace с диска или GitHub.

- локально: папка этого репозитория (нужен `.cursor-plugin/marketplace.json`);
- удалённо: `https://github.com/HEOcanuAHT/1c-agent-designer.git`.

Потом **Install** плагина `1c-agent-designer`. MCP `bsl-syntax` живёт у плагина, не в user `mcp.json`.

**Вариант B:** реальный clone (не junction) внутрь `%USERPROFILE%\.cursor\plugins\local\1c-agent-designer`, затем Reload Window.

Rule `template-maintenance` в плагин не входит.

## Быстрый старт новой конфигурации

Пустая папка в Cursor → Reload после установки плагина → «настрой окружение».  
Агент копирует каркас из плагина и спрашивает ИБ (`1c-project-bootstrap`).

Дальше: [docs/INITIAL_DUMP.md](docs/INITIAL_DUMP.md), [docs/WORKFLOW.md](docs/WORKFLOW.md), [AGENTS.md](AGENTS.md).

## Структура

```text
.cursor-plugin/plugin.json   # манифест Cursor Plugin
rules/                       # правила плагина
skills/                      # 1c-invariants, bootstrap, dump, 1c-syntax, std-*, …
agents/implementer.md
commands/                    # /1c-syntax-index, /1c-syntax-status
mcp.json                     # MCP bsl-syntax (обёртка bsl-ctx)
.cursor/rules/               # только template-maintenance (этот репозиторий)
.1c/                     # project.json.example, secrets example
docs/
src/                     # XML основной конфы (только дамп платформы)
ext/                     # XML внешних обработок
cfe/                     # XML расширений (.cfe)
.gitlab/merge_request_templates/
```

## Лицензия

MIT, см. [LICENSE](LICENSE). Copyright (c) 2026 HEOcanuAHT.

Плагин предоставляется **как есть**, без гарантий. Dump/load и другие операции могут изменить конфигурацию и ИБ; бэкап и проверка — на вашей стороне. Сторонние заимствования: [docs/ATTRIBUTION.md](docs/ATTRIBUTION.md). Не связан с фирмой «1С».

