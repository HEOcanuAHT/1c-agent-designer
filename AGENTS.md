# Agent notes — шаблон конфигурации 1С

- Стандарты кода: skills `coding-standards`, `std-*`
- **Dump/load XML** — смотри `tools.preferredDump` в `.1c/project.json`:
  - `ibcmd` (предпочтительно) → skill **`1c-ibcmd-pack`** / `Invoke-1cIbcmdDump.ps1`  
    (file `--db-path` или `infobase.dbms`; **только основная**, без `apply`/КБД)
  - `agent` → skill **`1c-designer-agent`** (load **без** `update-db-cfg`)
- Внешние обработки (`.epf`): skill **`1c-external-epf`** → `src/_extDataProcessors/`
- Упаковка `.cf`: skill `1c-ibcmd-pack` → `Invoke-1cIbcmdPack.ps1`
- **Первая настройка** (clone / нет `.1c/project.json`): skill **`1c-project-bootstrap`**  
  (интерактивный чеклист: тип ИБ, auth, ibcmd vs agent, доступ к SQL)
- **Обновление шаблона** в живом проекте: skill **`1c-template-sync`** (после sync — предложить миграцию `auth.password` → Credential Manager)

Секреты ИБ — **Windows Credential Manager** (`auth.credentialTarget`, скрипт `Set-1cIbCredential.ps1`);  
fallback: env `1C_IB_USER`/`1C_IB_PASSWORD` или устаревший plaintext в `.1c/project.local.json` (не коммитить).
