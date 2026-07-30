# Workflow разработки конфигурации 1С (шаблон)

## Роли Git и хранилища

1. **Хранилище 1С** (если используется) — источник поставки в продуктивный контур.
2. **Git (`main`)** — исходники для разработки и MR, не автоматическая поставка в хранилище.
3. Возврат в хранилище — **вручную** интегратором после merge (или по вашему GitSync-процессу).

## Ветки

- Фичи/фиксы: `feature/…` или `fix/…` от актуального `main`.
- Не коммитить доработки напрямую в `main` (кроме согласованных sync-коммитов выгрузки).

## Dump / load (Designer Agent)

- `dump-full` / `dump-update` → XML в `src/`.
- Правки в git → `load-changed` (или `-ListFile`) → **только основная конфигурация**.
- **Не** вызывать `update-db-cfg` / `/UpdateDBCfg` из автоматизации.
- Принятие в конфигурацию БД — вручную в Конфигураторе.
- Перед dump/load на файловой ИБ закройте обычный Конфигуратор.

Скрипты: `.cursor/skills/1c-designer-agent/`.

## Merge Request

Шаблон: `.gitlab/merge_request_templates/Default.md`.

## Код

**Оркестратор** (основной агент): декомпозиция, scaffold/pack/dump, dump/load конфы — rule `1c-orchestrator`.  
**Субагент `/implementer`**: только правки файлов (BSL, формы, XML) по `coding-standards` → нужные `std-*`, `tech-decisions` (`docs/TECH_DECISIONS.md`). Без Конфигуратора и скриптов ИБ.

См. `.cursor/agents/implementer.md`.
