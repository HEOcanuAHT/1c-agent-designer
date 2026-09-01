# Первая выгрузка конфигурации в `src/`

1. Подготовьте локальную ИБ (файловую, серверную или по имени в списке) с нужной версией платформы.
2. Если есть хранилище 1С — обновите конфигурацию ИБ из хранилища до рабочей версии.
3. Закройте обычный Конфигуратор (на файловой ИБ параллельно с AgentMode он мешает).
4. Настройка окружения: skill **`1c-project-bootstrap`** (чеклист: тип ИБ, auth, ibcmd/agent, SQL).  
   Вручную: скопировать example → `project.json` / `project.local.json`, заполнить `infobase`, `tools.preferredDump`, auth.
5. Полная выгрузка — skill **`1c-dump`** (по `tools.preferredDump`, **ibcmd** по умолчанию):

```powershell
# пустой src/: сразу dump-full
# непустой src/ + ibcmd: сначала спроси пользователя, что XML в src/ будет удалён и перезалит из ИБ,
# затем: -WipeOutDir
…\1c-dump\scripts\Invoke-1cDump.ps1 -Action dump-full -ProjectRoot "<этот-репо>" [-WipeOutDir]
```

**ibcmd:** полный `export` требует **пустой** каталог. Внешки и расширения живут в `ext/` и `cfe/` (не в `src/`).  
Непустой `src/`: агент **спрашивает**, затем `-WipeOutDir` — очистка `src/` и export сразу туда (без staging-копии). Хвосты старого layout (`README.md`, `_extDataProcessors`, `_extensions` внутри `src/`) паркуются и возвращаются.  
Инкремент (`dump-update`): `--sync` сразу в `src/`. Park только если в `src/` ещё лежат preserve-хвосты.

На файловой ИБ перед dump закрой Конфигуратор. Для ibcmd на client-server в `infobase` нужен блок `dbms`.

6. Убедитесь, что есть `src/Configuration.xml` и `src/ConfigDumpInfo.xml`.
7. Опционально служебная ИБ `.1c/ib-ext` (EPF/CFE, не dump). Skill **`1c-dump`** указывает CLI; путь — `1c-runtime`:

```powershell
powershell -NoProfile -File "…\1c-runtime\scripts\Invoke-1cServiceIb.ps1" `
  -Action ensure -ProjectRoot "<этот-репо>"
```

Save `.cf` с боевой → load, **без apply**. Не `Ensure-ServiceIb` через `-Command` (Cursor раскрывает `$`). Не `Invoke-1cValidateQuery.ps1 -Action ensure` (там apply). Пересборка: `-Force` или `-RefreshServiceIb`.
8. Коммит в `main` или ветку `sync/…` → Merge Request.
