---
name: 1c-syntax-index
description: Собрать или пересобрать sqlite-справку платформы 1С из shcntx_ru.hbk (bsl-ctx setup).
---

# Индексация справки платформы

Сначала skill **`1c-syntax`**.

1. `Get-1cSyntaxStatus.ps1 -ProjectRoot "<workspace>"` - если `dbOk=true` и пользователь не просил пересобрать, спроси про `-Rebuild`.
2. Нужны `uvx` и `shcntx_ru.hbk` у `platformVersion` из `.1c/project.json`. Нет uv - предложи https://docs.astral.sh/uv/ (с согласия).
3. Запусти (долго, сеть на первый `uvx`):

```powershell
powershell -NoProfile -File "<SkillHome-1c-syntax>/scripts/Build-1cSyntaxDb.ps1" -ProjectRoot "<workspace>"
```

Пересборка той же версии:

```powershell
powershell -NoProfile -File "<SkillHome-1c-syntax>/scripts/Build-1cSyntaxDb.ps1" -ProjectRoot "<workspace>" -Rebuild
```

`SkillHome-1c-syntax` = каталог `1c-syntax/SKILL.md`. Не копируй skills в проект.

4. После OK: sqlite в `%LOCALAPPDATA%\bsl-ctx\`. Если MCP `bsl-syntax` был в stub - пользователю Reload Window или переподключить MCP.
5. Не коммитить sqlite. Не парсить HTML-дамп.
