---
name: 1c-ibcmd-pack
description: >-
  ibcmd: pack XML→.cf; быстрый dump/export и partial import XML в основную
  конфигурацию (без apply/КБД). Preferred when tools.preferredDump=ibcmd.
  Use when user asks ibcmd, pack cf, dump/export, load-changed via ibcmd,
  сравнить с designer-agent, or project prefers ibcmd.
---

# 1C ibcmd (pack + dump + load)

Если в `.1c/project.json` задано `"tools": { "preferredDump": "ibcmd" }` — это **основной** путь dump/load; designer-agent только по явной просьбе или если ibcmd недоступен.
## Сценарии

| Сценарий | Скрипт | ИБ |
|----------|--------|-----|
| XML → `.cf` | `Invoke-1cIbcmdPack.ps1` | служебная **файловая** |
| dump / partial load XML | `Invoke-1cIbcmdDump.ps1` | `--db-path` **или** DBMS |

На пилоте (client-server, `adm-sand-theta` / MSSQL `theta-msdb-sd`/`com_dackov`, 8.3.23, ~8801 XML ≈174 МБ):

| Операция | agent | ibcmd |
|----------|------:|------:|
| полная выгрузка | ~68 с | ~14 с |
| инкремент (`dump-update` / `--sync`) | ~28 с | ~9 с |
| partial load (3 файла РС) | ~36 с | ~7 с |

И dump, и load — только **основная** (КБД не трогали; подтверждено в UI).

Файловая ИБ (пилот «КБ файл тест», тот же XML ≈8802 файла): полный `export` ~**15 с** (Конфигуратор **закрыт**).

### Открытый Конфигуратор (файловая ИБ)

На **файловой** ИБ, если Конфигуратор уже открыт на этой же базе, ibcmd падает сразу:

`Ошибка исключительной блокировки информационной базы`

**Что говорить пользователю (коротко):** Конфигуратор держит исключительную блокировку файловой ИБ — закрой Конфигуратор по этой базе и повтори. Это ожидаемо (как AgentMode на файловой ИБ), не баг скрипта.

На **client-server** открытый Designer обычно не мешает ibcmd (подключение к СУБД).

### Пользователи ИБ и инкремент (проверено)

| Ситуация | Результат |
|----------|-----------|
| ИБ **с пользователями**, верные `--user`/`--password` | dump-full / `--sync` / import — **OK** (C/S и файловая) |
| ИБ **без пользователей**, без `--user` | **OK** (`auth.required: false`) |
| ИБ **с пользователями**, без `--user` | **нельзя** выгрузить конфу: stdin-prompt → hang / `требуется аутентификация` |
| Неверный/несуществующий пользователь или пароль | `Идентификация пользователя не выполнена` (быстрый fail) |
| `--sync` в каталог, где `ConfigDumpInfo` от **другой** ИБ | нужен полный export |

**Ошибки ibcmd → что сказать пользователю:**

1. `Для выполнения операции требуется аутентификация…` / `Идентификация пользователя не выполнена` / зависание с `Пароль для '…':` / `Имя пользователя:`  
   → Неверный или отсутствующий пользователь/пароль ИБ. Проверь `auth` в `project.local.json`. Если в ИБ **нет** пользователей — `auth.required: false` и не передавать `--user`. Если пользователи **есть** — **обязательно** существующий `--user`/`--password` (без них конфиг не получить).

2. `Ошибка исключительной блокировки информационной базы`  
   → Закрой Конфигуратор (файловая ИБ).

3. `Требуется экспортировать конфигурацию полностью` (при `--sync`)  
   → `ConfigDumpInfo.xml` не от этой ИБ (другая база / битый маркер). Сделай `dump-full` в этот каталог, потом снова `--sync`.

4. `Каталог … не пуст` (при полном `export`)  
   → ibcmd требует **пустой** каталог. В `src/` обычно лежат `README.md` и `_extDataProcessors/` — скрипт `Invoke-1cIbcmdDump.ps1` **сам** выгружает во staging (`.1c/ibcmd-dump-staging/`) и мержит в целевой каталог, сохраняя preserve-пути. Для бенч-каталогов: `-NoStaging` только если каталог пустой.

5. Голый `ibcmd config …` (без `infobase`) при пользователях → интерактивный auth на stdin → «завис». Всегда `ibcmd infobase config …` + закрытый stdin.  
   Скрипты `Invoke-1cIbcmdDump` / `Pack` дополнительно **poll** stdout/stderr: при `Имя пользователя:` / `Пароль для` / `требуется аутентификация` процесс убивается сразу (не ждать ~1 мин).

## Критические правила CLI (проверено 8.3.23)

1. **Всегда** `ibcmd infobase config …`, не голый `ibcmd config …`.  
   Иначе при пользователях в ИБ — запрос auth на stdin → агент «зависает».
2. **Нет** `/IBName` и cluster `Srvr=…;Ref=…`. Только файл или СУБД.
3. **MSSQL / доменная учётка**: без `--db-user` / `--db-pwd`.
4. **Пользователь 1С**: `--user` / `--password` (`project.local.json` / env).
5. `--data=<dir>` (обычно `.1c/ibcmd-data/`, в `.gitignore`).
6. Автоматизация: **stdin закрыт** (`< NUL`) — скрипты это делают.
7. **`export` / `export --sync` и `import` / `import files` → только основная конфигурация.**  
   **Не** вызывать `config apply` (= обновление КБД / `update-db-cfg`). Принятие в КБД — вручную в Конфигураторе.  
   Пилот: после `import files` обновилась **только основная**, КБД без изменений (подтверждено в UI).
