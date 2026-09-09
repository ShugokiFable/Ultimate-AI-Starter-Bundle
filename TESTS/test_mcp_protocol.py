"""Real stdio fixtures for schema measurement: no network or provider needed."""
import json
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "TOOLS"))
from mcp_handshake import probe


def serve(mode):
    for raw in sys.stdin.buffer:
        assert not raw.startswith(b"\xef\xbb\xbf"), "MCP frames must not carry a BOM"
        msg = json.loads(raw)
        if "id" not in msg:
            continue
        if msg["method"] == "initialize":
            result = {"protocolVersion": "2025-06-18", "serverInfo": {"name": "fixture"}}
            if mode == "bad-init":
                result = []
        else:
            tool = {"name": "caf\u00e9", "inputSchema": {"type": "object"}}
            result = {"tools": [] if mode == "empty" else [tool]}
            if mode == "paged":
                if msg["params"].get("cursor") == "next":
                    result["tools"][0]["name"] = "second"
                else:
                    result["nextCursor"] = "next"
            elif mode == "repeat":
                result = {"tools": [], "nextCursor": "repeat"}
            elif mode == "malformed":
                result = {"tools": {}}
            elif mode == "missing":
                result = {}
            elif mode == "duplicate":
                result["tools"] *= 2
        print(json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": result}), flush=True)


def run():
    for mode, count in (("empty", 0), ("single", 1), ("paged", 2),
                        ("repeat", None), ("malformed", None), ("missing", None),
                        ("duplicate", None), ("bad-init", None)):
        result = probe(sys.executable, [str(Path(__file__).resolve()), "--serve", mode], 5)
        assert result["ok"] == (count is not None), (mode, result)
        if count is not None:
            assert result["tool_count"] == count, result
            # Compact JSON array overhead: brackets plus commas, including [].
            assert result["schema_bytes"] == sum(t["bytes"] for t in result["per_tool"]) + 2 + max(0, count - 1)
            assert result["schema_tokens_estimate"] == result["schema_bytes"] / 4
            expected = [{"name": n, "inputSchema": {"type": "object"}}
                        for n in (("caf\u00e9", "second")[:count])]
            assert result["schema_bytes"] == len(json.dumps(expected, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
    if os.name == "nt":
        command = '"' + sys.executable + '" "' + str(Path(__file__).resolve()) + '" --serve single'
        result = probe(os.environ["COMSPEC"], [], 5, shell_command=command)
        assert result["ok"] and result["tool_count"] == 1, result
    print("PASS: strict UTF-8 MCP frames, zero/one/paginated schemas, invalid responses, cursor loops and Windows command quoting")


if __name__ == "__main__":
    if "--serve" in sys.argv:
        serve(sys.argv[-1])
    else:
        run()
