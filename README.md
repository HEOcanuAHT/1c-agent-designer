# Шаблон проекта конфигурации 1С

Переиспользуемый каркас Git-репозитория для разработки конфигурации 1С в Cursor:

- иерархическая выгрузка в `src/`
- skills стандартов ИТС (`coding-standards`, `std-*`)
- dump/load: предпочтительно **ibcmd** (`1c-ibcmd-pack`), запасной путь — `1c-designer-agent`
- внешние обработки через `1c-external-epf` (`src/_extDataProcessors`)
- упаковка `.cf` через `1c-ibcmd-pack`
- обновление шаблона в живых проектах: `1c-template-sync` (без `src/`)
- субагент `/implementer`

**Не включает** персональный оркестратор (feature-pipeline, SDMS, analyst/planner/reviewer) — он живёт в отдельном ките.

## Правки самого шаблона

Отдельное окно Cursor с клоном `1c-agent-designer`. Процесс: [docs/TEMPLATE_MAINTENANCE.md](docs/TEMPLATE_MAINTENANCE.md).

Пилот конкретной конфигурации (+ кит) — **другое** workspace, не смешивать с правками шаблона.

## Репозиторий

- GitHub: https://github.com/HEOcanuAHT/1c-agent-designer
- Clone: `https://github.com/HEOcanuAHT/1c-agent-designer.git`

## Быстрый старт новой конфигурации

```powershell
git clone https://github.com/HEOcanuAHT/1c-agent-designer.git my-config
cd my-config
# открыть папку в Cursor и попросить агента: «настрой окружение» / bootstrap
# либо вручную:
Copy-Item .1c\project.json.example .1c\project.json
Copy-Item .1c\project.local.json.example .1c\project.local.json
# заполнить platformVersion, infobase (file|server|ibname), auth в local
```

Агент следует skill **`1c-project-bootstrap`**: Todo-чеклист и короткие вопросы (тип ИБ → auth → ibcmd или agent → доступ к SQL), затем `.1c/project*.json` (`tools.preferredDump`).

Дальше: [docs/INITIAL_DUMP.md](docs/INITIAL_DUMP.md), [docs/WORKFLOW.md](docs/WORKFLOW.md), [AGENTS.md](AGENTS.md).

## Структура

```text
.cursor/
  agents/implementer.md
  rules/                 # bootstrap, load без БД, git/XML
  skills/                # bootstrap, template-sync, coding-standards, std-*, designer-agent, …
.1c/                     # project.json.example, template-manifest.json, secrets example
docs/
src/                     # XML-выгрузка конфигурации + _extDataProcessors (внешки)
.gitlab/merge_request_templates/
```

## Связка с личным китом

Multi-root в Cursor:

1. этот шаблон (или клон под конкретную конфу);
2. кит оркестрации `1C` (feature-pipeline / SDMS) — по желанию.

Пилот конкретной конфигурации (например Коммерческая База) — отдельный репозиторий, собранный на базе этого шаблона.
