# Agent notes — шаблон конфигурации 1С

- Стандарты кода: skills `coding-standards`, `std-*`
- Dump/load XML: skill `1c-designer-agent` (load **без** `update-db-cfg`)
- Упаковка `.cf`: skill `1c-ibcmd-pack` (по запросу)
- **Первая настройка** (clone / копия шаблона / нет `.1c/project.json`): skill **`1c-project-bootstrap`**

Секреты ИБ — только в `.1c/project.local.json` (не коммитить).
