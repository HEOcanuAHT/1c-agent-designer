# Minimal stdio MCP when bsl-ctx sqlite is not built yet.
# Stdlib only. JSON-RPC newline-delimited. Logs -> stderr.
from __future__ import annotations

import argparse
import json
import sys


TOOLS = [
    {
        "name": "platform_info",
        "description": "Syntax-helper status: platform version, DB path, whether the index exists.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "search",
        "description": "Search platform API. Requires indexed sqlite (run /1c-syntax-index).",
        "inputSchema": {
            "type": "object",
            "properties": {"query": {"type": "string"}},
            "required": ["query"],
        },
    },
    {
        "name": "describe",
        "description": "Describe a platform type or member. Requires indexed sqlite.",
        "inputSchema": {
            "type": "object",
            "properties": {"name": {"type": "string"}, "ref": {"type": "string"}},
        },
    },
    {
        "name": "members",
        "description": "List members of a platform type. Requires indexed sqlite.",
        "inputSchema": {
            "type": "object",
            "properties": {"name": {"type": "string"}, "ref": {"type": "string"}},
        },
    },
    {
        "name": "signature",
        "description": "Method/constructor signatures. Requires indexed sqlite.",
        "inputSchema": {
            "type": "object",
            "properties": {"name": {"type": "string"}, "ref": {"type": "string"}},
        },
    },
    {
        "name": "relations",
        "description": "Type relations. Requires indexed sqlite.",
        "inputSchema": {
            "type": "object",
            "properties": {"name": {"type": "string"}, "ref": {"type": "string"}},
        },
    },
]


def missing_payload(platform: str, compat: str, project_root: str) -> dict:
    return {
        "ok": False,
        "code": "DB_MISSING",
        "platform": platform or None,
        "compatTarget": compat or None,
        "projectRoot": project_root or None,
        "hint": "Run /1c-syntax-index (Build-1cSyntaxDb.ps1 -ProjectRoot <workspace>). Needs uv + platform shcntx_ru.hbk.",
    }


def send(msg: dict) -> None:
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def result_text(req_id, text: str, is_error: bool = False) -> dict:
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "result": {
            "content": [{"type": "text", "text": text}],
            "isError": is_error,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default="")
    parser.add_argument("--platform", default="")
    parser.add_argument("--compat", default="")
    args = parser.parse_args()
    payload = missing_payload(args.platform, args.compat, args.project_root)
    payload_json = json.dumps(payload, ensure_ascii=False, indent=2)

    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        method = msg.get("method")
        req_id = msg.get("id")
        if method == "initialize":
            client_pv = (msg.get("params") or {}).get("protocolVersion") or "2024-11-05"
            send(
                {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "protocolVersion": client_pv,
                        "capabilities": {"tools": {}},
                        "serverInfo": {"name": "bsl-syntax-stub", "version": "0.1.0"},
                    },
                }
            )
        elif method == "notifications/initialized" or method == "initialized":
            continue
        elif method == "ping":
            send({"jsonrpc": "2.0", "id": req_id, "result": {}})
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": req_id, "result": {"tools": TOOLS}})
        elif method == "tools/call":
            send(result_text(req_id, payload_json, is_error=True))
        elif req_id is not None:
            send(
                {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32601, "message": f"Method not found: {method}"},
                }
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
