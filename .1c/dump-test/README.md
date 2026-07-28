# dump-test — локальные сравнения выгрузок

Содержимое `agent/` и `ibcmd/` **не в git** (см. `.gitignore`) и в `neverTouch` template-sync.

| Папка | Транспорт |
|-------|-----------|
| `agent/` | designer-agent (batch / AgentMode) |
| `ibcmd/` | `Invoke-1cIbcmdDump.ps1` → `ibcmd infobase config export` |

Сюда — только эксперименты. Рабочая выгрузка проекта — `src/`.

См. `.1c/README.md`: один `infobase`, инструменты берут свои поля.
