---
name: 1c-dump
description: >-
  Фасад dump/load XML основной конфигурации: читает tools.preferredDump
  (ibcmd|agent) и вызывает Invoke-1cIbcmdDump или Invoke-1cDesignerAgent.
  Use when dump, dump-full, dump-update, load-changed, выгрузка XML, загрузка XML.
---

# 1c-dump — фасад dump/load

Сначала skill **`1c-invariants`**, если ещё не в контексте.

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

## Ожидание Shell (агент)

Ждёт не ibcmd, а обвязка Shell. Скрипт сам пишет `OK action=…`, `ELAPSED_SEC=…` и строку `RESULT={…}` — этого достаточно.

| Action (ibcmd, типичная ИБ) | Ожидание | `block_until_ms` |
|-----------------------------|----------|------------------|
| `dump-update` / `dump-objects` / `load-files` / `ping` | 5–15 с | **30000** (до 45000) |
| `dump-full` | 20–40 с (файл ~10–20 с) | **60000** |

**Как вызывать**

1. Один `Shell` с `block_until_ms` из таблицы — дождаться завершения **в том же вызове**.
2. **Не** уводить в фон (`block_until_ms: 0`) и **не** ставить `AwaitShell` на 90 с для инкремента/короткого dump: в UI «ждём полторы минуты», даже если процесс уже мёртв.
3. Фон + `AwaitShell` — только если реально минуты (огромный full dump / зависание по логу).
4. **Не** ставить `notify_on_output`, если агент сам ждёт и ответит по выходу скрипта.
5. Успех: ненулевой exit при ошибке; в stdout — `OK action=<Action>` / `RESULT={"status":"ok",…}`.

## Жёсткие правила

1. Только **основная** конфигурация; без `update-db-cfg` / apply на боевую.
2. `dump-full -WipeOutDir` — только после явного «да» в чате.
3. Не собирать `ibcmd` / Designer CLI вручную — этот фасад или skills ниже.
4. SQL ≠ CredMgr 1С — rule `1c-ibcmd-auth`.
5. Не `AwaitShell` 90 с на 5–15-секундный `dump-update` — см. «Ожидание Shell».

Pack `.cf` — не здесь: `1c-ibcmd-pack` / `Invoke-1cIbcmdPack.ps1`.
