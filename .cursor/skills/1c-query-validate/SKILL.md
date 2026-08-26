---
name: 1c-query-validate
description: >-
  COM-проверка языка запросов 1С (QuerySchema / FindParameters) на служебной
  .1c/ib-ext. Без ENTERPRISE / HTTP / расширения. Use when user asks
  проверяй запросы, validate query, валидируй запросы, or query-validate.mode is on.
disable-model-invocation: true
---

# Проверка языка запросов (COM)

Не путать с оформлением запросов (`std-queries`) и оптимизацией (`std-query-optimization`): здесь только **синтаксис/схема** через платформу.

Служебная ИБ та же, что у EPF/CFE (`.1c/ib-ext`, `1c-runtime/scripts/Common-ServiceIb.ps1`). Apply на служебной — только `-Action ensure` (`Get-ServiceIbCfg -AllowApply`). На боевую — никогда.

## Среда

Только **Windows** + платформа 1С (`ibcmd`, `V83.COMConnector`). Linux/macOS — вне scope.

## Кто запускает

Только **оркестратор**. `/implementer` тексты запросов пишет в файлы, скрипт не вызывает.

Режим агента (opt-in) — rule `1c-query-validate`: по умолчанию выкл.; «проверяй запросы» → `.1c/query-validate.mode=on`.

## Команды

`SkillHome` = каталог этого SKILL.md. `-ProjectRoot` = workspace. Без `-ExecutionPolicy Bypass`.

Два шага; **не** мешать ensure и validate в одной команде.

```powershell
# редко (ibcmd) — раз за сессию / после обновления src
powershell -NoProfile -File "<SkillHome>/scripts/Invoke-1cValidateQuery.ps1" -Action ensure -ProjectRoot "<workspace>"

# часто: без ibcmd, пачка в одном COM
powershell -NoProfile -File "<SkillHome>/scripts/Invoke-1cValidateQuery.ps1" -ReuseOnly -BatchDir .1c/qv-batch -ProjectRoot "<workspace>"
powershell -NoProfile -File "<SkillHome>/scripts/Invoke-1cValidateQuery.ps1" -ReuseOnly -QueryFile .1c/qv-batch/01.txt -ProjectRoot "<workspace>"
powershell -NoProfile -File "<SkillHome>/scripts/Invoke-1cValidateQuery.ps1" -Action health -ProjectRoot "<workspace>"
```

| Exit | Смысл |
|------|--------|
| `0` | все ок (`VALID=true` / `SUMMARY fail=0`) |
| `1` | ошибка языка запроса (`VALID=false`) |
| `2` | `NEED_ENSURE=true` — сначала `-Action ensure`, потом снова `-ReuseOnly` |

Не вызывать validate **без** `-ReuseOnly` в цикле агента (снова ibcmd → лишние Allow).

## Когда режим `on` (или разовая просьба)

1. Собрать новые/изменённые тексты в `.1c/qv-batch/*.txt` (UTF-8), не по одному вызову на каждый чих.
2. Один `-ReuseOnly -BatchDir` (если `NEED_ENSURE` → ensure → повтор).
3. При `VALID=false` — исправить и повторить пачку, пока `fail=0` (или спросить пользователя).
4. Не валидировать неизменённые куски; не гонять на стиль/комментарии.
5. Пользовательские `1cv8` не убивать (rule `1c-no-kill-user-1cv8`).
