---
name: coding-standards
description: >-
  Роутер стандартов разработки 1С (ITS v8std). Use at the start of implementer
  or reviewer work to decide which domain std-* skills to load for the current change.
disable-model-invocation: true
---

# Стандарты 1С — роутер

## Источник

Синхронизация с ИТС: сессия пользователя на [v8std](https://its.1c.ru/db/v8std#browse:13:-1).  
В skills — выжимки must/checklist с номерами `#std…` и ссылками на статьи; не полный зеркальный дамп базы ИТС.

## Как подгружать (lazy)

1. Всегда применяй этот skill (`coding-standards`).
2. Дальше применяй **только** доменные skills, которые реально касаются текущего diff/задачи.
3. Не тяни «на всякий случай» запросы/обмен/права, если в изменениях этого нет.

| Если в задаче есть… | Skill |
|---------------------|--------|
| BSL-модули, именование, области, общие модули | `std-code-style` (+ `docs/practices.md` при глубоком стиле) |
| Регионы модулей (каркас) | `std-module-structure` |
| Клиент/сервер, вызовы сервера, трафик | `std-client-server` |
| Управляемые формы / `Form.xml` / async | `1c-forms` (+ `1c-metadata-manage` form-*) |
| Текст запроса, `Запрос`, СКД-запросы (оформление) | `std-queries` (+ `docs/query-writing.md`) |
| Runtime-проверка языка запросов (opt-in) | `1c-query-validate` (оркестратор, не implementer) |
| Производительность запросов, индексы, ВТ | `std-query-optimization` (+ `docs/practices.md`) |
| Запись данных, транзакции, блокировки | `std-transactions-locks` (+ `docs/practices.md`) |
| Роли, RLS, `ПравоДоступа`, привилегированный режим | `std-access-rights` |
| План обмена, `ОбменДанными.Загрузка`, EnterpriseData | `std-data-exchange` |
| API с `Вызов сервера`, пароли, Выполнить/Вычислить | `std-security` |
| Новые/изменённые объекты метаданных, подсистемы | `std-metadata` + `1c-metadata-manage` |
| Ручная правка XML метаданных / типичные факапы | `std-metadata-xml` |
| Расширения CFE (перехватчики BSL) | `std-extension-patterns` (+ pack: `1c-external-cfe`) |
| СКД / отчёты (проектирование) | `std-dcs-design` (+ `1c-metadata-manage` skd-*) |
| Регистры (проектирование) | `std-registers-design` |
| Антипаттерны / ревью perf | `std-anti-patterns` |
| Ловушки платформы | `std-platform-solutions` |
| Архитектура (размещение кода/объектов) | `std-architecture` (+ `docs/patterns.md`) |
| Журнал регистрации | `std-logging` |
| HTTP/REST/очереди | `std-integrations` |

Типичные комбинации:
- правка общего модуля без запросов → `std-code-style` (+ `std-client-server`, если есть клиентский API)
- новая/правка формы → `1c-forms` + `1c-metadata-manage` (form-*)
- новый объект метаданных → `std-metadata` + `1c-metadata-manage` (meta-*) + `std-metadata-xml`
- код в расширении → `std-extension-patterns` (+ `1c-external-cfe` для pack)
- новый запрос в отчёте → `std-queries` + `std-query-optimization` (+ `std-dcs-design` при СКД)
- проведение документа → `std-transactions-locks` (+ запросы при наличии)
- обработчик `ПередЗаписью` в объекте обмена → `std-data-exchange`

## Карта разделов ИТС (верхний уровень)

| Раздел ИТС | Skill |
|------------|--------|
| [Соглашения при написании кода](https://its.1c.ru/db/v8std/browse/13/-1/31) | `std-code-style` |
| [Организация работы конфигурации](https://its.1c.ru/db/v8std/browse/13/-1/1/2) / метаданные | `std-metadata` |
| [Клиент-серверное взаимодействие](https://its.1c.ru/db/v8std/browse/13/-1/35) | `std-client-server` |
| [Работа с запросами](https://its.1c.ru/db/v8std/browse/13/-1/26/27) | `std-queries` |
| [Оптимизация запросов](https://its.1c.ru/db/v8std/browse/13/-1/26/28) | `std-query-optimization` |
| [Обработка и модификация данных](https://its.1c.ru/db/v8std/browse/13/-1/26/29) | `std-transactions-locks` |
| [Настройка прав доступа](https://its.1c.ru/db/v8std/browse/13/-1/37) | `std-access-rights` |
| [Общие вопросы безопасности](https://its.1c.ru/db/v8std/browse/13/-1/36) | `std-security` |
| [Реализация обмена данными](https://its.1c.ru/db/v8std/browse/13/-1/38) | `std-data-exchange` |

## Минимальный чеклист ревью (без доменных skills)

Даже без узких skills отметь:
- [ ] Изменения соответствуют плану / не раздут scope
- [ ] Нет очевидной тяжёлой логики на клиенте
- [ ] Нет запросов в цикле «на глаз»
- [ ] Есть обработка `ОбменДанными.Загрузка` в обработчиках записи, если правили события объекта
- [ ] Секреты/пароли не в коде

Затем догрузи нужные `std-*` и углуби проверку.
