# `.1c/project.json` — варианты `infobase`

Рабочий файл: скопировать `project.json.example` → `project.json`.  
Секреты: `project.local.json` (не в git).  
Первичная настройка агентом: skill `1c-project-bootstrap`.  
Обновление tooling из шаблона: skill `1c-template-sync` (манифест `.1c/template-manifest.json`).

Опционально `ext.dir` / `ext.artifacts` — каталоги внешних обработок (skill `1c-external-epf`; дефолты `src/_extDataProcessors` и `artifacts/ext`).

Локальные сравнения выгрузок (не в git): `.1c/dump-test/agent/` и `.1c/dump-test/ibcmd/` — см. README в `dump-test/`.

Для **ibcmd dump** на client-server ИБ добавь `infobase.dbms` (`kind` / `server` / `name`, обычно `windowsAuth: true`) — `/IBName` ibcmd не умеет. Рабочий каталог: `ibcmd.dataDir` или `.1c/ibcmd-data/`. Скрипт: `1c-ibcmd-pack/scripts/Invoke-1cIbcmdDump.ps1`. Всегда `infobase config …`, не голый `config` (иначе hang на stdin).

Блок `template` — откуда тянуть обновления skills/rules (`url` / `version` / `ref`). Sync его обновляет; `src/` и секреты не трогает.

В `project.local.json` опционально `auth.uc` — код разблокировки ИБ (`/UC` при старте AgentMode). Env: `1C_IB_UC`.

Для `ibname` имя из списка баз может содержать кавычки — скрипт экранирует их как `""` (не `\"`).

| type | Поля | Designer |
|------|------|----------|
| `file` | `path` — каталог ИБ (`C:/…` или `.1c/ib-dev`) | `/F` |
| `server` | `server` — строка кластера как для `/S` | `/S` |
| `ibname` | `name` — имя из списка информационных баз | `/IBName` |

Проверка окружения:

```powershell
.\.cursor\skills\1c-project-bootstrap\scripts\Check-1cDevEnv.ps1 -ProjectRoot .
```
