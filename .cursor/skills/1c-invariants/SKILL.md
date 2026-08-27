---
name: 1c-invariants
description: >-
  Жёсткие инварианты любой задачи 1С: SkillHome vs ProjectRoot, не убивать 1cv8,
  load без КБД, query-validate opt-in. Читай сразу, если есть `.1c/`,
  `src/Configuration.xml`, или речь про 1С / dump / ibcmd / bootstrap / implementer.
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

## Запросы

`Invoke-1cValidateQuery.ps1` по умолчанию **не** гонять. Вкл. по фразе «проверяй запросы» — skill `1c-query-validate`.

## Git

Фичи в `feature/…` / `fix/…`, не напрямую в `main`. Процесс: `docs/WORKFLOW.md`.

Канон полей `project.json`: `.1c/README.md`.
