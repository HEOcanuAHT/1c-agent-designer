<!-- Adapted from comol/ai_rules_1c / cc-1c-skills. IB dump/load/EPF pack: use template skills. -->

# Form Patterns — pointer to canonical rule

**Canonical source:** `.cursor/skills/1c-forms/docs/form-patterns.md` (or its installed copy under the active tool's rules directory — `.cursor/rules/form-patterns.mdc`, `.claude/rules-1c/`, …).

This file is intentionally a thin pointer. Do **not** duplicate archetypes, naming conventions, or advanced ERP patterns here — edit the rule file only.

**When to load:** before designing a form via `1c-form-compile` when user requirements do not specify element placement (5+ elements or unclear requirements). For simple 1–3 field forms it is not needed.

**Also load:** the project forms router `related std-* / 1c-forms skills` first for any managed-form task — it selects companions (`forms-add.md`, `form-module.md`, `async-methods.md`, …).