8. `config save` без `--db` — основная; `save --db` — КБД.  
   `export`/`--sync` также видит правки **основной** без прожатия бочки (совпало с designer `dump-update`).

## Dump / export

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<kit>/.cursor/skills/1c-ibcmd-pack/scripts/Invoke-1cIbcmdDump.ps1" `
  -Action dump-full -ProjectRoot "<repo>"
```

| Action | ibcmd | Аналог designer-agent |
|--------|-------|------------------------|
| `dump-full` | `export <dir>` | `dump-full` |
| `dump-update` | `export --sync` | `dump-update` |
| `load-files` | `import files` (+ list) | `load-changed` |
| `ping` | `export info` | проверка связи |

`-OutDir` — каталог XML (дефолт `src`). Бенчи: `-OutDir .1c/dump-test/ibcmd`.

### Staging (`src/` + README / `_extDataProcessors`)

Проверено 8.3.23: полный `ibcmd export` требует **пустой** каталог; `export --sync` ломается, если рядом с XML есть посторонние файлы.

`Invoke-1cIbcmdDump.ps1` по умолчанию:

| Action | Когда staging | Что делает |
|--------|---------------|------------|
| `dump-full` | целевой каталог не пуст | export → `.1c/ibcmd-dump-staging/` → merge в `OutDir` |
| `dump-update` | в каталоге есть preserve-пути | копия только XML → staging → `--sync` → merge |

**Сохраняются** (не удаляются при merge): `README.md`, `ext.dir` (обычно `_extDataProcessors/`), опционально `ibcmd.preservePaths` в `project.json`.

Пустой бенч-каталог: `-NoStaging`. Designer-agent staging **не** нужен — дампит прямо в `src/`.

## Load / import (только основная)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<kit>/.cursor/skills/1c-ibcmd-pack/scripts/Invoke-1cIbcmdDump.ps1" `
  -Action load-files -ProjectRoot "<repo>" -ListFile ".1c/load-list.txt"
```

`-ListFile` — пути **относительно** каталога XML (`src` / `-OutDir`), по одному на строку.  
Скрипт: `infobase config import files --base-dir=…` и **никогда** не делает `apply`.

Вручную:

```text
ibcmd infobase config import files ^
  --dbms=MSSQLServer --db-server=<sql> --db-name=<db> ^
  --data=.1c/ibcmd-data --user=<1c> --password=<…> ^
  --base-dir=<src> <file1> <file2> …
```

### Конфиг (client-server)

Один блок `infobase` — agent читает `name`, ibcmd — `dbms`:

```json
"infobase": {
  "type": "ibname",
  "name": "…имя из списка…",
  "dbms": {
    "kind": "MSSQLServer",
    "server": "sql-host",
    "name": "db_name",
    "windowsAuth": true
  }
},
"ibcmd": { "dataDir": ".1c/ibcmd-data" }
```

Файловая: `type: file` + `path` — оба инструмента из одного поля.

Dump вручную:

```text
ibcmd infobase config export ^
  --dbms=MSSQLServer --db-server=<sql> --db-name=<db> ^
  --data=.1c/ibcmd-data --user=<1c> --password=<…> ^
  <outDir>
```

Инкремент: `--sync` (нужен `ConfigDumpInfo.xml` в `<outDir>`).

## Pack (XML → .cf)

Пакетно получить `.cf` из hierarchical XML **без EDT**.  
Служебная ИБ может быть пустой файловой без пользователя — тогда auth **не** спрашивать.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<kit>/.cursor/skills/1c-ibcmd-pack/scripts/Invoke-1cIbcmdPack.ps1" -Action pack
```

| Action | Что |
|--------|-----|
| `pack` | ensure IB → import → apply (если включено) → save `.cf` |
| `pack-delta` | git diff → урезанный XML → import → save |
| `ensure-ib` / `import` / `save-cf` | по шагам |

`pack.apply: true` здесь допустим — это **служебная** ИБ для сборки cf, не продуктовый dump/load.

Env: `1C_IBCMD`, `1C_IB_PATH`, `1C_IB_USER`, `1C_IB_PASSWORD`, `1C_DB_USER`, `1C_DB_PASSWORD`.

## Жёсткие правила

1. Не трогать хранилище / авто-помещение.
2. Не коммитить `.cf`, `.1c/ib-pack*`, `.1c/ibcmd-data`, `project.local.json`, dump-test.
3. Версия `ibcmd` = `platformVersion`.
4. Ошибка — stderr + exit code.
5. **Dump/load-скрипт не вызывает `config apply`.**
6. При ошибке **исключительной блокировки** на файловой ИБ — сразу указать: закрыть Конфигуратор по этой базе (см. выше), не искать другие причины.

## Результат пользователю

Dump/load: каталог, list/файлы, `ELAPSED_SEC`, тип подключения (без паролей), явно «без apply / КБД».  
Pack: путь к `.cf`, credentials да/нет.
