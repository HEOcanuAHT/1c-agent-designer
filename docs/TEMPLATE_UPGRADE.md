# После обновления шаблона в живом проекте

После `Sync-1cTemplate.ps1 -Action sync` сверь конфиг с актуальным шаблоном.  
`project.json` / `project.local.json` sync **не перезаписывает** (кроме `template.version`).

Канон полей: [`.1c/README.md`](../.1c/README.md) и `.1c/project.json.example`.  
История breaking-changes — `upgradeNotes` в `.1c/template-manifest.json` (скрипт печатает `UPGRADE …`).

Проекты **без** `.cursor/skills` в git: не sync, а обновление плагина (`git pull` шаблона + Reload Window).

## Порядок

1. `check` → `sync` (сначала `-DryRun` по желанию).
2. Сверить `.1c/project.json` с `.1c/project.json.example` и `.1c/README.md`.
3. Проверить `project.local.json` на plaintext `auth.password` → CredMgr (skill `1c-template-sync`).
4. `ping` выбранным dump-инструментом.
5. Отдельный коммит tooling (не смешивать с `src/`).

## Эта версия (2026.08.26.6)

- `1c-metadata-manage` / `std-architecture` — короткие роутеры (детали в `docs/`).
- Ownership запросов/C-S — у `std-queries` / `std-client-server`; запахи — `std-anti-patterns`.
- CFE borrow/patch: вход через `1c-external-cfe`, tools остаются в `1c-metadata-manage`.

## Если проект отстаёт

Кратко (детали — `upgradeNotes` манифеста):

| since | Что проверить |
|-------|----------------|
| 2026.08.26.6 | Роутеры metadata-manage / architecture; не тянуть старый монолит architecture |
| 2026.08.26.5 | Skills `1c-runtime`, `1c-dump`; Common-* не из ibcmd-pack |
| 2026.08.26.4 | AlwaysApply → `1c-invariants`; канон полей `.1c/README.md` |
| 2026.08.26.3 | (legacy) Common-* были в `1c-ibcmd-pack/scripts/` |
| 2026.08.26.2 | Query validate — skill `1c-query-validate` |
| 2026.08.26.1 | Служебная ИБ: save→load без apply |
| 2026.08.24.1 | XML внешек/расширений в `ext/` и `cfe/` |

Sync tooling **не** двигает папки и **не** правит `ext.dir` / `cfe.dir` в рабочем `project.json`. Если `src/_extDataProcessors` или `src/_extensions` ещё есть — вставь агенту промпт ниже (после Reload Window).

### Промпт: старый layout `src/_ext*` (≤ 2026.08.24.1)

```
Миграция раскладки шаблона 2026.08.24.1. Сделай сам, без лишних вопросов если пути старые есть на диске.

Цель:
- src/ — только XML основной конфы (дамп платформы). Без README.md, без _extDataProcessors, без _extensions.
- XML внешек → ext/  (ext.dir)
- XML расширений → cfe/  (cfe.dir)

Шаги:
1. Покажи что есть: src/_extDataProcessors, src/_extensions, src/README.md, блоки ext/cfe в .1c/project.json (и project.local.json, если там dir).
2. Если src/_extDataProcessors есть — git mv (или Move-Item, если не в git) в ext/. Если ext/ уже есть — смержи содержимое, не затирай чужое.
3. Если src/_extensions есть — то же в cfe/.
4. src/README.md удали, только если это каркас шаблона (про выгрузку/staging/_ext*), не произвольный файл проекта.
5. В .1c/project.json выставь "ext":{"dir":"ext"} и "cfe":{"dir":"cfe"} (остальные поля ext/cfe не трогай). Удали ibcmd.stagingDir, если есть. То же в project.local.json, только если там переопределены dir.
6. Не трогай XML конфы в src/ (Catalogs, Documents, Configuration.xml, …), .1c/ib-ext, artifacts, пароли.
7. git status: только перенос папок + правки json. Не коммить, пока не попрошу.

Если папок src/_ext* нет и dir уже ext/cfe — напиши «уже мигрировано» и ничего не меняй.
```

## Для разработчиков шаблона

При breaking change для живых проектов:

1. Поднять `version` в `.1c/template-manifest.json` (+ `template.version` в example, `version` в `plugin.json`).
2. Обновить **этот файл** — только дельта «что сделать после sync», без копии схемы из `.1c/README.md`.
3. Краткий пункт в `upgradeNotes` манифеста (для одного вывода `UPGRADE` после sync).
