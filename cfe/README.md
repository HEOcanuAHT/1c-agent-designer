# Расширения конфигурации проекта

Иерархическая XML-выгрузка **расширений** (`.cfe`), связанных с этой конфигурацией.

- Не часть основной выгрузки — dump/load `src/` их не трогает.
- Сборка/разбор: skill `1c-external-cfe` (`Invoke-1cExternalCfe.ps1`); служебная ИБ `.1c/ib-ext` общая с внешками (import конфы без КБД).
- Готовые `.cfe` → `artifacts/cfe/` (не коммитить).

Структура одного расширения: каталог `<Name>/` с `Configuration.xml` внутри.

Путь задаётся `cfe.dir` (дефолт `cfe`).

### Служебная проверка запросов

`Invoke-1cValidateQuery.ps1` — COM (`QuerySchema`) на `.1c/ib-ext`, без HTTP/расширения.  
Обычный путь агента: `-ReuseOnly -BatchDir .1c/qv-batch` (ensure только при `NEED_ENSURE`).
