---
name: std-integrations
description: >-
  HTTP/REST/queues integrations patterns for 1C (timeouts, serialization, idempotency).
  Use when adding or reviewing external system integrations. No MCP required.
disable-model-invocation: true
---

# std-integrations — интеграции с внешними системами

Источник: адаптировано из [comol/ai_rules_1c](https://github.com/comol/ai_rules_1c). MCP-зависимости сняты.

<!--
Adapted from https://github.com/comol/ai_rules_1c (upstream tools often from Nikolay-Shirokov/cc-1c-skills).
MCP-only gates removed. Dump/load/EPF/CFE pack: template skills 1c-ibcmd-pack, 1c-designer-agent, 1c-external-*.
-->

# 1C Integrations with External Systems

Applies to integration code: HTTP services, REST clients, web services, file exchange, message queues, webhooks.

## 1. Before writing code

- Проверь готовое в БСП («Интернет-поддержка», «Обмен данными», «Получение файлов…», «Цифровая подпись») и в текущей конфе (Grep по `src/`).
- Перед самописным механизмом сверься со справкой платформы / ИТС (криптография, СистемаВзаимодействия, шина и т.п.).
- Явно согласуй контракт: method, URL, payload, auth, timeouts, retry, logging.
- Локальный прототип (curl/Postman) — только для отладки контракта; прод-код остаётся в BSL.
## 2. Long-running and blocking operations

- Network calls are potentially long-running. Run all integration operations in the background through the БСП **"Long-running operations"** subsystem (`ДлительныеОперации.ВыполнитьФункцию`), not through a direct `ФоновыеЗадания` call. See `std-platform-solutions §2 → "Long-running operations"`.
- On the client — no synchronous HTTP calls; use `НачатьВыполнение*` or an async wrapper (template — `std-platform-solutions §8 → "External components on the thin client"`).

## 3. HTTP client

- Use platform `HTTPСоединение` / `HTTPЗапрос` or the БСП wrapper. `КомпонентаHTTPСервисы` and third-party COM objects are forbidden (see `std-platform-solutions` / `std-architecture` → `docs/patterns.md`).
- Connection timeout and read timeout MUST be set **explicitly** — use values from ``.1c/project.json`` or configuration constants, not magic numbers in code.
- Any response code different from the expected one MUST be turned into a meaningful exception with `ПодробноеПредставлениеОшибки(ИнформацияОбОшибке())` written to the event log. See `std-logging`.

## 4. Serialization and data contract

- JSON — via platform `ЧтениеJSON` / `ЗаписьJSON` (or the equivalent БСП helper if your БСП version provides one — verify the exact name with `поиск по БСП (MCP optional)` / `справка платформы (MCP optional)` before use). Manual string assembly is forbidden.
- Numbers, dates and booleans must be validated separately: agree the date format with the receiving side (typically `ISO 8601`), specify decimal precision for numbers explicitly.
- For XML — `ЧтениеXML` / `ЗаписьXML` plus XSD validation when a schema is available. Manual string parsing is forbidden.

## 5. Security

- Credentials, tokens, API keys — only via **write-protected configuration constants** or the БСП "Безопасное хранение паролей" subsystem. Hardcoding is forbidden (`std-security`).
- Validate the token/session before each request; implement token refresh centrally.

## 6. Idempotency and retries

- Mutating requests must be idempotent on the 1C side: store the operation key in an information register and check status before resending.
- Retry policy: bounded number of attempts with exponential backoff. Infinite retry loops are forbidden.

## 7. Testing

- Verify the contract first manually (Postman, curl) on a test endpoint, then capture expected responses as examples in comments / documentation.
- For unit-level checks of parsing/serialization, write a minimal handler that does not depend on the network.

## 8. Documentation

For every new integration module record at the top (or in the metadata-object card): the external system, the contract (URL, method, format), the authentication scheme, the required roles, and a link to the requirements document.

Local out-of-1C prototyping (curl, Postman, ad-hoc scripts) is acceptable for contract debugging only. Production code stays in BSL — Python or other languages do not enter the repository.
