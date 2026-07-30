#Область Шаблон проекта конфигурации 1С

Сюда помещается **иерархическая выгрузка** конфигурации (`DumpConfigToFiles` / AgentMode dump).

Пока каталог пуст (кроме этого файла, `src/_extDataProcessors/` и `src/_extensions/`):

1. Обновите локальную ИБ из хранилища (если используется).
2. Выполните полную выгрузку в этот каталог `src/` (см. [docs/INITIAL_DUMP.md](../docs/INITIAL_DUMP.md)).  
   При **ibcmd** `README.md`, `_extDataProcessors/` и `_extensions/` убирать не нужно — скрипт сам сделает staging.
3. После выгрузки здесь появятся `Configuration.xml`, каталоги объектов и `ConfigDumpInfo.xml`.
4. Закоммитьте в `main` или ветку `sync/…` → MR.

Отдельно:
- `src/_extDataProcessors/` — XML внешних обработок (skill `1c-external-epf`).
- `src/_extensions/` — XML расширений `.cfe` (skill `1c-external-cfe`).

#КонецОбласти
