---
name: 1c-invariants
description: >-
  Жёсткие инварианты любой задачи 1С: SkillHome vs ProjectRoot, не убивать 1cv8,
  load без КБД, query-validate opt-in, новые объекты — пустышка в Конфигураторе.
  Читай сразу, если есть `.1c/`, `src/Configuration.xml`, или речь про 1С /
  dump / ibcmd / bootstrap / implementer / meta-compile / новый справочник.
---

# Инварианты 1С

Plugin-rules с `alwaysApply: true` часто **не** попадают в контекст. Этот skill — канон; `.mdc` тот же текст для workspace/шаблона.

Только если есть `.1c/`, `src/Configuration.xml`, или пользователь явно про 1С/bootstrap. На чужих репо не применяй.

## Пути

**ProjectRoot** = workspace. **SkillHome** = каталог `SKILL.md` (плагин или `.cursor/skills/<name>`).
Скрипты: `-ProjectRoot "<workspace>"`. Skills в проект не копировать.

```powershell
powershell -NoProfile -File "<SkillHome>/scripts/<Script>.ps1" -ProjectRoot "<workspace>"
```

Fallback SkillHome: `<workspace>/.cursor/skills/<name>/` (клон) или `%USERPROFILE%\.cursor\plugins\local\1c-agent-designer\.cursor\skills\<name>\`.

## Процессы

Не убивать пользовательские `1cv8` / Конфигуратор / Предприятие (даже «на всякий случай»).
Запрещены `Get-Process 1cv8 | Stop-Process` и массовый `taskkill`.
При lock — путь ИБ и pid, решение за пользователем.
Точечно можно: orphan `ibcmd` **служебной** `.1c/ib-ext` (не ИБ пользователя).

## Dump / load

Только **основная** конфигурация. Не `update-db-cfg` / `/UpdateDBCfg` / `config apply` на боевую. КБД — вручную.
Инструмент: skill **`1c-dump`** (`tools.preferredDump`: ibcmd | agent). SQL ≠ пользователь 1С — rule `1c-ibcmd-auth`.

## Новые объекты метаданных

На живой конфе (`src/Configuration.xml` из дампа) **не** собирать объект с нуля:
`meta-compile`, `role-compile`, `subsystem-compile`, `cf-init`, `cf-edit add-childObject`.
Они переписывают весь `Configuration.xml` (мобильные флаги, xmlns) → ложные диффы и лишняя реструктуризация.

1. Список пустышек (тип + имя) → пользователь создаёт **пустые** объекты в Конфигураторе.
2. `dump-objects` / `dump-update` (skill `1c-dump`).
3. Агент **только заполняет**: `meta-edit`, формы, модули, СКД. `Configuration.xml` не трогать.

Исключения: пустой проект без дампа (`cf-init` / bootstrap); пользователь явно настоял на `meta-compile` (один раз предупредить про перепись корня).
Детали: skill `1c-metadata-manage`.

## Запросы

`Invoke-1cValidateQuery.ps1` по умолчанию **не** гонять. Вкл. по фразе «проверяй запросы» — skill `1c-query-validate`.

## Справка платформы

Платформенный API — skill **`1c-syntax`** (MCP `bsl-syntax` / bsl-ctx из `shcntx_ru.hbk`). Не HTML-дамп. Нет sqlite → `/1c-syntax-index`, сигнатуры не выдумывать. Не гейт на написание кода.

## Git

Фичи в `feature/…` / `fix/…`, не напрямую в `main`. Процесс: `docs/WORKFLOW.md`.

Канон полей `project.json`: `.1c/README.md`.
