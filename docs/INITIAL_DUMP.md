# Первая выгрузка конфигурации в `src/`

1. Подготовьте локальную ИБ (файловую, серверную или по имени в списке) с нужной версией платформы.
2. Если есть хранилище 1С — обновите конфигурацию ИБ из хранилища до рабочей версии.
3. Закройте обычный Конфигуратор (на файловой ИБ параллельно с AgentMode он мешает).
4. Настройка окружения: попросите агента выполнить skill **`1c-project-bootstrap`**  
   (или вручную скопируйте `.1c/project.json.example` → `project.json`, `project.local.json.example` → `project.local.json` и заполните `infobase` + auth).
5. Полная выгрузка:

```powershell
…\1c-project-template\.cursor\skills\1c-designer-agent\scripts\Invoke-1cDesignerAgent.ps1 `
  -Action dump-full -ProjectRoot "<этот-репо>"
```

Либо batch `/DumpConfigToFiles` в каталог `src/`.

6. Убедитесь, что есть `src/Configuration.xml` и `src/ConfigDumpInfo.xml`.
7. Коммит в `main` или ветку `sync/…` → Merge Request.
