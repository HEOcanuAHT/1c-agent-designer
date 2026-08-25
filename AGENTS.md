# Agent notes — шаблон конфигурации 1С

- **Пути скриптов:** `SkillHome` = каталог `SKILL.md` (плагин или `.cursor/skills/<name>` в клоне); `-ProjectRoot` = workspace. Rule `1c-plugin-paths`.
- Стандарты кода: skills `coding-standards`, `std-*` (в т.ч. формы/`1c-forms`, антипаттерны, СКД, расширения)
- **XML метаданных** (создать/править/validate Form/СКД/роли/CFE borrow): skill **`1c-metadata-manage`** — не заменяет dump/load
- **Dump/load XML** — смотри `tools.preferredDump` в `.1c/project.json`:
  - `ibcmd` (предпочтительно) → skill **`1c-ibcmd-pack`** / `Invoke-1cIbcmdDump.ps1` 
    (file `infobase.path` или `infobase.dbms`; **только основная**, без `apply`/КБД)
  - `agent` → skill **`1c-designer-agent`** (load **без** `update-db-cfg`)
- Внешние обработки (`.epf`): skill **`1c-external-epf`** → `ext/`; dump/pack через служебную `.1c/ib-ext` (import конфы без apply)
- Расширения (`.cfe`): skill **`1c-external-cfe`** → `cfe/`; dump/pack/scaffold через ту же `.1c/ib-ext`; BSL-паттерны — `std-extension-patterns`
- Проверка языка запросов: `Invoke-1cValidateQuery.ps1` (COM/`QuerySchema` на `.1c/ib-ext`; без HTTP/расширения). Агентам: `-ReuseOnly` + пачка `.1c/qv-batch/`; `ensure` только при `NEED_ENSURE`
- Режим «проверяй запросы» — rule `1c-query-validate` (флаг `.1c/query-validate.mode`); по умолчанию выкл.; validate только оркестратор
- Упаковка `.cf`: skill `1c-ibcmd-pack` → `Invoke-1cIbcmdPack.ps1`
- **Первая настройка** (пустая папка + плагин / clone / нет `.1c/project.json`): skill **`1c-project-bootstrap`**  
  (каркас из плагина, затем чеклист: тип ИБ, auth, ibcmd vs agent, доступ к SQL)
- **Обновление tooling** — плагин: git pull шаблона + Reload Window. Клоны с `.cursor/skills` в репо — skill `1c-template-sync`; после sync см. `docs/TEMPLATE_UPGRADE.md`
Scaffold, pack/dump, load конфы — **основной агент** (rule `1c-orchestrator` при работе с кодом/артефактами, `docs/WORKFLOW.md`).

Секреты пользователя **1С** (не SQL) — Windows Credential Manager (`auth.credentialTarget`, `Set-1cIbCredential.ps1`);  
fallback: env `1C_IB_USER`/`1C_IB_PASSWORD` или plaintext в `.1c/project.local.json` (не коммитить).  
SQL при `infobase.dbms.windowsAuth: true` — доменная учётка процесса; CredMgr 1С туда **не** подставлять (см. rule `1c-ibcmd-auth`).

Knowledge-слой форм/антипаттернов/XML частично адаптирован из [comol/ai_rules_1c](https://github.com/comol/ai_rules_1c) (без MCP-гейтов и без их dump/load).
