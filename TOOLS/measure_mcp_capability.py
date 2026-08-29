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

# The child gets an ALLOWLIST, not a blacklist.
#
# This was a list of vendor names to strip, which meant every credential nobody
# had thought of survived -- there was no GITHUB, TOKEN, KEY, SECRET or PAT in
# it. This script calls EVERY tool a server advertises with synthesized
# arguments. Against github-mcp-server with a live token that is
# create_pull_request, merge_pull_request, push_files and delete_file. A
# measurement tool must not be one typo away from writing to someone's repo.
#
# Only what a process needs to start survives. Anything else, credential or not,
# is dropped: an unknown variable cannot authenticate anything.
ENV_ALLOW = (
    "PATH", "PATHEXT", "SYSTEMROOT", "WINDIR", "COMSPEC", "TEMP", "TMP",
    "APPDATA", "LOCALAPPDATA", "PROGRAMFILES", "PROGRAMFILES(X86)",
    "PROGRAMDATA", "HOMEDRIVE", "HOMEPATH", "USERPROFILE", "SYSTEMDRIVE",
    "NUMBER_OF_PROCESSORS", "PROCESSOR_ARCHITECTURE", "OS", "NODE_PATH",
    "NVM_HOME", "NVM_SYMLINK", "PYTHONIOENCODING", "PYTHONUTF8",
)

# Names that change state somewhere. Skipped unless --include-mutating, because
# "measure what this server can do" must never mean "find out by doing it".
MUTATING_HINTS = (
    "create", "update", "delete", "remove", "write", "push", "merge", "close",
    "add", "set", "post", "send", "upload", "fork", "rename", "move", "start",
    "stop", "cancel", "run", "execute", "install", "publish", "revoke",
    # Added when windows-mcp entered the catalog. Every verb above is one a WEB
    # API would use. A server that drives the machine changes state in a
    # different vocabulary and none of it was here, so this sweep would have
    # called Click, Type, Shortcut, PowerShell, Registry, Clipboard, MultiEdit
    # and Process against the operator's live desktop, with arguments
    # synthesized from each schema. Skipping them is the floor, not the fix.
    "click", "type", "press", "key", "shortcut", "drag", "scroll", "shell",
    "registry", "clipboard", "edit", "select", "kill", "terminate", "restart",
    "launch", "open", "process", "notify", "notification",
)

# The line above is a BLOCKLIST of name fragments, and this file already knows
# what is wrong with those: the environment handling below was converted to an
# allowlist for exactly this reason. A blocklist fails open on the name nobody
# predicted, and two survive the extension even against a server whose tools we
# have read -- windows-mcp's `App` launches programs and `FileSystem` writes
# files. Neither contains a hint, and neither should ever be called blind.
#
# So a server that drives the machine is not swept at all. WHICH servers those
# are is a catalog fact rather than a guess about spelling, and the refusal
# points at the tool that answers the same question without calling anything.
CONTROLS_MACHINE_NOTE = """%s drives the local machine: keyboard, mouse, shell,
registry or filesystem. This sweep calls EVERY tool a server advertises with
arguments synthesized from its schema, which against that surface means typing
into whatever window has focus and running whatever PowerShell the sample
produces.

Nothing was called. For the numbers a profile decision actually needs -- tools,
schema bytes, tokens per turn -- use the tool that only reads:

    TOOLS\\Measure-McpSchemaCost.ps1 -Command '%s' -Name %s

To sweep it anyway, on a machine you accept will be driven, pass
--i-accept-desktop-control."""


def controls_machine(component_id):
    """True when CATALOG.json marks this component as driving the machine."""
    path = os.path.join(ROOT, "BUNDLED-TOOLS", "CATALOG.json")
    try:
        with open(path, encoding="utf-8") as fh:
            catalog = json.load(fh)
    except Exception:
        return False
    for component in catalog.get("components", []):
        if component.get("id") == component_id:
            return bool(component.get("controls_machine"))
    return False

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
THROTTLE_MARKERS = ("free daily limit", "rate limit", "rate-limit", "ratelimit",
                    "too many requests", "429", "quota exceeded", "try again in",
                    "slow down", "cap reached", "hourly_cap", "daily_cap",
                    "usage limit", "limit reached", "throttl", "retry-after")


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


