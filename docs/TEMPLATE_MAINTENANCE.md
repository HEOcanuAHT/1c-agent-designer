# Разработка самого шаблона (не конфигурации)

Этот документ — про правки репозитория **1c-agent-designer**.  
Для разработки конкретной конфы см. [WORKFLOW.md](WORKFLOW.md).

## Cursor

Открывать отдельный workspace с этим репозиторием:

- клон: `https://github.com/HEOcanuAHT/1c-agent-designer`
- или локальный Folder с этим репозиторием

Репозиторий **конкретной конфигурации** — другое окно Cursor.

## Что можно менять здесь

| Можно | Нельзя |
|--------|--------|
| `.cursor/skills` (bootstrap, std-*, designer-agent, ibcmd-pack, external-epf, external-cfe, tech-decisions) | XML конкретной конфы в `src/` (кроме `src/README.md`, `src/_extDataProcessors/README.md`, `src/_extensions/README.md`) |
| `.cursor/agents/implementer.md` | Секреты, пути к личным ИБ |
| `.cursor/rules`, каркас `.1c/*.example`, `docs/*` шаблона | Коммиты под одну конфу без обобщения |
| `.gitignore`, MR-шаблон, README шаблона | |

`src/` в шаблоне — пустой каркас: `README.md`, `src/_extDataProcessors/README.md`, `src/_extensions/README.md` (без XML конкретной конфы/внешек/расширений).

## Git

1. Ветка от `main`: `feature/…` или `fix/…`
2. PR на GitHub → merge в `main`
3. Не пушить экспериментальный мусор напрямую в `main` без PR (по возможности)

Репо: https://github.com/HEOcanuAHT/1c-agent-designer

## После изменения skills/rules

1. **Подними `version`** в `.1c/template-manifest.json` (и в `project.json.example` → `template.version`).
2. При **breaking change** для живых проектов — обнови `docs/TEMPLATE_UPGRADE.md` и краткий пункт в `upgradeNotes` манифеста.
3. Если файл нужен **только в шаблоне** (например `template-maintenance.mdc`) — добавь в `projectSkipPaths`, не в allowlist проектов.
4. Запушить в шаблон.
5. Живые проекты подтягивают tooling через skill **`1c-template-sync`** / `Sync-1cTemplate.ps1` (allowlist, **без** `src/` и секретов).

Пример:

```powershell
# в корне проекта конфигурации
.\.cursor\skills\1c-template-sync\scripts\Sync-1cTemplate.ps1 -Action check -ProjectRoot .
.\.cursor\skills\1c-template-sync\scripts\Sync-1cTemplate.ps1 -Action sync -ProjectRoot .
```

## Чеклист перед PR в шаблон

- [ ] Нет имён/путей конкретной конфы и личных серверов
- [ ] Load по-прежнему без `update-db-cfg` (правило `1c-designer-agent`)
- [ ] Примеры в `.1c/*.example`, не `project.local.json`
- [ ] README/docs обновлены, если менялся процесс
- [ ] При изменении tooling поднят `version` в `template-manifest.json` (+ example)
