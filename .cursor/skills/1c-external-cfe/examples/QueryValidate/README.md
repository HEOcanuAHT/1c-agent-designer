# QueryValidate — служебное расширение проверки запросов

HTTP-сервис в расширении для валидации языка запросов 1С **без выполнения**
(как `validatequery` из comol/mcp_designer_tools, плюс `СхемаЗапроса`).

## Зачем

Агент пишет запрос → вызываем проверку против метаданных служебной ИБ `.1c/ib-ext`
(туда уже импортирована основная конфа проекта).

## Endpoint

| Method | URL | Body |
|--------|-----|------|
| `GET` | `/hs/qv/health` | — |
| `POST` | `/hs/qv/validate` | JSON `{"query":"ВЫБРАТЬ ..."}` или raw text |

Ответ:

```json
{"ok":true,"valid":true,"error":""}
{"ok":true,"valid":false,"error":"...текст ошибки платформы..."}
```

## Вызов из PowerShell

```powershell
# Подготовить ИБ + расширение + HTTP (/HTTPPort)
powershell -NoProfile -File .cursor/skills/1c-external-cfe/scripts/Invoke-1cValidateQuery.ps1 -Action ensure

# Проверить запрос
powershell -NoProfile -File .cursor/skills/1c-external-cfe/scripts/Invoke-1cValidateQuery.ps1 `
  -QueryText "ВЫБРАТЬ 1"

# Остановить слушатель
powershell -NoProfile -File .cursor/skills/1c-external-cfe/scripts/Invoke-1cValidateQuery.ps1 -Action stop
```

Порт по умолчанию: `18088` (или `queryValidate.httpPort` в `project.json`).

## Поддерживаемый сценарий

**Windows + платформа с Конфигуратором** (`1cv8.exe`: DESIGNER и толстый ENTERPRISE в одном bin).  
HTTP без публикации: `1cv8 ENTERPRISE /F .1c\ib-ext /HTTPPort <port>` — процесс предприятия держит `/hs/qv/...`, пока не `-Action stop`.

Вне scope: Linux/macOS, Apache/IIS-публикация служебной ИБ, тонкий клиент, COM/EPF-обходы.

## Важно

1. На служебной ИБ скрипт делает **`config apply`** (основная + расширение) — только `.1c/ib-ext`, не боевая ИБ.
2. Перед import нужен dump основной конфы в `src/` (метаданные для проверки).
3. `Languages/*.xml`: `ExtendedConfigurationObject` подставляется из базовой конфы при ensure/validate.
4. Опционально скопировать каталог в `src/_extensions/QueryValidate` — скрипт сначала ищет там.

## Режим агента

По умолчанию агент **не** валидирует. Фраза «проверяй запросы» → файл `.1c/query-validate.mode` = `on` (gitignore).  
«не проверяй запросы» → `off`. Rule: `1c-query-validate`.

## Состав

- `Configuration.xml` — AddOn, префикс `Qv_`
- `HTTPServices/Qv_QueryValidate` — RootURL `qv`
- Модуль: `СхемаЗапроса` + `Запрос.НайтиПараметры()`
