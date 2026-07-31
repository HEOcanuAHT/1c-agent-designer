# Расширения конфигурации проекта

Иерархическая XML-выгрузка **расширений** (`.cfe`), связанных с этой конфигурацией.

- Не часть основной выгрузки — dump/load конфы их не трогают (preserve + фильтр).
- Сборка/разбор: skill `1c-external-cfe` (`Invoke-1cExternalCfe.ps1`); служебная ИБ `.1c/ib-ext` общая с внешками (import конфы без КБД).
- Готовые `.cfe` → `artifacts/cfe/` (не коммитить).

Структура одного расширения: каталог `<Name>/` с `Configuration.xml` внутри.

### Служебная проверка запросов

Готовый пример (не копируется sync’ом из `src/`):  
`.cursor/skills/1c-external-cfe/examples/QueryValidate` — HTTP-валидация запросов на `.1c/ib-ext`.  
Скрипт: `Invoke-1cValidateQuery.ps1`. При желании скопировать каталог сюда как `QueryValidate/`.
