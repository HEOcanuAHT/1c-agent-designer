#Область Шаблон проекта конфигурации 1С

Сюда помещается **иерархическая выгрузка** конфигурации (`DumpConfigToFiles` / AgentMode dump).

Пока каталог пуст (кроме этого файла и `src/_extDataProcessors/`):

1. Обновите локальную ИБ из хранилища (если используется).
2. Выполните полную выгрузку в этот каталог `src/` (см. [docs/INITIAL_DUMP.md](../docs/INITIAL_DUMP.md)).  
   При **ibcmd** `README.md` и `_extDataProcessors/` убирать не нужно — скрипт сам сделает staging.
3. После выгрузки здесь появятся `Configuration.xml`, каталоги объектов и `ConfigDumpInfo.xml`.
4. Закоммитьте в `main` или ветку `sync/…` → MR.

Отдельно: `src/_extDataProcessors/` — XML внешних обработок (не часть выгрузки конфы). См. README в этой папке и skill `1c-external-epf`.

#КонецОбласти
