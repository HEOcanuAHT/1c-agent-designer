---
name: 1c-ibcmd-pack
description: >-
  ibcmd: pack XML→.cf; быстрый dump/export и partial import XML в основную
  конфигурацию (без apply/КБД). Use when user asks ibcmd, pack cf, dump/export,
  load-changed via ibcmd, сравнить с designer-agent.
disable-model-invocation: true
---

# 1C ibcmd (pack + dump + load)

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
}
```

`type`/`name` — designer-agent; `dbms` — ibcmd.  
Опционально `ibcmd.dataDir` (дефолт `.1c/ibcmd-data`).

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

## Результат пользователю

Dump/load: каталог, list/файлы, `ELAPSED_SEC`, тип подключения (без паролей), явно «без apply / КБД».  
Pack: путь к `.cf`, credentials да/нет.
