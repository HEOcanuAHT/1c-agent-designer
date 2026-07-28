# dump-test — локальные сравнения выгрузок

Содержимое `agent/` и `ibcmd/` **не в git** (см. `.gitignore`) и в `neverTouch` template-sync.

| Папка | Транспорт |
|-------|-----------|
| `agent/` | designer-agent (batch / AgentMode) |
| `ibcmd/` | `Invoke-1cIbcmdDump.ps1` → `ibcmd infobase config export` |

Сюда — только эксперименты. Рабочая выгрузка проекта — `src/`.

См. skill `1c-ibcmd-pack` (секция dump): всегда `infobase config`, для SQL — `infobase.dbms`, Windows auth без `--db-user`.
