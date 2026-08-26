<!--
Adapted from https://github.com/comol/ai_rules_1c (upstream tools often from Nikolay-Shirokov/cc-1c-skills).
MCP-only gates removed. Dump/load/EPF/CFE pack: template skills 1c-ibcmd-pack, 1c-designer-agent, 1c-external-*.
-->

# Adding or Modifying a Managed Form

This file owns the **rules**, not the MCP sequence. The pre-edit and post-edit MCP playbooks live in:

- Sequence: Grep/Read `src/` → mutate via skill `1c-metadata-manage` (form-*) → `form-validate.ps1`. No MCP.

## Rules specific to creating / modifying a form

- **The `1c-metadata-manage` skill (form-manage)** is the preferred path for creating or structurally modifying `Form.xml` (BOM, UUID, `ChildObjects`). Hand-editing — only Hard rule exceptions in that skill.
- **Validate** after XML edit: `form-validate.ps1` from `1c-metadata-manage`.
- **Form-element naming.** Elements added to a typical form must carry the `{PREFIX}` prefix from `.1c/project.json`. Elements inside a newly created form (object already prefixed) do **not** repeat the prefix — see skill `std-metadata`.
- **Common pitfalls** — skill `std-metadata-xml`.
- **Region structure of the form module** — skill `std-module-structure` (Form Module, 5 regions).

## Form-Presentation Rules

### Programmatic Modification of Typical Forms

All typical form modifications are performed **programmatically**, not visually. Elements are created in the `OnCreateAtServer` handler (or via subscription / extension).

### Placement of Added Elements

- If the form has tabs — add elements to a separate tab (e.g. "Additional" or with `{PREFIX}`).
- If no tabs — create a group without title for added elements.
- Typical form element names — with `{PREFIX}` prefix.

### New Forms (Non-Typical Objects)

- Separate header attributes and tabular sections into distinct tabs: "Main" (header), then one tab per tabular section.
- Fill "Header Data Path" property for pages with tabular sections.
- Reference fields — maximum width 27 characters.
- Multiline comment fields — width 79, height 3.

### Fill Checking

- Use "Fill check" property on form attributes.
- Before writing / posting, call `ПроверитьЗаполнение()`:

```bsl
Если Не ПроверитьЗаполнение() Тогда
	Возврат;
КонецЕсли;
```

### Form Commands

- When creating commands that modify data — enable "Modifies stored data" flag.

## Companion rules

| If the change also includes… | Also load |
|---|---|
| Event handlers (`ПриОткрытии`, `ПередЗаписью`, …), form-module logic, reserved names | `form-module.md` |
| Client-side async code (`Асинх` / `Ждать`) | `async-methods.md` |

This list is curated by the router skill `1c-forms`; load only the items you actually touch.
