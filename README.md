# Шаблон проекта конфигурации 1С

Переиспользуемый каркас и **Cursor Plugin** для разработки конфигурации 1С:

- иерархическая выгрузка в `src/`
- skills стандартов ИТС (`coding-standards`, `std-*`)
- dump/load: skill **`1c-dump`** (`tools.preferredDump` → ibcmd или designer-agent)
- внешние обработки через `1c-external-epf` (`ext`)
- расширения через `1c-external-cfe` (`cfe` → `.cfe`)
- проверка языка запросов: skill `1c-query-validate` (opt-in)
- справка платформы: skill **`1c-syntax`** (MCP `bsl-syntax`, sqlite из `shcntx_ru.hbk` через bsl-ctx; `/1c-syntax-index`)
- общий runtime: `1c-runtime`; упаковка `.cf` — `1c-ibcmd-pack`
- субагент `/implementer` (только файлы; сборка и ИБ — основной агент)

Предпочтительно: skills/rules живут в **плагине**, репозиторий конфы — `src/` + `.1c/`.  
Клоны шаблона с `.cursor/skills` в git по-прежнему работают (`1c-template-sync`).

## Правки самого шаблона / плагина

Отдельное окно Cursor с клоном `1c-agent-designer`. Процесс: [docs/TEMPLATE_MAINTENANCE.md](docs/TEMPLATE_MAINTENANCE.md).

Репозиторий конкретной конфигурации — **отдельный** workspace, не смешивать с правками шаблона.

## Репозиторий

- GitHub: https://github.com/HEOcanuAHT/1c-agent-designer
- Clone: `https://github.com/HEOcanuAHT/1c-agent-designer.git`

## Локальная установка плагина

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.cursor\plugins\local" | Out-Null
cmd /c mklink /J "%USERPROFILE%\.cursor\plugins\local\1c-agent-designer" "D:\path\to\1c-agent-designer"
```

Подставь путь к клону шаблона. Затем в Cursor: **Developer: Reload Window**.  
Customize → skills/rules `1c-agent-designer`. Rule `template-maintenance` в плагин не входит.

## Быстрый старт новой конфигурации

**Плагин (предпочтительно):** пустая папка в Cursor → Reload после установки плагина → «настрой окружение».  
Агент копирует каркас из плагина и спрашивает ИБ (`1c-project-bootstrap`).

**Клон шаблона (legacy):**

```powershell
git clone https://github.com/HEOcanuAHT/1c-agent-designer.git my-config
cd my-config
# открыть папку в Cursor и попросить агента: «настрой окружение» / bootstrap
```

Дальше: [docs/INITIAL_DUMP.md](docs/INITIAL_DUMP.md), [docs/WORKFLOW.md](docs/WORKFLOW.md), [AGENTS.md](AGENTS.md).

## Структура

```text
.cursor-plugin/plugin.json   # манифест Cursor Plugin
.cursor/
  agents/implementer.md
  commands/              # /1c-syntax-index, /1c-syntax-status
  rules/
  skills/                # 1c-invariants (канон Always), bootstrap, dump, 1c-syntax, std-*, …
mcp.json                 # MCP bsl-syntax (обёртка bsl-ctx)
.1c/                     # project.json.example, template-manifest.json, secrets example
docs/
src/                     # XML основной конфы (только дамп платформы)
ext/                     # XML внешних обработок
cfe/                     # XML расширений (.cfe)
.gitlab/merge_request_templates/
```
