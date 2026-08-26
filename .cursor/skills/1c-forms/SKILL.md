---
name: 1c-forms
description: >-
  Managed forms router: Form.xml layout, form module, events, async, reserved names.
  Use when creating or editing managed forms, form modules, or async client handlers.
disable-model-invocation: true
---

# 1c-forms — управляемые формы

Источник: адаптировано из [comol/ai_rules_1c](https://github.com/comol/ai_rules_1c) (без MCP-гейтов).
Мутации `Form.xml` — skill `1c-metadata-manage` (form-*). Dump/load — `1c-dump`.

Роутер: сначала этот skill, затем только нужные companion docs.

> **Execution gate.** Мутации `Form.xml` — `1c-metadata-manage` (`docs/form-manage.md`, form-compile DSL). Hard rule — в SKILL того skill. `Form.Module.bsl` — обычный BSL.

## Routing

| Task | Load |
|------|------|
| Layout from scratch | `form-patterns.md` |
| Create / structural `Form.xml` | `forms-add.md`, `std-metadata-xml` |
| Typical form presentation rules | `forms-add.md` → Form-Presentation Rules |
| Form event handlers | `form-module.md` → Adding Form Event Handlers |
| `Form.Module.bsl` logic | `form-module.md` |
| Reserved names (`ПараметрыВыбора`, …) | `form-module.md` → Reserved Names |
| Module regions | `std-module-structure` |
| Client-server / round trips | `std-client-server`, `std-anti-patterns` (Excessive Client-Server Calls, `&НаСервере` vs БезКонтекста) |
| Async (`Асинх` / `Ждать`) | `async-methods.md` |
| Adopted form in extension | `std-extension-patterns` |

Не прелоадить весь набор «на всякий случай».
