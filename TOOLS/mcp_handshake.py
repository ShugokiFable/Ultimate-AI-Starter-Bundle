"""Bounded stdio MCP initialize + tools/list probe. Uses only the stdlib."""
from __future__ import annotations

import argparse
import base64
import collections
import json
import os
import queue
import subprocess
import sys
import threading
import time


def _stop_tree(proc: subprocess.Popen) -> None:
    if proc.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(proc.pid), "/T", "/F"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    else:
        proc.terminate()
    try:
        proc.wait(5)
    except subprocess.TimeoutExpired:
        proc.kill()


def probe(command: str, args: list[str], timeout: int) -> dict:
    stderr = collections.deque(maxlen=3)
    messages: queue.Queue = queue.Queue()
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    try:
        proc = subprocess.Popen(
            [command, *args],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            creationflags=flags,
        )
    except OSError as exc:
        return {"ok": False, "reason": f"could not start server: {exc}"}

    def read_stdout() -> None:
        assert proc.stdout is not None
        for line in proc.stdout:
            try:
                messages.put(json.loads(line))
            except (TypeError, ValueError):
                continue

    def read_stderr() -> None:
        assert proc.stderr is not None
        for line in proc.stderr:
            if line.strip():
                stderr.append(line.strip())

    threading.Thread(target=read_stdout, daemon=True).start()
    threading.Thread(target=read_stderr, daemon=True).start()

    def send(payload: dict) -> None:
        assert proc.stdin is not None
        proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        proc.stdin.flush()

    def wait_for(message_id: int, deadline: float):
        while time.monotonic() < deadline:
            if proc.poll() is not None and messages.empty():
                return None
            try:
                message = messages.get(timeout=min(0.2, deadline - time.monotonic()))
            except queue.Empty:
                continue
            if message.get("id") == message_id:
                return message
        return None

    try:
        deadline = time.monotonic() + timeout
        send(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {},
                    "clientInfo": {"name": "uabs-handshake", "version": "1.0"},
                },
            }
        )
        initialized = wait_for(1, deadline)
        if not initialized:
            reason = f"no initialize response within {timeout}s"
            if stderr:
                reason += "  [stderr: " + " | ".join(stderr) + "]"
            return {"ok": False, "reason": reason}
        if initialized.get("error"):
            return {"ok": False, "reason": "server returned error: " + json.dumps(initialized["error"], separators=(",", ":"))}

        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        listed = wait_for(2, deadline)
        if not listed:
            return {"ok": False, "reason": "initialized but never answered tools/list"}
        if listed.get("error"):
            return {"ok": False, "reason": "server returned error: " + json.dumps(listed["error"], separators=(",", ":"))}
        result = initialized.get("result") or {}
        tools = (listed.get("result") or {}).get("tools") or []
        return {
            "ok": True,
            "protocol": result.get("protocolVersion", ""),
            "server_name": (result.get("serverInfo") or {}).get("name", ""),
            "tool_count": len(tools),
        }
    except (BrokenPipeError, OSError, ValueError) as exc:
        return {"ok": False, "reason": f"MCP exchange failed: {exc}"}
    finally:
        _stop_tree(proc)


def selftest() -> int:
    child = (
        "import json,sys;"
        "a=json.loads(sys.stdin.readline());"
        "print(json.dumps({'jsonrpc':'2.0','id':a['id'],'result':{'protocolVersion':'2025-06-18','serverInfo':{'name':'fixture','version':'1'}}}),flush=True);"
        "sys.stdin.readline();b=json.loads(sys.stdin.readline());"
        "print(json.dumps({'jsonrpc':'2.0','id':b['id'],'result':{'tools':[{'name':'fixture','inputSchema':{'type':'object'}}]}}),flush=True);"
        "sys.stdin.readline()"
    )
    result = probe(sys.executable, ["-u", "-c", child], 10)
    if result.get("ok") and result.get("tool_count") == 1:
        print("MCP HANDSHAKE SELFTEST: PASS")
        return 0
    print("MCP HANDSHAKE SELFTEST: FAIL " + json.dumps(result, separators=(",", ":")))
    return 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", help="base64-encoded JSON: command, args, timeout")
    parser.add_argument("--selftest", action="store_true")
    ns = parser.parse_args()
    if ns.selftest:
        return selftest()
    if not ns.spec:
        parser.error("--spec is required")
    spec = json.loads(base64.b64decode(ns.spec).decode("utf-8"))
    result = probe(spec["command"], list(spec.get("args") or []), int(spec.get("timeout") or 60))
    print(json.dumps(result, separators=(",", ":")))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
