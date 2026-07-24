#!/usr/bin/env python3
"""SSH client for 1C Designer agent mode (persistent invoke_shell)."""
from __future__ import annotations

import argparse
import re
import socket
import sys
import time
from pathlib import Path


def require_paramiko():
    try:
        import paramiko
    except ImportError as exc:
        raise SystemExit("Install paramiko: pip install paramiko") from exc
    return paramiko


def wait_port(host: str, port: int, timeout: float) -> None:
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            with socket.create_connection((host, port), timeout=2):
                return
        except OSError as exc:
            last = exc
            time.sleep(0.4)
    raise SystemExit(f"Agent port {host}:{port} not open: {last}")


def read_available(channel, idle: float = 0.5, hard_timeout: float = 3600.0) -> str:
    buf: list[str] = []
    started = time.time()
    last = time.time()
    while True:
        if channel.recv_ready():
            chunk = channel.recv(65535)
            if not chunk:
                break
            text = chunk.decode("utf-8", errors="replace")
            buf.append(text)
            sys.stdout.write(text)
            sys.stdout.flush()
            last = time.time()
            continue
        if channel.exit_status_ready():
            break
        now = time.time()
        if buf and (now - last) >= idle:
            break
        if (now - started) >= hard_timeout:
            break
        time.sleep(0.05)
    return "".join(buf)


SUCCESS_RE = re.compile(
    r'"type"\s*:\s*"success"|операция завершена|Operation completed',
    re.IGNORECASE,
)
ERROR_RE = re.compile(
    r'"type"\s*:\s*"error"|операция не выполнена|unknown command',
    re.IGNORECASE,
)


def _marker_updated(marker: Path, marker_before: float | None) -> bool:
    if not marker.exists():
        return False
    if marker_before is None:
        return True
    return marker.stat().st_mtime > marker_before


def wait_success_or_marker(
    channel,
    marker: Path | None,
    marker_before: float | None,
    long_op: bool,
    timeout: float,
    stable_sec: float = 5.0,
    eof_ok: bool = False,
) -> str:
    """Read until success JSON/text, or dump marker file settles.

    eof_ok: for common shutdown the agent closes the SSH transport; treat EOF as done.
    """
    buf: list[str] = []
    started = time.time()
    last_data = time.time()
    last_cdi_size = -1
    cdi_stable_since: float | None = None

    while True:
        if channel.recv_ready():
            chunk = channel.recv(65535)
            if not chunk:
                if eof_ok:
                    print("\nEOF_OK (channel closed)", flush=True)
                    return "".join(buf)
            else:
                text = chunk.decode("utf-8", errors="replace")
                buf.append(text)
                sys.stdout.write(text)
                sys.stdout.flush()
                last_data = time.time()
                joined = "".join(buf)
                if ERROR_RE.search(joined) and not eof_ok:
                    raise SystemExit(f"Agent error:\n{joined}")
                if SUCCESS_RE.search(joined):
                    # Long dump/load: if marker given, wait until it updates; else success is enough.
                    if not long_op:
                        return joined
                    if marker is None:
                        print("\nSUCCESS (no marker)", flush=True)
                        return joined
                    if _marker_updated(marker, marker_before):
                        print(f"\nSUCCESS+MARKER {marker}", flush=True)
                        return joined

        # Agent dropped the session (typical after common shutdown).
        if eof_ok and (
            channel.closed
            or channel.exit_status_ready()
            or not channel.get_transport()
            or not channel.get_transport().is_active()
        ):
            print("\nEOF_OK (session closed)", flush=True)
            return "".join(buf)

        joined = "".join(buf)
        if long_op and marker is not None and _marker_updated(marker, marker_before):
            cdi = marker.parent / "ConfigDumpInfo.xml"
            if cdi.exists():
                size = cdi.stat().st_size
                now = time.time()
                if size > 0 and size == last_cdi_size:
                    if cdi_stable_since is None:
                        cdi_stable_since = now
                    elif (now - cdi_stable_since) >= stable_sec:
                        time.sleep(0.5)
                        if channel.recv_ready():
                            extra = channel.recv(65535).decode("utf-8", errors="replace")
                            buf.append(extra)
                            sys.stdout.write(extra)
                            sys.stdout.flush()
                        print(f"\nMARKER_STABLE {cdi} ({size} bytes, {stable_sec}s)", flush=True)
                        return "".join(buf)
                else:
                    last_cdi_size = size
                    cdi_stable_since = None

        if channel.exit_status_ready():
            if eof_ok:
                print("\nEOF_OK (exit_status)", flush=True)
                return "".join(buf)
            break
        if (time.time() - started) >= timeout:
            if eof_ok:
                print(f"\nEOF_OK (timeout {timeout}s after shutdown)", flush=True)
                return "".join(buf)
            raise SystemExit(f"Timeout waiting for command result:\n{joined}")
        # short ops: idle after any output
        if (not long_op) and buf and (time.time() - last_data) >= 1.2:
            if SUCCESS_RE.search(joined) or '"body"' in joined or "designer>" in joined:
                return joined
        time.sleep(0.1)

    return "".join(buf)


