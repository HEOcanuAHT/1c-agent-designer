---
name: 1c-metadata-manage
description: >-
  Create/edit/validate 1C metadata XML, forms, DCS/SKD, MXL, roles, subsystems,
  CFE borrow/patch. Prefer tools/ scripts over hand-editing. Not dump/load IB
  or EPF/CFE pack — use 1c-dump / 1c-external-epf / 1c-external-cfe.
disable-model-invocation: true
---

# 1c-metadata-manage — роутер XML

Правка XML метаданных скриптами (`tools/`). Dump/load/pack ИБ — **не** здесь.

| Канон шаблона | Skill |
|---------------|--------|
| Dump/load конфы | `1c-dump` |
| EPF scaffold/pack | `1c-external-epf` |
| CFE scaffold/pack | `1c-external-cfe` |

## Hard rule

Мутации XML — через `tools/` (BOM, UUID, ChildObjects). Исключения: однострочный фикс; skill недоступен → ручной edit + `std-metadata-xml` + `*-validate`; read-only — напрямую. После мутации — `*-validate` / `*-info`.

Запрещено: `/UpdateDBCfg`, `config apply` на боевую, ad-hoc dump/load.

## Пути

`SkillHome` = каталог этого SKILL.md. XML в workspace (`src/`, `cfe/<Name>/`, `ext/`).

```powershell
powershell.exe -NoProfile -File "<SkillHome>/tools/<tool>/scripts/….ps1" ...
```

## Домены (грузи только нужный docs)

| Задача | Docs | Tools |
|--------|------|-------|
| Объекты метаданных | [meta-manage.md](docs/meta-manage.md) | `1c-meta-*` |
| Формы | [form-manage.md](docs/form-manage.md), [form-compile-dsl.md](docs/form-compile-dsl.md); layout — `1c-forms` | `1c-form-*` |
| СКД | [skd-manage.md](docs/skd-manage.md) | `1c-skd-*` |
| MXL | [mxl-manage.md](docs/mxl-manage.md) | `1c-mxl-*` |
| Роли | [role-manage.md](docs/role-manage.md) | `1c-role-*` |
| CFE XML borrow/diff/patch | [cfe-manage.md](docs/cfe-manage.md); pack — `1c-external-cfe` | `1c-cfe-manage` |
| Configuration.xml | [cf-manage.md](docs/cf-manage.md) | `1c-cf-manage` |
| Подсистемы / интерфейс | [subsystem-manage.md](docs/subsystem-manage.md), [interface-manage.md](docs/interface-manage.md) | `1c-subsystem-manage`, `1c-interface-manage` |
| Макеты / справка | [template-manage.md](docs/template-manage.md), [help-manage.md](docs/help-manage.md) | `1c-template-manage`, `1c-help-manage` |
| БСП | [bsp-manage.md](docs/bsp-manage.md), [ssl-patterns.md](docs/ssl-patterns.md) | — |

Knowledge: `std-metadata-xml`, `1c-forms`, `std-extension-patterns`, `std-dcs-design`, `std-registers-design`.
