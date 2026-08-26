---
name: 1c-dump
description: >-
  Фасад dump/load XML основной конфигурации: читает tools.preferredDump
  (ibcmd|agent) и вызывает Invoke-1cIbcmdDump или Invoke-1cDesignerAgent.
  Use when dump, dump-full, dump-update, load-changed, выгрузка XML, загрузка XML.
---

# 1c-dump — фасад dump/load

Один вход для агента. Детали CLI — в `1c-ibcmd-pack` / `1c-designer-agent`.

## Выбор инструмента

| `tools.preferredDump` | Скрипт |
|----------------------|--------|
| `ibcmd` (дефолт) | `1c-ibcmd-pack` → `Invoke-1cIbcmdDump.ps1` |
| `agent` | `1c-designer-agent` → `Invoke-1cDesignerAgent.ps1` |

Переопределение: `-Tool ibcmd|agent`. Канон полей: `.1c/README.md`.

## Команды

`SkillHome` = каталог этого SKILL.md. `-ProjectRoot` = workspace.

```powershell
powershell -NoProfile -File "<SkillHome>/scripts/Invoke-1cDump.ps1" `
  -Action dump-full -ProjectRoot "<workspace>"
# непустой src/ + ibcmd: согласие пользователя, затем -WipeOutDir
```

| Action | ibcmd | agent |
|--------|-------|-------|
| `dump-full` | export | dump-full |
| `dump-update` | export --sync | dump-update |
| `dump-objects` | invalidate + sync | dump-objects |
| `load-changed` / `load-files` | import files | load-changed |
| `ping` | export info | ping |

Общие: `-ListFile`, `-Objects`, `-BaseRef`/`-HeadRef` (agent load).  
Только ibcmd: `-WipeOutDir`, `-OutDir`, `-NoStaging`.

## Жёсткие правила

1. Только **основная** конфигурация; без `update-db-cfg` / apply на боевую.
2. `dump-full -WipeOutDir` — только после явного «да» в чате.
3. Не собирать `ibcmd` / Designer CLI вручную — этот фасад или skills ниже.
4. SQL ≠ CredMgr 1С — rule `1c-ibcmd-auth`.

Pack `.cf` — не здесь: `1c-ibcmd-pack` / `Invoke-1cIbcmdPack.ps1`.