def run(
    host: str,
    port: int,
    user: str,
    password: str,
    commands: list[str],
    marker: Path | None,
    connect_timeout: float,
) -> int:
    paramiko = require_paramiko()
    wait_port(host, port, connect_timeout)

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        hostname=host,
        port=port,
        username=user,
        password=password,
        allow_agent=False,
        look_for_keys=False,
        timeout=connect_timeout,
    )

    # 1C Designer agent often refuses PTY; open shell without get_pty.
    transport = client.get_transport()
    channel = transport.open_session()
    channel.set_combine_stderr(True)
    channel.invoke_shell()
    time.sleep(0.5)
    banner = read_available(channel, idle=0.6, hard_timeout=30)
    if not re.search(r"designer>|1C:Enterprise|1C Designer Shell", banner, re.I):
        # read a bit more
        banner += read_available(channel, idle=1.0, hard_timeout=15)
    if not re.search(r"designer>|1C:Enterprise|1C Designer Shell", banner, re.I):
        client.close()
        raise SystemExit(f"No designer shell banner:\n{banner}")

    setup = [
        "options set --show-prompt=no",
        "options set --output-format=json",
    ]
    all_cmds = setup + commands

    try:
        for cmd in all_cmds:
            print(f"\n>>> {cmd}", flush=True)
            marker_before = None
            long_op = bool(
                re.search(
                    r"dump-config-to-files|load-config-from-files|update-db-cfg",
                    cmd,
                )
            )
            if long_op and marker is not None and marker.exists():
                marker_before = marker.stat().st_mtime
            else:
                marker_before = None

            # Drain leftovers from previous command before sending.
            time.sleep(0.15)
            while channel.recv_ready():
                _ = channel.recv(65535)

            channel.send(cmd + "\n")
            eof_ok = bool(re.search(r"common\s+shutdown", cmd, re.I))
            if long_op:
                timeout = 36000.0
            elif eof_ok:
                timeout = 8.0
            else:
                timeout = 120.0
            out = wait_success_or_marker(
                channel,
                marker if long_op else None,
                marker_before,
                long_op,
                timeout,
                eof_ok=eof_ok,
            )
            if eof_ok:
                # Agent is going down; no further commands.
                break
            if long_op and marker is not None:
                if not marker.exists():
                    raise SystemExit(f"Dump reported success but marker missing: {marker}")
                if marker_before is not None and marker.stat().st_mtime <= marker_before:
                    raise SystemExit(
                        f"Dump reported success but marker mtime unchanged: {marker}"
                    )
    finally:
        try:
            channel.close()
        except Exception:
            pass
        client.close()

    return 0


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=1543)
    p.add_argument("--user", required=True)
    p.add_argument("--password", default="")
    p.add_argument("--commands-file", required=True)
    p.add_argument("--marker-file", default="")
    p.add_argument("--connect-timeout", type=float, default=40)
    args = p.parse_args()

    commands = [
        ln.strip().lstrip("\ufeff")
        for ln in Path(args.commands_file).read_text(encoding="utf-8-sig").splitlines()
        if ln.strip().lstrip("\ufeff") and not ln.strip().lstrip("\ufeff").startswith("#")
    ]
    if not commands:
        raise SystemExit("No commands in commands file")

    marker = Path(args.marker_file) if args.marker_file else None
    return run(
        host=args.host,
        port=args.port,
        user=args.user,
        password=args.password,
        commands=commands,
        marker=marker,
        connect_timeout=args.connect_timeout,
    )


if __name__ == "__main__":
    sys.exit(main())
