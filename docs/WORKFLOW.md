# Workflow разработки конфигурации 1С (шаблон)

## Роли Git и хранилища

1. **Хранилище 1С** (если используется) — источник поставки в продуктивный контур.
2. **Git (`main`)** — исходники для разработки и MR, не автоматическая поставка в хранилище.
3. Возврат в хранилище — **вручную** интегратором после merge (или по вашему GitSync-процессу).

## Ветки

- Фичи/фиксы: `feature/…` или `fix/…` от актуального `main`.
- Не коммитить доработки напрямую в `main` (кроме согласованных sync-коммитов выгрузки).

## Dump / load

По `tools.preferredDump` в `.1c/project.json` (канон полей: [`.1c/README.md`](../.1c/README.md)):

| Значение | Skill |
|----------|--------|
| `ibcmd` (предпочтительно) | фасад **`1c-dump`** → `1c-ibcmd-pack` |
| `agent` | фасад **`1c-dump`** → `1c-designer-agent` |

Агенту: `Invoke-1cDump.ps1` (skill `1c-dump`). Детали CLI — в ibcmd-pack / designer-agent.

- `dump-full` / `dump-update` → XML в `src/`.
- Откат файлов объекта к ИБ без git: `dump-objects`. `dump-update` правки на диске не видит.
- Правки в git → `load-changed` (или list-file) → **только основная конфигурация**.
- **Не** вызывать `update-db-cfg` / `/UpdateDBCfg` из автоматизации.
- Принятие в конфигурацию БД — вручную в Конфигураторе.
- Перед dump/load на файловой ИБ закройте обычный Конфигуратор (агент `1cv8` не убивает).
- **Новый объект метаданных:** пустышку создаёт разработчик в Конфигураторе, затем dump в `src/`. Агент заполняет XML, не собирает объект через `meta-compile` (skill `1c-invariants`).

## Merge Request

Шаблон: `.gitlab/merge_request_templates/Default.md`.

## Код

**Оркестратор** (основной агент): декомпозиция, scaffold/pack/dump, dump/load конфы — rule `1c-orchestrator`.  
**Субагент `/implementer`**: только правки файлов (BSL, формы, XML) по `coding-standards` → нужные `std-*`, `tech-decisions` (`docs/TECH_DECISIONS.md`), skill `1c-syntax` для платформенного API. Без Конфигуратора и скриптов ИБ.

См. `.cursor/agents/implementer.md`.
