---
name: 1c-forms
description: >-
  Managed forms router: Form.xml layout, form module, events, async, reserved names.
  Use when creating or editing managed forms, form modules, or async client handlers.
disable-model-invocation: true
---

# 1c-forms — управляемые формы

Источник: адаптировано из [comol/ai_rules_1c](https://github.com/comol/ai_rules_1c) (без MCP-гейтов).
Мутации `Form.xml` — предпочтительно через skill `1c-metadata-manage` (form-*).
Dump/load конфы — `1c-ibcmd-pack` / `1c-designer-agent` (без update-db-cfg).


# Managed Forms — Entry Point

This file is the **router** for managed-form work. Load it first, then load only the companion rules selected by the table below — companion files are not auto-attached by file pattern.

> **Execution gate.** Companion rules define *what* a correct form looks like; the *mutation* of `Form.xml` / layouts itself goes through the **`1c-metadata-manage`** skill (`form-manage.md`, form-compile DSL) or skill `1c-metadata-manage` — hard gate per `AGENTS.md → Skills and Subagents`, exceptions only per the skill's `SKILL.md → Hard rule`. Editing `Form.Module.bsl` logic is regular BSL work and is not covered by this gate.

## Routing

| Task | Load |
|---|---|
| Design a form layout from scratch, or when requirements do not specify element placement | `form-patterns.md` |
| Create or structurally modify `Form.xml` | `forms-add.md`, `metadata-xml-workarounds.md` |
| Programmatic modification of typical forms (element placement, fill checking, form commands) | `forms-add.md → Form-Presentation Rules` |
| Add or rename form event handlers | `form-module.md → Adding Form Event Handlers` |
| Edit `Form.Module.bsl` logic | `form-module.md` |
| Server-side form-module code (reserved names `ПараметрыВыбора`, `СвязиПараметровВыбора`, `СписокВыбора`, `ПараметрыОтбора`, `ОтборСтрок`) | `form-module.md → Reserved Names` |
| Set up module regions in a new form module | `module-structure.md → Form Module` (5 mandatory regions) |
| Client-server architecture (directives, round trips) | `skill `std-architecture` §3 → "Client-Server Interaction"`, `skill `std-anti-patterns` → "Excessive Client-Server Calls"`, `skill `std-anti-patterns` → "Using &НаСервере Instead of &НаСервереБезКонтекста"` |
| Client-side async code (`Асинх` / `Ждать`) | `async-methods.md` |
| Working on an adopted form of an extension | `skill `std-extension-patterns``, `skill `std-architecture` §2` |

Each companion file is self-contained — load only the ones that match the task. Do not preload the whole set "to be safe".
