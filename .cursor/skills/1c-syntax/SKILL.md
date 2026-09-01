---
name: 1c-syntax
description: >-
  Справка платформы 1С (синтаксис-помощник) через bsl-ctx MCP: типы, методы,
  свойства, запросы. Use when writing BSL, calling platform API, constructors,
  query language, or when user asks index/обнови справку / syntax-helper.
---

# Справка платформы (bsl-ctx)

Не гейт: без базы можно писать код. **Платформенный API не угадывать.**

Источник: `.hbk` установленной платформы (`shcntx_ru.hbk`, `shlang_*`, `shquery_*`) -> sqlite `bsl-ctx`. HTML-выгрузку не делать.

`SkillHome` = каталог этого SKILL.md. `-ProjectRoot` = workspace.

## Когда

- Пишешь/ревьюишь BSL, конструкторы `Новый`, методы платформы, глобальный контекст.
- Текст запроса (`ВЫБРАТЬ`, виртуальные таблицы).
- Пользователь: «обнови справку», `/1c-syntax-index`, `/1c-syntax-status`.

## MCP (имена тулз как у bsl-ctx)

Сервер `bsl-syntax` (плагин `mcp.json`).

| Тулза | Зачем |
|-------|--------|
| `platform_info` | жива ли база, версия платформы |
| `search` | естественный запрос ("хеш SHA256", "вставить в структуру") |
| `describe` | карточка типа/метода по имени или `ref` |
| `members` | методы/свойства типа |
| `signature` | перегрузки и параметры |
| `relations` | связи типов |

Поток: `search` -> `ref` -> `describe` / `members` / `signature`.

Ответ `code: DB_MISSING` (или MCP не подключён): **не сочинять** редкие сигнатуры. Предложи `/1c-syntax-index`. Очевидное (`Массив.Добавить`) можно из знаний модели, с пометкой что справка не проиндексирована.

Фильтр совместимости: MCP выставляет `BSL_CTX_TARGET_VERSION` из `CompatibilityMode` в `src/Configuration.xml` (не из номера exe).

## Команды на диске

```powershell
powershell -NoProfile -File "<SkillHome>/scripts/Get-1cSyntaxStatus.ps1" -ProjectRoot "<workspace>"
powershell -NoProfile -File "<SkillHome>/scripts/Build-1cSyntaxDb.ps1" -ProjectRoot "<workspace>"
powershell -NoProfile -File "<SkillHome>/scripts/Build-1cSyntaxDb.ps1" -ProjectRoot "<workspace>" -Rebuild
```

Нужны: `uv`/`uvx`, Python >= 3.12 (тянет `uvx`), `platformVersion` в `.1c/project.json`, файл `bin\shcntx_ru.hbk`.

Сборка выставляет UTF-8 и `BSL_CTX_PSEUDO_TYPES` (оверлей + автодописывание имён вроде «Объекты метаданных», на которых 1.4.0 падает). Если `corpus.sqlite` уже есть — повторный index только делает `build`, без повторного разбора `.hbk`.

База: `%LOCALAPPDATA%\bsl-ctx\bsl-context-<platformVersion>.sqlite` (не в git). Одна платформа - одна база на все проекты.

Перепарс только по `/1c-syntax-index`, `-Rebuild` или явной фразе «обнови справку». Не на каждый чат.

`/implementer` тулзы MCP может звать (чтение). Скрипт `Build-1cSyntaxDb.ps1` - оркестратор, не implementer.
