# Plan

1. [complete] Publish and install the validated 5.1.1 bridge release.
2. [complete] Reproduce Hermes' false-success registrar behavior against the
   real client: cancelled tool-enable prompts and missing-server tests returned
   exit code zero.
3. [complete] Deliver 5.1.2 with explicit tool enablement, output-based
   Hermes connection verification, full validation, release, and deployment.
4. [complete] Deliver 5.1.3 with idempotent release publication, a green tag
   workflow, and an exact-version active installation folder.
5. [complete] Deliver 5.1.5 so Claude Code 2026-07-28 can call Forge tools:
   `tools/call` always carries `resultType: "complete"`.
6. [complete] Deliver 5.2.0 so a fresh install cannot recreate a Documents
   copy, and so Register-MCP will not wedge Grok at 8 running servers.
