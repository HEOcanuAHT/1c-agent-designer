# Разработка самого шаблона (не конфигурации)

Этот документ — про правки репозитория **1c-agent-designer**.  
Для разработки конкретной конфы см. [WORKFLOW.md](WORKFLOW.md).

## Cursor

Открывать отдельный workspace (не пилот конкретной конфы):

- клон: `https://github.com/HEOcanuAHT/1c-agent-designer`
- или локальный Folder с этим репозиторием

Пилот (конкретная конфа + кит `1C`) — другое окно.

## Что можно менять здесь

| Можно | Нельзя |
|--------|--------|
| `.cursor/skills` (bootstrap, std-*, designer-agent, ibcmd-pack, external-epf, tech-decisions) | XML конкретной конфы в `src/` (кроме `src/README.md`, `src/_extDataProcessors/README.md`) |
| `.cursor/agents/implementer.md` | feature-pipeline / SDMS / analyst-planner-reviewer |
| `.cursor/rules`, каркас `.1c/*.example`, `docs/*` шаблона | Секреты, пути к личной ИБ пилота |
| `.gitignore`, MR-шаблон, README шаблона | Коммиты «под пилот» без обобщения |

`src/` в шаблоне — пустой каркас: `README.md` и `src/_extDataProcessors/README.md` (без XML конкретной конфы/внешек).

## Git

1. Ветка от `main`: `feature/…` или `fix/…`
2. PR на GitHub → merge в `main`
3. Не пушить экспериментальный мусор напрямую в `main` без PR (по возможности)

Репо: https://github.com/HEOcanuAHT/1c-agent-designer

## После изменения skills/rules

1. Запушить в шаблон.
2. Пилоты/новые конфиги подтягивают изменения осознанно:
   - новый проект: `git clone` шаблона;
   - уже живой репо: скопировать нужные пути из шаблона (или subtree/cherry-pick) — **не** автомержить всё подряд.
3. Кит `1C` пока держит копии skills; синхронизация кит ↔ шаблон — отдельная задача (не обязательно в каждом PR).

## Чеклист перед PR в шаблон

- [ ] Нет имён/путей конкретной конфы (пилотные ИБ, СДМС-номера)
- [ ] Load по-прежнему без `update-db-cfg` (правило `1c-designer-agent`)
- [ ] Примеры в `.1c/*.example`, не `project.local.json`
- [ ] README/docs обновлены, если менялся процесс
