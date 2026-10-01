---
name: 1c-syntax-status
description: Статус sqlite-справки платформы 1С (bsl-ctx): платформа, hbk, база, CompatibilityMode.
---

# Статус справки платформы

Сначала skill **`1c-syntax`**.

```powershell
powershell -NoProfile -File "<SkillHome-1c-syntax>/scripts/Get-1cSyntaxStatus.ps1" -ProjectRoot "<workspace>"
```

Покажи JSON коротко: `platformVersion`, `hbkOk`, `dbOk`, `compatTarget`, `missing`, `hint`.

Если `dbOk=false` - предложи `/1c-syntax-index`. Не запускай setup без согласия.
