# Agent notes — шаблон конфигурации 1С

Канон полей ИБ/auth: [`.1c/README.md`](.1c/README.md).
Перед любой задачей 1С **сразу** прочитай skill **`1c-invariants`** (plugin-rules с alwaysApply часто не в контексте).

| Задача | Куда |
|--------|------|
| Пути скриптов (SkillHome ≠ ProjectRoot) | skill `1c-invariants` |
| Dump/load XML | skill **`1c-dump`** (`tools.preferredDump`) → ibcmd или designer-agent. Только основная, без apply/КБД |
| Служебная `.1c/ib-ext` | `1c-runtime` → `Invoke-1cServiceIb.ps1 -Action ensure` (без apply). Не `Ensure-ServiceIb` через `-Command` |
| Общий runtime (Common-*) | skill **`1c-runtime`** |
| SQL vs пользователь 1С | rule `1c-ibcmd-auth` |
| EPF | `1c-external-epf` → `ext/` |
| CFE | `1c-external-cfe` → `cfe/`. «Проверь применимость» → `pack` на `.1c/ib-ext`, не `cfe-validate` |
| XML метаданных (без ИБ) | `1c-metadata-manage`. **Новый объект:** пустышка в Конфигураторе → dump → заполнение; не `meta-compile` (skill `1c-invariants`) |
| Проверка запросов | opt-in, skill `1c-query-validate` (оркестратор; `-ReuseOnly`) |
| Bootstrap | `1c-project-bootstrap` |
| Sync клона (legacy) | `1c-template-sync`; после — [`docs/TEMPLATE_UPGRADE.md`](docs/TEMPLATE_UPGRADE.md) |
| Стандарты BSL | `coding-standards` → `std-*` |
| Справка платформы (типы/методы/запросы) | skill **`1c-syntax`** (MCP `bsl-syntax`). Нет базы → `/1c-syntax-index`. Не угадывать API |
| Формы | `1c-forms` |
| Упаковка `.cf` | `1c-ibcmd-pack` / `Invoke-1cIbcmdPack.ps1` |
| `.ps1` | UTF-8 BOM, ASCII-пунктуация; rule `ps1-encoding` |

Секреты пользователя **1С** — Windows Credential Manager (`auth.credentialTarget`). SQL при `windowsAuth: true` — доменная учётка процесса, CredMgr туда не подставлять.

Scaffold / pack / dump / load — **основной агент** (rule `1c-orchestrator`). `/implementer` — только файлы.

Knowledge-слой форм/антипаттернов/XML частично из [comol/ai_rules_1c](https://github.com/comol/ai_rules_1c) (без MCP-гейтов и без их dump/load).
