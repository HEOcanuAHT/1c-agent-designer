---
name: 1c-project-bootstrap
description: >-
  Первичная настройка репозитория конфигурации 1С после clone/копии шаблона:
  зависимости (Python, paramiko, платформа 1С), .1c/project.json и
  project.local.json, тип ИБ (file/server/ibname). Use when user clones
  template, asks setup/инициализация/настройка окружения, or .1c/project.json
  is missing.
---

# Bootstrap проекта конфигурации 1С

## Когда запускать

- Клон/копия `1c-project-template` (или конфиг на его базе) без рабочего `.1c/project.json`
- Пользователь просит: настройка окружения, инициализация, bootstrap, «подключи ИБ»
- Правило `1c-project-bootstrap` предложило setup — согласие пользователя

Не запускать повторно, если `.1c/project.json` уже заполнен и пользователь не просит перенастроить. Секреты не трогать без явной просьбы.

## Цель

1. Проверить зависимости dump/load (`1c-designer-agent`).
2. Создать `.1c/project.json` и `.1c/project.local.json` из example.
3. Спросить тип ИБ и заполнить поля.
4. Опционально: `ping` / подсказать первый `dump-full` ([docs/INITIAL_DUMP.md](../../../docs/INITIAL_DUMP.md)).

## Шаг 0 — корень проекта

Корень = каталог с `.cursor/skills` и `.1c/` (или куда копировали шаблон). Все пути относительно него.

## Шаг 1 — зависимости

Запусти проверку:

```powershell
…\.cursor\skills\1c-project-bootstrap\scripts\Check-1cDevEnv.ps1 -ProjectRoot "<repo>"
```

| Компонент | Зачем | Если нет |
|-----------|--------|----------|
| Платформа 1С (`1cv8.exe`) | Designer dump/load | Спросить `platformVersion` / путь установки |
| Python 3 | SSH к AgentMode (`designer_agent_ssh.py`) | Предложить установить Python 3.10+ и добавить в PATH |
| `paramiko` | то же | `pip install paramiko` (с согласия пользователя) |
| `plink` (опционально) | запасной SSH-клиент | Не обязателен, если есть Python+paramiko |
| Git | `load-changed` по diff | Обычно уже есть в среде Cursor |

**Не ставь** софт молча. Кратко покажи, чего не хватает → предложи команды → выполни только после согласия.

Транспорт по умолчанию в шаблоне: `designerAgent.transport: agent` (нужен Python+paramiko **или** plink). Batch без SSH — fallback (`transport: batch`).

## Шаг 2 — тип информационной базы

Спроси **одним** выбором (AskQuestion / аналог UI, иначе нумерованный список в чате):

| Вариант | `infobase.type` | Что спросить дальше | Поля JSON |
|---------|-----------------|---------------------|-----------|
| Файловая | `file` | путь к каталогу ИБ (слэши `C:/…` или относительный `.1c/ib-dev`) | `path` |
| Серверная | `server` | строка кластера `host\base` как для `/S` | `server` |
| По имени в списке ИБ | `ibname` | имя из окна запуска 1С (как в списке баз) | `name` |

Дополнительно (коротко):

- `platformVersion` (например `8.3.23.1865`) — можно взять из вывода Check-скрипта
- пользователь/пароль ИБ → **только** в `project.local.json` (не в git)
- `designerAgent.baseDir` — абсолютный путь репо со слэшами `C:/Users/.../repo` (удобно для AgentMode)

## Шаг 3 — файлы конфига

1. Если нет `.1c/project.json` — копируй `.1c/project.json.example`.
2. Если нет `.1c/project.local.json` — копируй `.1c/project.local.json.example`.
3. Запиши ответы пользователя.
4. Сохрани блок `template` из example (url/version/ref) — нужен для skill `1c-template-sync`.

### Примеры `infobase`

**file:**

```json
"infobase": { "type": "file", "path": "C:/Users/.../InfoBase8" }
```

**server:**

```json
"infobase": { "type": "server", "server": "tcp://app-server/MyBase" }
```

(формат строки — как ожидает `/S` у вашей площадки; уточни у пользователя, если сомневаешься.)

**ibname:**

```json
"infobase": { "type": "ibname", "name": "--== dev ==-- МояБаза" }
```

`auth` в `project.json` можно оставить `"required": true` с пустыми user/password; реальные значения — в local.

Не коммить `project.local.json`. Не писать пароль в лог/чат целиком.

## Шаг 4 — проверка связи

С согласия пользователя:

```powershell
…\1c-designer-agent\scripts\Invoke-1cDesignerAgent.ps1 -Action ping -ProjectRoot "<repo>"
```

Перед ping: обычный Конфигуратор на этой ИБ закрыт (особенно файловая).

Успех → предложи следующий шаг: `dump-full` по [docs/INITIAL_DUMP.md](../../../docs/INITIAL_DUMP.md) (если `src/` ещё пустой каркас).

## Правила поведения агента

1. Один вопрос за раз по смыслу; тип ИБ — всегда через выбор из трёх вариантов.
2. После выбора типа спрашивай **только** нужное поле (`path` / `server` / `name`).
3. Предлагай установку зависимостей явно; не «чини окружение» без согласия.
4. Dump/load — skill `1c-designer-agent`; load без `update-db-cfg`.
5. Не смешивай bootstrap с feature-pipeline / SDMS (их нет в этом шаблоне).
6. Позже обновление skills/rules — skill `1c-template-sync` (не перезаписывать `src/`).
