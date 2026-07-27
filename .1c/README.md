# `.1c/project.json` — варианты `infobase`

Рабочий файл: скопировать `project.json.example` → `project.json`.  
Секреты: `project.local.json` (не в git).  
Первичная настройка агентом: skill `1c-project-bootstrap`.

Опционально `ext.dir` / `ext.artifacts` — каталоги внешних обработок (skill `1c-external-epf`; дефолты `src/_extDataProcessors` и `artifacts/ext`).

| type | Поля | Designer |
|------|------|----------|
| `file` | `path` — каталог ИБ (`C:/…` или `.1c/ib-dev`) | `/F` |
| `server` | `server` — строка кластера как для `/S` | `/S` |
| `ibname` | `name` — имя из списка информационных баз | `/IBName` |

Проверка окружения:

```powershell
.\.cursor\skills\1c-project-bootstrap\scripts\Check-1cDevEnv.ps1 -ProjectRoot .
```
