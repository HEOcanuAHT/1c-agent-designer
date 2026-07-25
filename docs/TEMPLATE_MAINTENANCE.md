# Разработка самого шаблона (не конфигурации)

Этот документ — про правки репозитория **1c-agent-designer**.  
Для разработки конкретной конфы см. [WORKFLOW.md](WORKFLOW.md).

## Cursor

Открывать отдельный workspace (не пилот конкретной конфы):

- Folder: каталог клона `1c-agent-designer`

Пилот конфигурации (+ кит `1C`) — другое окно.

## Что можно менять здесь

| Можно | Нельзя |
|--------|--------|
| `.cursor/skills` (bootstrap, std-*, designer-agent, ibcmd-pack, tech-decisions) | XML конкретной конфы в `src/` (кроме `src/README.md`) |
| `.cursor/agents/implementer.md` | feature-pipeline / SDMS / analyst-planner-reviewer |
| `.cursor/rules`, каркас `.1c/*.example`, `docs/*` шаблона | Секреты, пути к личной ИБ Комбазы |
| `.gitignore`, MR-шаблон, README шаблона | Коммиты «под пилот» без обобщения |

`src/` в шаблоне остаётся пустым каркасом (только README).

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
3. Кит `1C` пока держит копии skills; синхронизация кит ↔ шаблон — отдельная задача (не обязательно в каждом MR).

## Чеклист перед PR в шаблон

- [ ] Нет имён/путей конкретной конфы (Комбаза, InfoBase8, СДМС-номера)
- [ ] Load по-прежнему без `update-db-cfg` (правило `1c-designer-agent`)
- [ ] Примеры в `.1c/*.example`, не `project.local.json`
- [ ] README/docs обновлены, если менялся процесс
