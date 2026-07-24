---
name: 1c-designer-agent
description: >-
  Полный/инкрементальный dump XML и load-changed по git diff через локальный
  конфигуратор (batch /DumpConfigToFiles по умолчанию). Use when user asks
  dump-config-to-files, load-changed-from-git, designer dump/load.
disable-model-invocation: true
---

# 1C dump / load-changed (PowerShell)

## Цель

1. `dump-full` / `dump-update` → XML в `src/`
2. правки в git
3. `load-changed` → в ИБ только файлы из `git diff`

**Не делает:** хранилище, захват/помещение.

Транспорт по умолчанию: **batch** (`/DumpConfigToFiles`, `/LoadConfigFromFiles`).  
AgentMode+SSH — experimental (`designerAgent.transport: agent` или `-UseAgent`).

## Два «только отличия»

| Режим | Сравнивает |
|--------|------------|
| `dump-update` (`-update`) | ИБ ↔ `ConfigDumpInfo.xml` |
| `load-changed` | `git diff BaseRef..HeadRef` под `src/` |

## Конфиг

- `.1c/project.json` — `infobase.path`, `src`, `platformVersion`
- `.1c/project.local.json` — `auth.user` / `auth.password`
- `designerAgent.transport`: `batch` (дефолт) | `agent`

Путь к файловой ИБ — со слэшами: `C:/Users/.../InfoBase8`.

## Команды

```powershell
…\Invoke-1cDesignerAgent.ps1 -Action dump-full -ProjectRoot "<repo>"
…\Invoke-1cDesignerAgent.ps1 -Action load-changed -BaseRef main
```

| Action | Что |
|--------|-----|
| `dump-full` | полная выгрузка |
| `dump-update` | инкремент vs ConfigDumpInfo |
| `load-changed` | git → `-listFile` → load |
| `ping` | проверить designer + auth |

## AgentMode и каталог `0\`

AgentMode всегда работает из `AgentBaseDir\<userDir>` (часто `0\`, см. `agentbasedir.json`).  
Скрипт передаёт `--dir=../src` и `--list-file=../.1c/...`, чтобы XML писались/читались в реальный `src/` репозитория, а не в `0\src\`.  
Папку `0\` и `agentbasedir.json` лучше держать в `.gitignore`.

## Правила

1. Не авто-помещать в хранилище.
2. Секреты только в `project.local.json` / env (в лог пароль не писать).
3. Перед dump/load закрыть обычный конфигуратор и старый AgentMode на этой ИБ.
4. После `dump-*` / `load-changed` / `ping` агент гасится (kill по `.1c/agent.pid`), если не `designerAgent.keepAlive: true`. `start` оставляет процесс жить; `stop` — ручная остановка.
5. **Загрузка (частичная и полная) — только в основную конфигурацию.** Не вызывать `update-db-cfg` / `/UpdateDBCfg`. Принятие в конфигурацию БД — вручную в Конфигураторе.

### Когда операция закончена

Агент отдаёт JSON `"type":"success"` — это основной отбойник (в логе `SUCCESS+MARKER` / `SUCCESS (no marker)`).  
Для dump с `--marker-file` success принимается вместе с обновлением `Configuration.xml`.  
Запасной путь — стабильность `ConfigDumpInfo.xml` (~5 с).  
После операции агент гасится по `.1c/agent.pid` (вторая SSH-сессия shutdown больше не используется).

`load-changed -ListFile <path>` — явный список путей относительно `src/` (удобно для незакоммиченных файлов).

## Параллель с открытым Конфигуратором (файловая ИБ)

Проверено (один и тот же / другой пользователь ИБ — без разницы): второй процесс `/AgentMode` **стартует** и открывает порт, но SSH-логин падает:

`Authentication failed: transport shut down or saw EOF`

Дамп при открытом Designer на той же файловой ИБ **не работает**. Нужно закрыть пользовательский конфигуратор.
