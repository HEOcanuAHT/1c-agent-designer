# `.1c/project.json` — варианты `infobase`

Рабочий файл: скопировать `project.json.example` → `project.json`.  
Секреты: `project.local.json` (не в git).  
Первичная настройка агентом: skill `1c-project-bootstrap`.  
Обновление tooling из шаблона: skill `1c-template-sync` (манифест `.1c/template-manifest.json`).

Опционально `ext.dir` / `ext.artifacts` — каталоги внешних обработок (skill `1c-external-epf`; дефолты `src/_extDataProcessors` и `artifacts/ext`).

Блок `template` — откуда тянуть обновления skills/rules (`url` / `version` / `ref`). Sync его обновляет; `src/` и секреты не трогает.

| type | Поля | Designer |
|------|------|----------|
| `file` | `path` — каталог ИБ (`C:/…` или `.1c/ib-dev`) | `/F` |
| `server` | `server` — строка кластера как для `/S` | `/S` |
| `ibname` | `name` — имя из списка информационных баз | `/IBName` |

Проверка окружения:

```powershell
.\.cursor\skills\1c-project-bootstrap\scripts\Check-1cDevEnv.ps1 -ProjectRoot .
```
