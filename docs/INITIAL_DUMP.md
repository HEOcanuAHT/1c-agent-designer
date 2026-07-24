# Первая выгрузка конфигурации в `src/`

1. Подготовьте локальную ИБ (файловую или серверную) с нужной версией платформы.
2. Если есть хранилище 1С — обновите конфигурацию ИБ из хранилища до рабочей версии.
3. Закройте обычный Конфигуратор (на файловой ИБ параллельно с AgentMode он мешает).
4. Заполните `.1c/project.json` (из `project.json.example`) и `.1c/project.local.json` (auth).
5. Полная выгрузка:

```powershell
…\1c-project-template\.cursor\skills\1c-designer-agent\scripts\Invoke-1cDesignerAgent.ps1 `
  -Action dump-full -ProjectRoot "<этот-репо>"
```

Либо batch `/DumpConfigToFiles` в каталог `src/`.

6. Убедитесь, что есть `src/Configuration.xml` и `src/ConfigDumpInfo.xml`.
7. Коммит в `main` или ветку `sync/…` → Merge Request.
