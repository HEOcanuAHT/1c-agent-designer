---
name: std-architecture
description: >-
  Architecture router for non-trivial 1C design: where logic lives, extensions
  vs main, data-access defaults. Defers to ITS std-* and anti-patterns for
  details. Use when designing modules, placement, or cross-cutting structure.
disable-model-invocation: true
---

# std-architecture — роутер

Не дублируй ITS и каталог запахов. Грузи **этот** skill для размещения кода / объектов; дальше — только нужный домен.

| Тема | Куда |
|------|------|
| Клиент/сервер, трафик, `&НаСервереБезКонтекста` | `std-client-server` |
| Оформление запросов | `std-queries` |
| Скорость запросов, ВТ, индексы | `std-query-optimization` |
| Запахи / severity / before-after | `std-anti-patterns` |
| Ловушки платформы | `std-platform-solutions` |
| Расширения (перехватчики BSL) | `std-extension-patterns` |
| Async / модальность в формах | `1c-forms` → `async-methods.md` |
| Безопасность API | `std-security` |
| Журнал регистрации | `std-logging` |
| Транзакции / блокировки | `std-transactions-locks` |
| Паттерны Result-Structure / Early Return / NEW_OBJECTS_IN / BSP-реквизиты | [docs/patterns.md](docs/patterns.md) |

Кратко здесь:

1. Бизнес-логика — в **общих модулях**, не в модулях форм.
2. Приоритет доработки: подписки → расширения → правка типового.
3. Новые объекты — по политике проекта (часто `main_configuration`); детали — `docs/patterns.md`.
4. Запросы в цикле и точечная нотация ссылок — запрет/каталог в `std-anti-patterns`; норма — `std-queries` / BSP `ЗначениеРеквизита*`.
