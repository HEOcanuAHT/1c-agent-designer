# Agent notes — шаблон конфигурации 1С

- Стандарты кода: skills `coding-standards`, `std-*`
- Dump/load XML: skill `1c-designer-agent` (load **без** `update-db-cfg`)
- Быстрый dump/load через ibcmd: skill `1c-ibcmd-pack` → `Invoke-1cIbcmdDump.ps1`  
  (`infobase config export|import files`, **только основная**, без `apply`/КБД)
- Внешние обработки (`.epf`): skill **`1c-external-epf`** → `src/_extDataProcessors/`
- Упаковка `.cf`: skill `1c-ibcmd-pack` → `Invoke-1cIbcmdPack.ps1`
- **Первая настройка** (clone / копия шаблона / нет `.1c/project.json`): skill **`1c-project-bootstrap`**
- **Обновление шаблона** в живом проекте (skills/rules, без `src/`): skill **`1c-template-sync`**

Секреты ИБ — только в `.1c/project.local.json` (не коммитить).
