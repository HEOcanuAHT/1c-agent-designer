---
name: 1c-metadata-manage
description: >-
  Create/edit/validate 1C metadata XML, managed forms, DCS/SKD, MXL, roles,
  subsystems, CFE XML (borrow/patch). Prefer these scripts over hand-editing XML.
  Not for dump/load IB, EPF pack, or UpdateDBCfg — use 1c-ibcmd-pack /
  1c-designer-agent / 1c-external-epf / 1c-external-cfe.
disable-model-invocation: true
---

# 1c-metadata-manage — XML метаданных без поломок

Адаптировано из [comol/ai_rules_1c](https://github.com/comol/ai_rules_1c) / [cc-1c-skills](https://github.com/Nikolay-Shirokov/cc-1c-skills).

**Не заменяет** наши сборщики:

| Задача | Канон шаблона |
|--------|----------------|
| Dump/load XML основной конфы | `1c-ibcmd-pack` / `1c-designer-agent` (**без** update-db-cfg) |
| EPF pack/dump/scaffold | `1c-external-epf` → `src/_extDataProcessors/`, `.1c/ib-ext` |
| CFE pack/dump/scaffold в артефакты | `1c-external-cfe` → `src/_extensions/` |
| Bootstrap / sync | `1c-project-bootstrap` / `1c-template-sync` |

Этот skill — **сборка/правка XML** (UUID, ChildObjects, Form.xml, СКД, роли, borrow CFE) и валидация скриптами.

## Hard rule (смягчённый)

Мутации метаданных XML предпочтительно через скрипты `tools/` ниже (BOM, UUID, порядок ChildObjects).

Исключения:

- однострочный фикс существующего значения (синоним, флаг);
- skill недоступен — ручной edit + `std-metadata-xml` + `*-validate`;
- read-only анализ XML — напрямую.

После мутации — соответствующий `*-validate` / `*-info`.

**Запрещено** этим skill: `/UpdateDBCfg`, `ibcmd config apply` на боевую ИБ, ad-hoc dump/load вместо `1c-ibcmd-pack` / `1c-designer-agent`.

## Пути скриптов

Относительно корня репозитория:

`.cursor/skills/1c-metadata-manage/tools/<tool>/scripts/...`

Пример:

```powershell
powershell.exe -NoProfile -File .cursor/skills/1c-metadata-manage/tools/1c-meta-validate/scripts/meta-validate.ps1 ...
```

Расширения: XML-исходники в `src/_extensions/<Name>/` (не корень `src/` как у upstream).  
Внешние обработки: `src/_extDataProcessors/` + skill `1c-external-epf` (здесь нет epf-build/dump).

## Домены

| Задача | Документ | Tools |
|--------|----------|-------|
| Объекты метаданных | [docs/meta-manage.md](docs/meta-manage.md) | `1c-meta-*` |
| Управляемые формы | [docs/form-manage.md](docs/form-manage.md), DSL [docs/form-compile-dsl.md](docs/form-compile-dsl.md) | `1c-form-*` |
| Паттерны layout | skill `1c-forms` / [docs/form-patterns.md](docs/form-patterns.md) | — |
| СКД | [docs/skd-manage.md](docs/skd-manage.md) | `1c-skd-*` |
| MXL | [docs/mxl-manage.md](docs/mxl-manage.md) | `1c-mxl-*` |
| Роли | [docs/role-manage.md](docs/role-manage.md) | `1c-role-*` |
| CFE XML (borrow/diff/patch) | [docs/cfe-manage.md](docs/cfe-manage.md) | `1c-cfe-manage` + pack через `1c-external-cfe` |
| Configuration.xml | [docs/cf-manage.md](docs/cf-manage.md) | `1c-cf-manage` |
| Подсистемы / интерфейс | [docs/subsystem-manage.md](docs/subsystem-manage.md), [docs/interface-manage.md](docs/interface-manage.md) | `1c-subsystem-manage`, `1c-interface-manage` |
| Макеты / справка | [docs/template-manage.md](docs/template-manage.md), [docs/help-manage.md](docs/help-manage.md) | `1c-template-manage`, `1c-help-manage` |
| БСП регистрация | [docs/bsp-manage.md](docs/bsp-manage.md), [docs/ssl-patterns.md](docs/ssl-patterns.md) | — |

Сопровождающие knowledge skills: `std-metadata-xml`, `1c-forms`, `std-extension-patterns`, `std-dcs-design`, `std-registers-design`.

## Не включено из upstream (намеренно)

`1c-db-ops`, `1c-web-ops`, `1c-epf-*`, `1c-erf-*` — конфликт с нашим IB/EPF tooling.