def measure(command: str, component_id: str, timeout: int = 90,
            include_mutating: bool = False) -> dict:
    env = {k: v for k, v in os.environ.items() if k.upper() in ENV_ALLOW}
    proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, shell=True, text=True,
                            encoding="utf-8", bufsize=1, env=env)
    lines: list = []
    threading.Thread(target=lambda: [lines.append(l) for l in proc.stdout],
                     daemon=True).start()

    def send(obj):
        if proc.poll() is not None:
            raise SystemExit("%s: server exited (code %s) before the sweep finished"
                             % (component_id, proc.returncode))
        try:
            proc.stdin.write(json.dumps(obj) + "\n")
            proc.stdin.flush()
        except (OSError, ValueError) as exc:
            raise SystemExit("%s: cannot write to the server: %s" % (component_id, exc))

    def wait(msg_id, budget=timeout):
        end = time.time() + budget
        while time.time() < end:
            # A server that died mid-sweep used to burn the full budget on
            # every remaining tool -- 25 tools x 90s is 37 minutes producing a
            # record full of "timeout" that looks like data.
            if proc.poll() is not None:
                return None
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
        "credentials": "none (environment reduced to %d process variables)" % len(ENV_ALLOW),
        "tools": len(tools),
        "schema_bytes": len(json.dumps(tools, separators=(",", ":"))),
        "keyless": [], "needs_key": [], "rate_limited": [], "deprecated": [],
        "unverified": {}, "skipped_mutating": [],
        # A tool that answers "free daily limit reached" was REACHED without
        # credentials -- you cannot be throttled on a tier you cannot access.
        # So throttled tools are keyless-capable, and a sweep run inside a spent
        # quota window still establishes that, which is why this set exists
        # separately from `keyless` (that one means "worked right now").
        "keyless_capable": [],
    }

    for offset, tool in enumerate(tools, start=200):
        name = tool["name"]
        if not include_mutating and any(h in name.lower() for h in MUTATING_HINTS):
            record["skipped_mutating"].append(name)
            continue
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

        # The markers are consulted BEFORE trusting the absence of an error
        # flag. Plenty of servers report failures as plain content without
        # setting isError, and keying off `failed` alone filed those as KEYLESS
        # even when the text said "Unauthorized: API key is required" -- the
        # exact inversion this script exists to prevent, landing in the bucket
        # that looks safest.
        #
        # Order matters and is asserted by a release contract: DEPRECATED, then
        # THROTTLE, then AUTH. Firecrawl's daily-limit message recommends OAuth,
        # so auth-first would file a working keyless tool as needing a key.
        if any(g in blob for g in GONE_MARKERS):
            record["deprecated"].append(name)
        elif any(x in blob for x in THROTTLE_MARKERS):
            # Throttled means the tool IS keyless and the free allowance is
            # spent -- the opposite conclusion from "needs a key".
            record["rate_limited"].append(name)
        elif any(a in blob for a in AUTH_MARKERS):
            record["needs_key"].append(name)
        elif not failed:
            record["keyless"].append(name)
        else:
            record["unverified"][name] = (text or json.dumps(err or res))[:160].replace("\n", " ")

    record["keyless_capable"] = sorted(set(record["keyless"]) | set(record["rate_limited"]))
    record["provenance"] = (
        "Generated by TOOLS/measure_mcp_capability.py. `keyless` means the call "
        "succeeded during THIS sweep; `rate_limited` means it was reached without "
        "credentials and the free allowance was spent. `keyless_capable` is the "
        "union and is the set to compare against documentation -- a sweep run "
        "inside a spent quota window reports the same capability with a different "
        "split."
    )
    proc.kill()
    return record


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    command, component_id = sys.argv[1], sys.argv[2]
    include_mutating = "--include-mutating" in sys.argv[3:]
    # Before anything is called, not after.
    if controls_machine(component_id) and "--i-accept-desktop-control" not in sys.argv[3:]:
        print(CONTROLS_MACHINE_NOTE % (component_id, command, component_id))
        return 2
    record = measure(command, component_id, include_mutating=include_mutating)

    print("%s -- %d tools, %d schema bytes, no credentials\n"
          % (component_id, record["tools"], record["schema_bytes"]))
    for bucket in ("keyless", "rate_limited", "needs_key", "deprecated"):
        names = record[bucket]
        print("%-11s %2d  %s" % (bucket.upper(), len(names), ", ".join(names) or "-"))
    print("%-11s %2d  %s" % ("UNVERIFIED", len(record["unverified"]),
                             ", ".join(record["unverified"]) or "-"))
    if record["skipped_mutating"]:
        print("%-11s %2d  %s" % ("SKIPPED", len(record["skipped_mutating"]),
                                 ", ".join(record["skipped_mutating"])))
        print("  Not called: the name suggests it changes state. --include-mutating overrides.")
    if record["unverified"]:
        print("\n  UNVERIFIED is not a synonym for keyless. Each of these never")
        print("  reached the auth check, so nothing is known about it:")
        for k, v in record["unverified"].items():
            print("    %-32s %s" % (k, v[:90]))

    os.makedirs(OUT_DIR, exist_ok=True)
    dest = os.path.join(OUT_DIR, component_id + ".json")
    with open(dest, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(record, fh, indent=2)
        fh.write("\n")
    print("\nwrote %s" % os.path.relpath(dest, ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
