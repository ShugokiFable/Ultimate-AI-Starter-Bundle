"""Opt-in real Codex boundary check; isolated home, no login or model request.

Run: python TESTS/test_codex_native_profiles.py --codex <absolute codex.exe>
The app-server methods are from codex-cli 0.152.0's generated protocol schema.
"""
import argparse
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "TOOLS"))
from mcp_handshake import _stop_tree


def fixture_server():
    for line in sys.stdin:
        msg = json.loads(line)
        method = msg.get("method")
        if "id" not in msg:
            continue
        if method == "initialize":
            result = {"protocolVersion": msg["params"]["protocolVersion"],
                      "capabilities": {"tools": {}}, "serverInfo": {"name": "uabs-fixture", "version": "1"}}
        elif method == "tools/list":
            result = {"tools": [{"name": name, "description": "Harmless fixture",
                                  "inputSchema": {"type": "object", "properties": {}}}
                                 for name in ("read", "other", "hidden")]}
        elif method == "tools/call":
            result = {"content": [{"type": "text", "text": "fixture-ok"}]}
        else:
            result = {}
        print(json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": result}), flush=True)


def run(exe):
    with tempfile.TemporaryDirectory(prefix="uabs-native-scope-") as tmp:
        root = Path(tmp)
        home, project, other = root / "codex-home", root / "project with spaces", root / "other"
        for p in (home, project / ".codex", other, root / "local", root / "roaming"):
            p.mkdir(parents=True)
        # Deliberately exclude credentials and provider configuration from the child.
        env = {k: v for k, v in os.environ.items()
               if k.upper() in ("PATH", "SYSTEMROOT", "COMSPEC", "PATHEXT", "TEMP", "TMP")}
        env.update(CODEX_HOME=str(home), USERPROFILE=str(root), HOME=str(root),
                   LOCALAPPDATA=str(root / "local"), APPDATA=str(root / "roaming"))
        env["PATH"] = str(Path(exe).parent) + os.pathsep + env.get("PATH", "")
        env["SKYRIM_FORGE_PYTHON"] = sys.executable
        config = (f'[mcp_servers.uabs_fixture]\ncommand = {json.dumps(sys.executable)}\n'
                  f'args = {json.dumps([str(Path(__file__).resolve()), "--serve"])}\n'
                  'enabled_tools = ["read", "other"]\ndisabled_tools = ["other"]\n')
        target = project / ".codex/config.toml"
        target.write_text(config, encoding="utf-8")
        for trust in ("untrusted", "trusted"):
            (home / "config.toml").write_text(
                f'[projects.{json.dumps(str(project))}]\ntrust_level = "{trust}"\n', encoding="utf-8")
            for cwd in (project, other):
                result = subprocess.run([exe, "mcp", "list", "--json"], cwd=cwd, env=env,
                                        capture_output=True, text=True, timeout=20, check=True)
                names = {s["name"] for s in json.loads(result.stdout)}
                assert ("uabs_fixture" in names) == (trust == "trusted" and cwd == project), (trust, cwd, names)
            if os.name == "nt":
                diagnostic = subprocess.run(
                    ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                     str(ROOT / "TOOLS/Test-McpHandshake.ps1"), "-Provider", "Codex",
                     "-Path", str(project), "-Name", "uabs_fixture", "-RequireMatch"],
                    cwd=other, env=env, capture_output=True, text=True, timeout=45)
                assert diagnostic.returncode == (0 if trust == "trusted" else 1), diagnostic.stdout + diagnostic.stderr
                if trust == "trusted":
                    assert "3 advertised tools" in diagnostic.stdout, diagnostic.stdout
                else:
                    assert "No matching servers" in diagnostic.stdout, diagnostic.stdout
        get = subprocess.run([exe, "mcp", "get", "uabs_fixture", "--json"], cwd=project, env=env,
                             capture_output=True, text=True, timeout=20, check=True)
        entry = json.loads(get.stdout)
        assert entry["enabled_tools"] == ["read", "other"] and entry["disabled_tools"] == ["other"]
        proc = subprocess.Popen([exe, "app-server", "--stdio"], cwd=project, env=env,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                text=True, encoding="utf-8", creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        messages = queue.Queue()
        def read():
            for line in proc.stdout:
                messages.put(json.loads(line))
        threading.Thread(target=read, daemon=True).start()
        seq = 0
        def request(method, params):
            nonlocal seq
            seq += 1
            proc.stdin.write(json.dumps({"id": seq, "method": method, "params": params}) + "\n")
            proc.stdin.flush()
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                item = messages.get(timeout=max(0.01, deadline - time.monotonic()))
                if item.get("id") == seq:
                    assert "error" not in item, item
                    return item["result"]
            raise TimeoutError(method)
        try:
            request("initialize", {"clientInfo": {"name": "uabs-native-test", "version": "1"},
                                   "capabilities": {"experimentalApi": True}})
            proc.stdin.write('{"method":"initialized"}\n')
            proc.stdin.flush()
            thread = request("thread/start", {"cwd": str(project), "ephemeral": True})["thread"]["id"]
            status = request("mcpServerStatus/list", {"threadId": thread})
            server = next(s for s in status["data"] if s["name"] == "uabs_fixture")
            assert set(server["tools"]) == {"read"}, server
            result = request("mcpServer/tool/call", {"threadId": thread, "server": "uabs_fixture", "tool": "read", "arguments": {}})
            assert "fixture-ok" in json.dumps(result), result
        finally:
            proc.stdin.close()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                _stop_tree(proc)
            proc.stdout.close()
        assert target.read_text(encoding="utf-8") == config, "Native checks changed project configuration"
    print("PASS: Codex native trusted/untrusted scope, unrelated folder, tool filters, harmless call and cleanup; no model request")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--codex")
    parser.add_argument("--serve", action="store_true")
    args = parser.parse_args()
    if args.serve:
        fixture_server()
    elif args.codex:
        run(args.codex)
    else:
        parser.error("--codex must name the real executable; this test never silently skips")
