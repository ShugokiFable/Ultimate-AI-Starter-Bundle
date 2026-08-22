r"""Measure what an MCP server can actually do WITHOUT credentials.

Why this exists
---------------
Through 7.9.8 the catalog said of firecrawl-mcp:

    "scrape/search/interact work on the keyless hosted tier;
     crawl/map/agent/extract need a key."

Two of those five claims were false. `interact` answers "Unauthorized: API key
is required", and `extract` is not key-gated at all -- it is deprecated and
removed from the MCP surface. Nobody had called the tools; the note was written
from the vendor's marketing page and then aged.

So the note is generated now. This calls EVERY tool the server advertises, with
the credential environment scrubbed, and classifies each result into four
buckets that are deliberately kept apart:

    KEYLESS     the call succeeded with no credentials
    NEEDS_KEY   the service answered unauthorized / key required
    DEPRECATED  the server says the tool is gone
    UNVERIFIED  the call never reached auth (bad arguments, timeout)

UNVERIFIED is the important one. Folding it into KEYLESS is exactly how a
capability map becomes confidently wrong, and a first cut of this script did
precisely that: nine tools failed argument validation and were counted as
working keyless.

Arguments are derived from each tool's own inputSchema, so a schema change
upstream does not silently turn into a false verdict.

Usage
-----
    python TOOLS/measure_mcp_capability.py "npx -y firecrawl-mcp@3.24.0" firecrawl-mcp

Writes BUNDLED-TOOLS/capability-records/<id>.json.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "BUNDLED-TOOLS", "capability-records")

SAMPLE_URL = "https://modelcontextprotocol.io"
SAMPLE_PAGE = "https://modelcontextprotocol.io/docs/getting-started/intro"
SAMPLE_ID = "00000000-0000-0000-0000-000000000000"

# Anything matching these is removed from the child's environment, so the
# measurement describes a machine with no accounts rather than this one.
CRED_HINTS = ("FIRECRAWL", "NOUS", "EXA", "TAVILY", "PARALLEL", "SERPER",
              "BRAVE", "SEARXNG", "KEENABLE", "BROWSERBASE", "SERPAPI",
              "PERPLEXITY", "OPENAI", "ANTHROPIC")

AUTH_MARKERS = ("api key", "unauthorized", "payment required",
                "insufficient credits", "authentication", "forbidden")
GONE_MARKERS = ("deprecated", "no longer", "unavailable through mcp", "removed")
# Checked BEFORE the auth markers, and the ordering is the whole point.
# firecrawl's throttle message is "The free daily limit for this network has
# been reached... To continue now: ... update the Firecrawl server entry so its
# URL is ...oauth...", which contains auth words and would otherwise be filed as
# NEEDS_KEY. That misreading turns a working keyless tool into a documented
# false negative -- it is how the first run of this script contradicted a
# correct measurement taken twenty minutes earlier.
THROTTLE_MARKERS = ("free daily limit", "rate limit", "rate-limit", "too many requests",
                    "429", "quota exceeded", "try again in", "slow down")


def sample_value(tool_name: str, prop: str, spec: dict):
    """A well-formed value for one schema property."""
    t = spec.get("type")
    if isinstance(t, list):
        t = t[0] if t else None
    low = prop.lower()
    if spec.get("enum"):
        return spec["enum"][0]
    if t == "array":
        item = spec.get("items") or {}
        return [sample_value(tool_name, prop, item)] if item else [SAMPLE_PAGE]
    if t in ("integer", "number"):
        return 2
    if t == "boolean":
        return False
    if t == "object":
        return {}
    if "url" in low:
        return SAMPLE_PAGE if ("scrape" in tool_name or "parse" in tool_name) else SAMPLE_URL
    if low in ("id", "jobid", "monitorid", "crawlid", "agentid", "sessionid"):
        return SAMPLE_ID
    if "schedule" in low:
        return "daily"
    return "model context protocol"


def measure(command: str, component_id: str, timeout: int = 90) -> dict:
    env = {k: v for k, v in os.environ.items()
           if not any(h in k.upper() for h in CRED_HINTS)}
    proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, shell=True, text=True,
                            encoding="utf-8", bufsize=1, env=env)
    lines: list = []
    threading.Thread(target=lambda: [lines.append(l) for l in proc.stdout],
                     daemon=True).start()

    def send(obj):
        proc.stdin.write(json.dumps(obj) + "\n")
        proc.stdin.flush()

    def wait(msg_id, budget=timeout):
        end = time.time() + budget
        while time.time() < end:
            for line in list(lines):
                try:
                    m = json.loads(line)
                except Exception:
                    continue
                if m.get("id") == msg_id:
                    return m
            time.sleep(0.3)
        return None

    send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
          "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                     "clientInfo": {"name": "uabs-capability", "version": "1"}}})
    time.sleep(4)
    send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
    send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
    listed = wait(2)
    if not listed:
        proc.kill()
        raise SystemExit("%s: no tools/list response" % component_id)

    tools = listed["result"]["tools"]
    record = {
        "component": component_id,
        "command": command,
        "tested_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "credentials": "none (scrubbed: %s)" % ", ".join(CRED_HINTS),
        "tools": len(tools),
        "schema_bytes": len(json.dumps(tools, separators=(",", ":"))),
        "keyless": [], "needs_key": [], "rate_limited": [], "deprecated": [],
        "unverified": {},
    }

    for offset, tool in enumerate(tools, start=200):
        name = tool["name"]
        schema = tool.get("inputSchema") or {}
        props = schema.get("properties") or {}
        required = schema.get("required") or list(props)[:1]
        args = {p: sample_value(name, p, props[p]) for p in required if p in props}
        # Some tools accept several mutually exclusive shapes; give the common
        # free-text one so validation does not mask the auth answer.
        if not args and "prompt" in props:
            args["prompt"] = "model context protocol"

        send({"jsonrpc": "2.0", "id": offset, "method": "tools/call",
              "params": {"name": name, "arguments": args}})
        reply = wait(offset)
        if reply is None:
            record["unverified"][name] = "timeout"
            continue

        err = reply.get("error")
        res = reply.get("result") or {}
        text = ""
        try:
            text = (res.get("content") or [{}])[0].get("text", "") or ""
        except Exception:
            text = ""
        blob = (text + " " + json.dumps(err or res)).lower()
        failed = bool(err) or bool(res.get("isError"))

        if not failed:
            record["keyless"].append(name)
        elif any(g in blob for g in GONE_MARKERS):
            record["deprecated"].append(name)
        elif any(t in blob for t in THROTTLE_MARKERS):
            # Throttled means the tool IS keyless and the free allowance is
            # spent -- the opposite conclusion from "needs a key".
            record["rate_limited"].append(name)
        elif any(a in blob for a in AUTH_MARKERS):
            record["needs_key"].append(name)
        else:
            record["unverified"][name] = (text or json.dumps(err or res))[:160].replace("\n", " ")

    proc.kill()
    return record


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    command, component_id = sys.argv[1], sys.argv[2]
    record = measure(command, component_id)

    print("%s -- %d tools, %d schema bytes, no credentials\n"
          % (component_id, record["tools"], record["schema_bytes"]))
    for bucket in ("keyless", "rate_limited", "needs_key", "deprecated"):
        names = record[bucket]
        print("%-11s %2d  %s" % (bucket.upper(), len(names), ", ".join(names) or "-"))
    print("%-11s %2d  %s" % ("UNVERIFIED", len(record["unverified"]),
                             ", ".join(record["unverified"]) or "-"))
    if record["unverified"]:
        print("\n  UNVERIFIED is not a synonym for keyless. Each of these never")
        print("  reached the auth check, so nothing is known about it:")
        for k, v in record["unverified"].items():
            print("    %-32s %s" % (k, v[:90]))

    os.makedirs(OUT_DIR, exist_ok=True)
    dest = os.path.join(OUT_DIR, component_id + ".json")
    with open(dest, "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2)
        fh.write("\n")
    print("\nwrote %s" % os.path.relpath(dest, ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
