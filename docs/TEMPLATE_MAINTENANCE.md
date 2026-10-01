# Разработка плагина (не конфигурации)

Этот документ — про правки репозитория **1c-agent-designer**.  
Для разработки конкретной конфы см. [WORKFLOW.md](WORKFLOW.md).

## Cursor

Открывать отдельный workspace с этим репозиторием:

- клон: `https://github.com/HEOcanuAHT/1c-agent-designer`
- или локальный Folder с этим репозиторием

Репозиторий **конкретной конфигурации** — другое окно Cursor.

### Локальный плагин (dogfood)

Cursor **не** грузит junction/symlink из `~/.cursor/plugins/local`, если цель снаружи этой папки (в логе: `loadUserLocalPlugin … rejected: symlink target … outside …\plugins\local`). Карточки плагина и MCP `bsl-syntax` из-за этого нет.

Нужен `.cursor-plugin/marketplace.json`. Дальше:

1. Customize → Plugins → добавить marketplace: эта папка **или** GitHub `https://github.com/HEOcanuAHT/1c-agent-designer.git`
2. Install `1c-agent-designer`
3. **Developer: Reload Window**

Альтернатива: `git clone` репозитория **внутрь** `%USERPROFILE%\.cursor\plugins\local\1c-agent-designer` (реальные файлы, не junction).

`template-maintenance` — только из `.cursor/rules` этого репо, не из манифеста плагина.

Пустой проект 1С: открыть папку → «настрой окружение» → bootstrap копирует каркас, skills в репо не кладёт.

## Что можно менять здесь

| Можно | Нельзя |
|--------|--------|
| `.cursor-plugin/plugin.json`, `skills` (bootstrap, runtime, dump, std-*, 1c-forms, 1c-metadata-manage, designer-agent, ibcmd-pack, external-epf/cfe, query-validate, tech-decisions) | XML конкретной конфы в `src/` |
| `agents/implementer.md` | Секреты, пути к личным ИБ |
| `rules/`, `.cursor/rules/template-maintenance.mdc`, каркас `.1c/*.example`, `docs/*` плагина | Коммиты под одну конфу без обобщения |
| `.gitignore`, MR-шаблон, README, `ext/README.md`, `cfe/README.md` | |

`src/` здесь пустой (дамп конфы). Каркас внешек/расширений: `ext/README.md`, `cfe/README.md`.

## Git

1. Ветка от `main`: `feature/…` или `fix/…`
2. PR на GitHub → merge в `main`
3. Не пушить экспериментальный мусор напрямую в `main` без PR (по возможности)

Репо: https://github.com/HEOcanuAHT/1c-agent-designer

## После изменения skills/rules

1. **Подними `version`** в `.cursor-plugin/plugin.json` (и то же в `.cursor-plugin/marketplace.json` → `metadata.version`).
2. Правило только этого репозитория — `.cursor/rules/template-maintenance.mdc`. В `rules/` его не клади: манифест `"rules": "rules"` отдаёт каталог в плагин целиком.
3. **Не** ставь `alwaysApply: true` на узкие правила (dump, auth, query-validate). Инварианты — skill **`1c-invariants`** + копия в `1c-invariants.mdc`. Skills и rules в репозиторий конфы не копировать. Plugin-rules с alwaysApply Cursor часто не инжектит.
4. Запушить. У пользователей конфигураций — обновление плагина и **Developer: Reload Window**.

Канон полей `project.json`: `.1c/README.md`.

## Чеклист перед PR

- [ ] Нет имён/путей конкретной конфы и личных серверов
- [ ] Load по-прежнему без `update-db-cfg` (skill `1c-invariants`)
- [ ] Примеры в `.1c/*.example`, не `project.local.json`
- [ ] README/docs обновлены, если менялся процесс
- [ ] При изменении tooling поднят `version` в `plugin.json` и `marketplace.json`
- [ ] `*.ps1` — UTF-8 BOM, без `—`/`…` (rule `ps1-encoding`; lint `.github/scripts/Test-Ps1Encoding.ps1`)
