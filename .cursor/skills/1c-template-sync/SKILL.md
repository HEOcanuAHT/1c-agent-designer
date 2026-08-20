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

## Плагин без `.cursor/skills` в репо

Если в проекте есть `.1c/project.json` (или каркас bootstrap), но **нет** `.cursor/skills/` — tooling живёт в плагине `1c-agent-designer`.

- «обнови шаблон» → **не** копируй skills в проект.
- Скажи: `git pull` в клоне шаблона (или обнови junction) → **Developer: Reload Window**.
- `Sync-1cTemplate.ps1` — только для клонов, где `.cursor/skills` уже в git.

Скрипт sync по-прежнему: `<SkillHome>/scripts/Sync-1cTemplate.ps1` (`SkillHome` = каталог этого SKILL.md).

## Жёсткие границы

**Никогда не трогать:**

- `src/` (XML конфигурации и внешние обработки проекта)
- `.1c/project.json`, `.1c/project.local.json` (кроме поля `template.*` после sync)
- каталоги ИБ / `artifacts/` / runtime `.1c/*`

**Обновляется (allowlist из `.1c/template-manifest.json`):**

- `.cursor/skills`, `.cursor/rules` (кроме template-only), `.cursor/agents`
- `docs/WORKFLOW.md`, `docs/INITIAL_DUMP.md`, `docs/TEMPLATE_UPGRADE.md`
- `AGENTS.md`, `.1c/*.example`, `.1c/README.md`, `.1c/template-manifest.json`
- `.gitlab/merge_request_templates`

**Не копируется в проекты** (`projectSkipPaths`):  
`.cursor/rules/template-maintenance.mdc`, `docs/TEMPLATE_MAINTENANCE.md` — только для репо шаблона. Если в проекте уже лежат — sync их **удалит**.

Опционально (`-IncludeOptional`): `.gitignore`, `README.md` — **спрашивать отдельно**.

Свои skills/rules проекта (имена, которых нет в шаблоне) **не удаляются**.

Скрипт всегда:  
`.cursor/skills/1c-template-sync/scripts/Sync-1cTemplate.ps1`  
(не ищи в `tools/`). Clone шаблона во temp делай **вне sandbox** / с полными правами — иначе клон может пропасть.

## Первый sync (нет skill/манифеста в проекте)

В проекте ещё нет `1c-template-sync`. Не копируй репо шаблона целиком поверх проекта конфигурации.

1. `git clone --depth 1 https://github.com/HEOcanuAHT/1c-agent-designer.git` во временную папку (или `-TemplateRoot` на локальный клон).
2. Запусти скрипт **из клона шаблона**, цель = проект конфигурации:

```powershell
# cwd = клон шаблона
.\.cursor\skills\1c-template-sync\scripts\Sync-1cTemplate.ps1 `
  -Action sync `
  -ProjectRoot "C:\path\to\my-config" `
  -TemplateRoot .
```

3. После этого в проекте появятся skill, манифест и `template.*` в `project.json`. Дальше sync можно делать уже из проекта.

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
6. **После sync** — проверка секретов (см. ниже); не молча переписывать `project.local.json`.
7. Предложи закоммитить изменения tooling отдельным коммитом в проекте.

## После sync: секреты в `project.local.json` → Credential Manager

Sync **не** трогает `.1c/project.local.json`. Если в файле лежит `auth.password` в открытом виде — предложи перенос в Credential Manager.

### Когда предлагать миграцию

После успешного `sync` прочитай `.1c/project.local.json` (только локально, не в чат):

| Признак | Действие |
|---------|----------|
| `auth.password` непустой | **Предложить** перенос в CredMgr |
| есть `auth.user` + `password`, нет `credentialTarget` | то же |
| только `credentialTarget`, пароля нет | OK, не трогать |
| `auth.required: false` | OK, не трогать |
| `infobase.dbms.windowsAuth: true` | SQL-пароль **не** нужен; CredMgr только для пользователя **1С** |

Коротко спроси одним сообщением:

> «В `project.local.json` пароль ИБ в открытом виде. Перенести в Windows Credential Manager и убрать из файла?»

Без согласия **не** запускать миграцию и **не** выводить пароль в чат.

### Миграция (после согласия)

```powershell
# сначала dry-run
…\1c-project-bootstrap\scripts\Migrate-1cAuthToCredMgr.ps1 -ProjectRoot "<repo>" -WhatIf

# применить (пароль читается из local, в лог не пишется)
…\1c-project-bootstrap\scripts\Migrate-1cAuthToCredMgr.ps1 -ProjectRoot "<repo>"
```

Скрипт: сохраняет user/password в CredMgr → пишет `credentialTarget` → удаляет `auth.password` (и `auth.user`) из local.

Если пользователь предпочитает ввод сам:

```powershell
…\1c-project-bootstrap\scripts\Set-1cIbCredential.ps1 -ProjectRoot "<repo>"
```

и вручную убрать `password` из local.

### Опционально: `tools.preferredDump`

Если в `project.json` нет `tools.preferredDump` — **кратко предложи** добавить вручную (`ibcmd` | `agent`), sync сам `project.json` не меняет. Не навязывать без согласия.

### Чеклист агента после sync

| id | content |
|----|---------|
| `sync-done` | sync skills/rules |
| `sync-upgrade` | сверить `.1c/project.json` с example и `docs/TEMPLATE_UPGRADE.md` |
| `sync-secrets` | проверить local на plaintext password |
| `sync-credmgr` | по согласию Migrate / Set-1cIbCredential |
| `sync-ping` | по согласию ping dump-инструментом |

`sync-credmgr` → `cancelled`, если пароля в файле нет.

### После sync: сверка конфига

Sync **не перезаписывает** `project.json` / `project.local.json` (кроме `template.version`).

1. Сверь `.1c/project.json` с `.1c/project.json.example` и `docs/TEMPLATE_UPGRADE.md` (актуальная форма полей).
2. Если в манифесте есть `upgradeNotes` — скрипт печатает `UPGRADE [версия] …` для пропущенных версий; правки в конфиг — **вручную**, с согласия пользователя.

Автоматически только безопасное: CredMgr, копирование allowlist, `template.version` в `project.json`.

## Версии

Источник истины: `.1c/template-manifest.json` → поле `version` (в шаблоне и после sync в проекте).  
В `.1c/project.json` после sync пишется блок:

```json
"template": {
  "name": "1c-agent-designer",
  "version": "2026.07.30.3",
  "url": "https://github.com/HEOcanuAHT/1c-agent-designer.git",
  "ref": "main"
}
```
