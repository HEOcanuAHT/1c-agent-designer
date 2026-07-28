# Первая выгрузка конфигурации в `src/`

1. Подготовьте локальную ИБ (файловую, серверную или по имени в списке) с нужной версией платформы.
2. Если есть хранилище 1С — обновите конфигурацию ИБ из хранилища до рабочей версии.
3. Закройте обычный Конфигуратор (на файловой ИБ параллельно с AgentMode он мешает).
4. Настройка окружения: skill **`1c-project-bootstrap`** (чеклист: тип ИБ, auth, ibcmd/agent, SQL).  
   Вручную: скопировать example → `project.json` / `project.local.json`, заполнить `infobase`, `tools.preferredDump`, auth.
5. Полная выгрузка — по `tools.preferredDump` (**ibcmd** по умолчанию):

```powershell
# предпочтительно (README и src/_extDataProcessors/ можно не убирать — скрипт сам сделает staging):
…\1c-ibcmd-pack\scripts\Invoke-1cIbcmdDump.ps1 -Action dump-full -ProjectRoot "<этот-репо>"

# fallback (designer-agent — дампит прямо в src/, staging не нужен):
…\1c-designer-agent\scripts\Invoke-1cDesignerAgent.ps1 -Action dump-full -ProjectRoot "<этот-репо>"
```

**ibcmd и непустой `src/`:** полный `export` требует пустой каталог. Скрипт выгружает во временный `.1c/ibcmd-dump-staging/` и мержит XML в `src/`, сохраняя `README.md` и `_extDataProcessors/`. Инкремент (`dump-update`) — аналогично, если в `src/` есть эти папки.

На файловой ИБ перед dump закрой Конфигуратор. Для ibcmd на client-server в `infobase` нужен блок `dbms`.

6. Убедитесь, что есть `src/Configuration.xml` и `src/ConfigDumpInfo.xml`.
7. Коммит в `main` или ветку `sync/…` → Merge Request.
