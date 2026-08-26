# Architecture patterns (companion to std-architecture router)

Источник: адаптировано из [comol/ai_rules_1c](https://github.com/comol/ai_rules_1c).  
Нормы запросов / клиент-сервер / запахи — в `std-queries`, `std-client-server`, `std-anti-patterns`, не здесь.

## Code placement

- Business logic — **in common modules**, not in form modules.
- БСП suffixes: no suffix — server-only; `Клиент`; `КлиентСервер`; `ВызовСервера`; `Глобальный`; `ПовтИсп`; `Переопределяемый`.
- Server object modules — `#Если Сервер Или ТолстыйКлиентОбычноеПриложение Или ВнешнееСоединение Тогда`.

## Result-Structure

```bsl
Результат = Новый Структура;
Результат.Вставить("ПроверкаПройдена", ПроверкаПройдена);
Результат.Вставить("ТекстОшибки", ТекстОшибки);
Возврат Результат;
```

## Early Return

```bsl
Если Отказ Тогда
	Возврат;
КонецЕсли;
```

## Value Table Search

```bsl
СтруктураОтбора = Новый Структура("ВидСпецодежды", ТекущаяСтрока.ВидСпецодежды);
НайденныеСтроки = ТаблицаДанных.НайтиСтроки(СтруктураОтбора);
```

## Event subscriptions

Prefer over editing typical modules. Handlers — common module `{PREFIX}EventSubscriptions`.

## New metadata placement

`{NEW_OBJECTS_IN}` from project policy / `.1c/project.json` (if used):

| Value | Behavior |
|-------|----------|
| `main_configuration` (default) | New objects in main; extension — interception only |
| `extension` | New objects may live in extension |

Typical roles — do not modify; add new with `{PREFIX}`.

## Background jobs

Ops > ~10 s — background job + progress; do not block UI.

## Defensive typing / Structure keys

```bsl
Если ТипЗнч(ДокументыИлиСсылка) <> Тип("Массив") Тогда
	Документы = Новый Массив;
	Документы.Добавить(ДокументыИлиСсылка);
Иначе
	Документы = ДокументыИлиСсылка;
КонецЕсли;

Если ПараметрыОтчета.Свойство("ДатаНачала", ДатаНачала) Тогда
	// ...
КонецЕсли;
```

Normalize collections via `ОбщегоНазначенияКлиентСервер.ЗначениеВМассиве()` when useful.

## Extensions (summary)

Priority: subscriptions → extensions → typical edit.  
Directives / `ПродолжитьВызов` — `std-extension-patterns`.  
Forms in extensions: minimize visual edits; prefer code.

## Data access — reference attributes

Dot-notation on refs (`Контрагент.ИНН`) loads the object. **Project default: hard ban** outside trivial one-off handlers (stricter than ITS). Prefer:

| Method | Purpose |
|--------|---------|
| `ОбщегоНазначения.ЗначениеРеквизитаОбъекта` | One attr, one ref |
| `ОбщегоНазначения.ЗначенияРеквизитовОбъекта` | Many attrs, one ref |
| `ОбщегоНазначения.ЗначениеРеквизитаОбъектов` | One attr, many refs |
| `ОбщегоНазначения.ЗначенияРеквизитовОбъектов` | Many attrs, many refs |

Cache repeats in `Соответствие`. Catalog entry: `std-anti-patterns`.

## Error handling / security (headlines)

- Empty `Попытка / Исключение` — **запрещено**; логируй или пробрасывай. Положительный companion — `std-logging`.
- `Выполнить()` / `Вычислить()` — только при крайней необходимости (`std-security`).
- Hardcoded credentials — **запрещены** (`std-security`).
- Modal sync dialogs — **запрещены**; async — `1c-forms` → `async-methods.md`.
- Server dates — `ТекущаяДатаСеанса()` (`std-platform-solutions`).
- COM / Excel.Application — не использовать без явного ТЗ (`std-platform-solutions`).

Full catalog — `std-anti-patterns`. Platform pitfalls — `std-platform-solutions`. Locks — `std-transactions-locks`.

- Mass work on server; no client round-trips in loops; `&НаСервереБезКонтекста` when form context unused (`std-client-server`).
- No queries in loops — batch + VT (`std-queries` / `std-query-optimization`).
- Privileged mode — pair `Истина`/`Ложь`.
- Short transactions; no UI / long / external calls inside (`std-transactions-locks`).

## Code smells (index)

| Smell | Fix direction |
|-------|----------------|
| Data Clumps | Structure + constructor |
| Primitive Obsession | Enum / CatalogRef / DefinedType |
| Divergent Change / Shotgun Surgery | Split or consolidate modules (SRP) |
| Feature Envy | Move to object's common module |
| Variable Reuse | Separate variables |

Severity examples — `std-anti-patterns`.
