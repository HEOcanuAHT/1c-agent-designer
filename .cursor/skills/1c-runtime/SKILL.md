---
name: 1c-runtime
description: >-
  Shared PowerShell runtime for 1C skills: project.json merge, ibcmd connection,
  service IB (.1c/ib-ext). Agent CLI is Invoke-1cServiceIb.ps1 only; Common-*.ps1
  are dotsourced by other skills. Use when editing Common-*.ps1 or tracing
  SkillHome runtime paths.
disable-model-invocation: true
---

# 1c-runtime — общий runtime

Единое место для скриптов, которые раньше лежали в `1c-ibcmd-pack/scripts/`:

| Файл | Назначение |
|------|------------|
| `scripts/Invoke-1cServiceIb.ps1` | **агентский CLI** служебной `.1c/ib-ext` (`ensure` / `status`) |
| `scripts/Common-Project.ps1` | merge `project.json`, пути 1cv8/ibcmd, designer auth / CredMgr |
| `scripts/Common-IbcmdConnection.ps1` | file/DBMS + пользователь 1С (`Get-ConnectionArgs`) |
| `scripts/Common-ServiceIb.ps1` | `Ensure-ServiceIb` (не вызывать напрямую) |

«Собери служебную ИБ» / после `dump-full` — **только** `-File`:

```powershell
powershell -NoProfile -File "<SkillHome>/scripts/Invoke-1cServiceIb.ps1" `
  -Action ensure -ProjectRoot "<workspace>"
```

Дефолт как у EPF: `config save` с боевой → `config load` в `.1c/ib-ext`, **без apply**. XML import — fallback. `-Force` / `-RefreshServiceIb` — пересобрать. `-AllowApply` — только явно (query-validate, другой штамп).

Не `Ensure-ServiceIb` через `powershell -Command` (Cursor раскрывает `$`). Не `Invoke-1cValidateQuery.ps1 -Action ensure` вместо этого CLI: там всегда apply.

Потребители: `1c-ibcmd-pack`, `1c-designer-agent`, `1c-external-epf`, `1c-external-cfe`, `1c-query-validate`, `1c-template-sync`.

`SkillHome` = каталог этого SKILL.md. Не копировать в другие skills — dotsource отсюда.

В `1c-ibcmd-pack/scripts/` остались **stubs** на эти файлы (compat после частичного sync).

Канон полей ИБ: `.1c/README.md`. SQL ≠ CredMgr 1С: rule `1c-ibcmd-auth`.
