# Разработка самого шаблона (не конфигурации)

Этот документ — про правки репозитория **1c-agent-designer**.  
Для разработки конкретной конфы см. [WORKFLOW.md](WORKFLOW.md).

## Cursor

Открывать отдельный workspace с этим репозиторием:

- клон: `https://github.com/HEOcanuAHT/1c-agent-designer`
- или локальный Folder с этим репозиторием

Репозиторий **конкретной конфигурации** — другое окно Cursor.

### Локальный плагин (dogfood)

Junction (не требует Developer Mode):

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.cursor\plugins\local" | Out-Null
cmd /c mklink /J "%USERPROFILE%\.cursor\plugins\local\1c-agent-designer" "<абсолютный путь к этому репо>"
```

**Developer: Reload Window.** Customize: skills/rules плагина на месте; `template-maintenance` — только из `.cursor/rules` этого репо, не из манифеста плагина.

Пустой проект 1С: открыть папку → «настрой окружение» → bootstrap копирует каркас, skills в репо не кладёт.

## Что можно менять здесь

| Можно | Нельзя |
|--------|--------|
| `.cursor-plugin/plugin.json`, `.cursor/skills` (bootstrap, std-*, 1c-forms, 1c-metadata-manage, designer-agent, ibcmd-pack, external-epf/cfe, tech-decisions) | XML конкретной конфы в `src/` (кроме `src/README.md`, `src/_extDataProcessors/README.md`, `src/_extensions/README.md`) |
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

1. **Подними `version`** в `.1c/template-manifest.json`, `.cursor-plugin/plugin.json` и в `project.json.example` → `template.version`.
2. При **breaking change** для живых проектов — обнови `docs/TEMPLATE_UPGRADE.md` и краткий пункт в `upgradeNotes` манифеста.
3. Если файл нужен **только в шаблоне** (например `template-maintenance.mdc`) — добавь в `projectSkipPaths` **и** не включай в `.cursor-plugin/plugin.json` → `rules`.
4. Запушить в шаблон. Для плагина: Reload Window (junction уже смотрит на этот клон).
5. Живые **клоны** с `.cursor/skills` в git — skill **`1c-template-sync`**. Проекты только с плагином — не копировать skills, только обновить плагин + Reload.

Пример sync (только клоны):

```powershell
# в корне проекта конфигурации, если есть .cursor/skills
.\.cursor\skills\1c-template-sync\scripts\Sync-1cTemplate.ps1 -Action check -ProjectRoot .
.\.cursor\skills\1c-template-sync\scripts\Sync-1cTemplate.ps1 -Action sync -ProjectRoot .
```

## Чеклист перед PR в шаблон

- [ ] Нет имён/путей конкретной конфы и личных серверов
- [ ] Load по-прежнему без `update-db-cfg` (правило `1c-designer-agent`)
- [ ] Примеры в `.1c/*.example`, не `project.local.json`
- [ ] README/docs обновлены, если менялся процесс
- [ ] При изменении tooling поднят `version` в `template-manifest.json`, `plugin.json` (+ example)
