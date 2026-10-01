<!-- Adapted from comol/ai_rules_1c / cc-1c-skills. IB dump/load/EPF pack: use template skills. -->

# 1C SSL/БСП Subsystems Reference

For basic SSL usage (attribute access, user messages) — see skill `std-architecture` (Data Access) and `std-code-style`.

## When to Use

Invoke this skill when:
- Working with users and access rights
- Working with files and attachments
- Implementing print forms
- Managing background jobs
- Working with object versioning
- Sending emails
- Need common utility functions (arrays, structures, strings)

## Core Principle

**ALWAYS check if SSL has a solution before writing custom code.**

## SSL Search Workflow

When implementing new functionality:

1. **First, search SSL** — use `BSP docs (MCP optional)` MCP tool with keywords describing your need
   - Example: `BSP docs (MCP optional)("фоновое задание прогресс")`
   - Example: `BSP docs (MCP optional)("копирование структуры")`

2. **Check existing patterns** — use `Grep src/ (MCP optional)` to find how similar tasks are solved in the codebase

3. **Use SSL if available** — it's tested, optimized, and maintained

4. **Only then write custom code** — and document why SSL wasn't suitable

## Key SSL Modules

- **Пользователи** — users, roles, access rights
- **РаботаСФайлами** — file storage and attachments
- **УправлениеПечатью** — print forms
- **ДлительныеОперации** — background jobs with progress
- **ВерсионированиеОбъектов** — object history
- **РаботаСПочтовымиСообщениями** — email sending
- **ОбщегоНазначения** / **ОбщегоНазначенияКлиентСервер** — common utilities
- **СтроковыеФункцииКлиентСервер** — string functions

---

**Remember**: SSL is your first stop for common functionality. Writing custom code when SSL has a solution is technical debt.
