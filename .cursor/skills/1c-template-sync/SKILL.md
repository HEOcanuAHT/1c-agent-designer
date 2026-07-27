---
name: 1c-template-sync
description: >-
  Подтянуть обновления шаблона 1c-agent-designer в проект конфигурации без
  изменения src/ и секретов ИБ. Use when user asks обновить шаблон / sync
  template / подтянуть skills, or project template version is outdated.
---

# Обновление шаблона в проекте конфигурации

## Когда запускать

- Пользователь: «обнови шаблон», «подтяни skills/rules», sync template
- Правило предложило обновление — только после согласия
- После clone шаблона давно; манифест отсутствует или версия отстаёт

## Жёсткие границы

**Никогда не трогать:**

- `src/` (XML конфигурации и внешние обработки проекта)
- `.1c/project.json`, `.1c/project.local.json` (кроме поля `template.*` после sync)
- каталоги ИБ / `artifacts/` / runtime `.1c/*`

**Обновляется (allowlist из `.1c/template-manifest.json`):**

- `.cursor/skills`, `.cursor/rules` (кроме template-only), `.cursor/agents`
- `docs/WORKFLOW.md`, `docs/INITIAL_DUMP.md`
- `AGENTS.md`, `.1c/*.example`, `.1c/README.md`, `.1c/template-manifest.json`
- `.gitlab/merge_request_templates`

**Не копируется в проекты** (`projectSkipPaths`):  
`.cursor/rules/template-maintenance.mdc`, `docs/TEMPLATE_MAINTENANCE.md` — только для репо шаблона. Если в проекте уже лежат — sync их **удалит**.

Опционально (`-IncludeOptional`): `.gitignore`, `README.md` — **спрашивать отдельно**.

Свои skills/rules проекта (имена, которых нет в шаблоне) **не удаляются**.

Скрипт всегда:  
`.cursor/skills/1c-template-sync/scripts/Sync-1cTemplate.ps1`  
(не ищи в `tools/`). Clone шаблона во temp делай **вне sandbox** / с полными правами — иначе клон может пропасть.

## Первый sync со старого пилота (нет skill/манифеста)

В проекте ещё нет `1c-template-sync`. Не копируй репо шаблона целиком поверх пилота.

1. `git clone --depth 1 https://github.com/HEOcanuAHT/1c-agent-designer.git` во временную папку (или `-TemplateRoot` на локальный клон).
2. Запусти скрипт **из клона шаблона**, цель = пилот:

```powershell
# cwd = клон шаблона
.\.cursor\skills\1c-template-sync\scripts\Sync-1cTemplate.ps1 `
  -Action sync `
  -ProjectRoot "C:\path\to\pilot" `
  -TemplateRoot .
```

3. После этого в пилоте появятся skill, манифест и `template.*` в `project.json`. Дальше sync можно делать уже из пилота.

Если пользователь дал только URL шаблона — сделай clone во temp и шаг 2; **не** трогай `src/` и секреты вручную в обход скрипта.

## Источник шаблона

1. Локальный клон: `-TemplateRoot "C:\...\1c-agent-designer"`
2. Или GitHub: скрипт сам сделает shallow clone (`manifest.url` / `-TemplateUrl`)

URL по умолчанию: `https://github.com/HEOcanuAHT/1c-agent-designer.git`

## Команды

Корень = репозиторий **проекта конфигурации** (не обязательно шаблон).

```powershell
# Версия локально
.\.cursor\skills\1c-template-sync\scripts\Sync-1cTemplate.ps1 -Action status -ProjectRoot .

# Сравнить с шаблоном (локальный клон)
.\.cursor\skills\1c-template-sync\scripts\Sync-1cTemplate.ps1 -Action check -ProjectRoot . -TemplateRoot "C:\path\to\1c-agent-designer"

# Сравнить с GitHub main
.\.cursor\skills\1c-template-sync\scripts\Sync-1cTemplate.ps1 -Action check -ProjectRoot .

# Пробный прогон
.\.cursor\skills\1c-template-sync\scripts\Sync-1cTemplate.ps1 -Action sync -ProjectRoot . -DryRun

# Применить
.\.cursor\skills\1c-template-sync\scripts\Sync-1cTemplate.ps1 -Action sync -ProjectRoot .
```

Коды `check`: `0` up-to-date, `2` нет локальной версии, `3` outdated.

## Поведение агента

1. Кратко предложи: «В шаблоне есть обновления tooling. Подтянуть skills/rules без `src/`?»
2. Не синкать без согласия.
3. После согласия: `check` → `sync` (сначала `-DryRun`, если пользователь хочет посмотреть).
4. Покажи итог: новая `version`, список `SYNC …`.
5. Напомни: `project.json` / `src/` не менялись (кроме `template.version` в project.json, если файл есть).
6. Предложи закоммитить изменения tooling отдельным коммитом в проекте.

## Версии

Источник истины: `.1c/template-manifest.json` → поле `version` (в шаблоне и после sync в проекте).  
В `.1c/project.json` после sync пишется блок:

```json
"template": {
  "name": "1c-agent-designer",
  "version": "2026.07.27.1",
  "url": "https://github.com/HEOcanuAHT/1c-agent-designer.git",
  "ref": "main"
}
```
