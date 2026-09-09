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


def probe(command: str, args: list[str], timeout: int, shell_command: str | None = None) -> dict:
    stderr = collections.deque(maxlen=3)
    messages: queue.Queue = queue.Queue()
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    argv = [command, *args]
    if shell_command is not None:
        if os.name != "nt":
            return {"ok": False, "reason": "shell_command is a Windows command line; use command/args on other systems"}
        # -Command is explicitly shell syntax. Do not feed it through
        # list2cmdline as an argument: its backslash-quoted quotes break cmd.exe.
        argv = subprocess.list2cmdline([os.environ["COMSPEC"]]) + ' /d /s /c "' + shell_command + '"'
    try:
        proc = subprocess.Popen(
            argv,
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
            if isinstance(message, dict) and message.get("id") == message_id:
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
        if not isinstance(initialized.get("result"), dict):
            return {"ok": False, "reason": "invalid initialize response"}

        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        tools, cursors, names = [], set(), set()
        params = {}
        for message_id in range(2, 102):
            send({"jsonrpc": "2.0", "id": message_id, "method": "tools/list", "params": params})
            listed = wait_for(message_id, deadline)
            if not listed:
                return {"ok": False, "reason": "initialized but never answered tools/list"}
            page = listed.get("result")
            if listed.get("error") or not isinstance(page, dict) or not isinstance(page.get("tools"), list):
                return {"ok": False, "reason": "invalid or error tools/list response"}
            for tool in page["tools"]:
                if (not isinstance(tool, dict) or not isinstance(tool.get("name"), str)
                        or not tool["name"] or tool["name"] in names
                        or not isinstance(tool.get("inputSchema"), dict)):
                    return {"ok": False, "reason": "invalid or duplicate tool definition"}
                names.add(tool["name"])
                tools.append(tool)
            cursor = page.get("nextCursor")
            if cursor is None:
                break
            if not isinstance(cursor, str) or not cursor or cursor in cursors:
                return {"ok": False, "reason": "invalid or repeated tools/list cursor"}
            cursors.add(cursor)
            params = {"cursor": cursor}
        else:
            return {"ok": False, "reason": "tools/list exceeded 100 pages"}
        result = initialized.get("result") or {}
        def json_bytes(value):
            return len(json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
        size = json_bytes(tools)
        return {
            "ok": True,
            "protocol": result.get("protocolVersion", ""),
            "server_name": (result.get("serverInfo") or {}).get("name", ""),
            "tool_count": len(tools),
            "schema_bytes": size,
            "schema_tokens_estimate": size / 4,
            "measurement_basis": "compact UTF-8 tools array; bytes/4 estimate, not prompt or billed tokens",
            "per_tool": [{"name": tool["name"], "bytes": json_bytes(tool)} for tool in tools],
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
    if result.get("ok") and result.get("tool_count") == 1 and result["schema_bytes"] == result["per_tool"][0]["bytes"] + 2:
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
    result = probe(spec["command"], list(spec.get("args") or []), int(spec.get("timeout") or 60), spec.get("shell_command"))
    print(json.dumps(result, separators=(",", ":")))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
