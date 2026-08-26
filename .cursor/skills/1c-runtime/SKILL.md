---
name: 1c-runtime
description: >-
  Shared PowerShell runtime for 1C skills: project.json merge, ibcmd connection,
  service IB (.1c/ib-ext). Not for dump/pack by itself - other skills dotsource
  these scripts. Use when editing Common-*.ps1 or tracing SkillHome runtime paths.
disable-model-invocation: true
---

# 1c-runtime — общий runtime

Единое место для скриптов, которые раньше лежали в `1c-ibcmd-pack/scripts/`:

| Файл | Назначение |
|------|------------|
| `scripts/Common-Project.ps1` | merge `project.json`, пути 1cv8/ibcmd, designer auth / CredMgr |
| `scripts/Common-IbcmdConnection.ps1` | file/DBMS + пользователь 1С (`Get-ConnectionArgs`) |
| `scripts/Common-ServiceIb.ps1` | служебная `.1c/ib-ext` (EPF/CFE/query-validate) |

Потребители: `1c-ibcmd-pack`, `1c-designer-agent`, `1c-external-epf`, `1c-external-cfe`, `1c-query-validate`, `1c-template-sync`.

`SkillHome` = каталог этого SKILL.md. Не копировать в другие skills — dotsource отсюда.

В `1c-ibcmd-pack/scripts/` остались **stubs** на эти файлы (compat после частичного sync).

Канон полей ИБ: `.1c/README.md`. SQL ≠ CredMgr 1С: rule `1c-ibcmd-auth`.
