# Шаблон проекта конфигурации 1С

Переиспользуемый каркас Git-репозитория для разработки конфигурации 1С в Cursor:

- иерархическая выгрузка в `src/`
- skills стандартов ИТС (`coding-standards`, `std-*`)
- dump/load через `1c-designer-agent`
- внешние обработки через `1c-external-epf` (`src/_extDataProcessors`)
- упаковка через `1c-ibcmd-pack` (по запросу)
- субагент `/implementer`

**Не включает** персональный оркестратор (feature-pipeline, SDMS, analyst/planner/reviewer) — он живёт в отдельном ките.

## Правки самого шаблона

Отдельное окно Cursor: [`1c-project-template.code-workspace`](../1c-project-template.code-workspace)  
(или каталог `1c-project-template`). Процесс: [docs/TEMPLATE_MAINTENANCE.md](docs/TEMPLATE_MAINTENANCE.md).

Пилот конфигурации (Комбаза + кит) — **другое** workspace, не смешивать с правками шаблона.

## Репозиторий

- GitLab: https://git.dns-shop.ru/Dackov.AI/1c-project-template
- Clone: `https://git.dns-shop.ru/Dackov.AI/1c-project-template.git`

## Быстрый старт новой конфигурации

```powershell
git clone https://git.dns-shop.ru/Dackov.AI/1c-project-template.git my-config
cd my-config
# открыть папку в Cursor и попросить агента: «настрой окружение» / bootstrap
# либо вручную:
Copy-Item .1c\project.json.example .1c\project.json
Copy-Item .1c\project.local.json.example .1c\project.local.json
# заполнить platformVersion, infobase (file|server|ibname), auth в local
```

Агент следует skill **`1c-project-bootstrap`**: проверит Python/`paramiko`/платформу, предложит доустановить, спросит тип ИБ и запишет `.1c/project*.json`.

Дальше: [docs/INITIAL_DUMP.md](docs/INITIAL_DUMP.md), [docs/WORKFLOW.md](docs/WORKFLOW.md), [AGENTS.md](AGENTS.md).

## Структура

```text
.cursor/
  agents/implementer.md
  rules/                 # bootstrap, load без БД, git/XML
  skills/                # bootstrap, coding-standards, std-*, designer-agent, external-epf, ibcmd-pack, …
.1c/                     # project.json.example, secrets example
docs/
src/                     # XML-выгрузка конфигурации + _extDataProcessors (внешки)
.gitlab/merge_request_templates/
```

## Связка с личным китом

Multi-root в Cursor:

1. этот шаблон (или клон под конкретную конфу);
2. кит оркестрации `1C` (feature-pipeline / SDMS) — по желанию.

Пилот конкретной конфигурации (например Коммерческая База) — отдельный репозиторий, собранный на базе этого шаблона.
