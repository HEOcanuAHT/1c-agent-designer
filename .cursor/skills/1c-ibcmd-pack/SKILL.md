---
name: 1c-ibcmd-pack
description: >-
  Собирает .cf из XML-выгрузки (src) через ibcmd: пустая/служебная ИБ,
  import XML → apply → save .cf. Параметры платформы и пути — из .1c/project.json
  проекта. Use when user asks to pack config to cf, ibcmd, XML→.cf, выгрузить cf,
  перегнать выгрузку в cf.
disable-model-invocation: true
---

# 1C ibcmd pack (XML → .cf)

## Цель

Пакетно получить `.cf` из иерархической XML-выгрузки **без EDT** и без UI Конфигуратора.
Служебная база может быть **пустой файловой** и **без пользователя** — тогда логин/пароль **не спрашивать и не передавать**.

Это **не** помещение в хранилище и не замена форм/метаданных в Cursor.

## Конфиг проекта (обязателен)

В корне репозитория конфигурации:

- `.1c/project.json` — в git (без секретов)
- `.1c/project.local.json` — опционально, в `.gitignore` (локальные пути/секреты)

Минимальный пример — `project.json.example` рядом с этим skill.

### Поля

| Поле | Назначение |
|------|------------|
| `platformVersion` | например `8.3.23.1865` → поиск `ibcmd.exe` |
| `ibcmd` | явный путь к ibcmd (если задан — важнее автопоиска) |
| `src` | каталог XML (обычно `src`) |
| `artifacts` | куда класть `.cf` |
| `infobase.type` | пока только `file` |
| `infobase.path` | каталог файловой ИБ (можно `.1c/ib-pack` внутри репо) |
| `infobase.createIfMissing` | создать ИБ, если нет |
| `auth.required` | `false` → **никогда** не просить user/password |
| `auth.user` / `auth.password` | только если `required: true` (лучше в `project.local.json` или env) |
| `pack.cfName` | имя выходного `.cf` |
| `pack.force` | передать `--force` ibcmd при предупреждениях |
| `pack.apply` | после import вызвать apply конфигурации БД |

Env-оверрайды (опционально): `1C_IBCMD`, `1C_IB_PATH`, `1C_IB_USER`, `1C_IB_PASSWORD`.

## Когда спрашивать пользователя

- Нет `.1c/project.json` и не передан путь к конфигу → создать по example, спросить только `platformVersion` и путь ИБ (или оставить `.1c/ib-pack`).
- `auth.required: true` и нет user/password в local/env → спросить **один раз** или предложить записать в `project.local.json`.
- `auth.required: false` (дефолт для пустой перегонки) → **не спрашивать** учётку.

## Команды агента

Из корня репо конфигурации (или с `-ProjectRoot`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<kit>/.cursor/skills/1c-ibcmd-pack/scripts/Invoke-1cIbcmdPack.ps1" -Action pack
```

Действия:

| Action | Что делает |
|--------|------------|
| `pack` | ensure IB → import XML → apply (если включено) → save `.cf` |
| `pack-delta` | построить обрезанную XML-папку по `git diff` → import в отдельную служебную ИБ → save `.cf` |
| `ensure-ib` | создать пустую файловую ИБ при необходимости |
| `import` | только import XML в ИБ |
| `save-cf` | только save текущей конфигурации в `.cf` |

Скрипт сам читает `.1c/project.json` (+ local), резолвит `ibcmd`, не передаёт `-u`/`-P`, если auth не required.

### pack-delta: диапазон дифа

Для `pack-delta` скрипт запускает `git diff --name-only <BaseRef> <HeadRef>` и копирует в временный delta-src только затронутые объекты (плюс `Configuration.xml` и `ConfigDumpInfo.xml`).

Вызов:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<kit>/.cursor/skills/1c-ibcmd-pack/scripts/Invoke-1cIbcmdPack.ps1" `
  -Action pack-delta `
  -ProjectRoot "<repoRoot>" `
  -BaseRef "<baseRef>" `
  -HeadRef "<headRef>"
```

Если `-BaseRef/-HeadRef` не переданы, скрипт возьмёт их из `.1c/project.json` -> `delta.baseRef/delta.headRef` или возьмёт дефолты `HEAD~1` и `HEAD`.

Эквивалент ibcmd (справочно, файловая ИБ без пользователя):

```text
ibcmd infobase create --db-path=<ib> --import=<src> --apply --force
ibcmd config save --db-path=<ib> <artifacts>/<name>.cf
```

или на существующей ИБ:

```text
ibcmd config import files --db-path=<ib> --base-dir=<src> [--force]
ibcmd config apply --db-path=<ib> --force
ibcmd config save --db-path=<ib> <out.cf>
```

## Жёсткие правила

1. Не трогать продуктовое хранилище и не предлагать авто-помещение.
2. Не коммитить `.cf`, каталог служебной ИБ (`.1c/ib-pack`), `project.local.json`.
3. Версия `ibcmd` должна соответствовать `platformVersion` проекта (разные репо — разные версии через свой `project.json`).
4. При ошибке ibcmd — показать stderr и код выхода, не выдумывать успех.

## Результат пользователю

Кратко: путь к `.cf`, использованные `ibcmd` и `db-path`, было ли создание ИБ, были ли credentials (да/нет — без печати пароля).
