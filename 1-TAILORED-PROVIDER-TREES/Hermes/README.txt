HERMES COST-OPTIMIZED CONFIG — 2026-08-18

What was changed:
- Main DeepSeek V4 Flash reasoning: xhigh -> high.
- Main max_turns: 500 -> 350 as a runaway-spend ceiling.
- Tool-loop hard stop enabled for repeated no-progress failures.
- Compression absolute trigger: 250,000 tokens.
- Lean tail mode enabled.
- No-LLM proactive tool-result pruning at 48,000 tokens.
- Idle compaction after 30 minutes.
- Auxiliary LLM tasks moved to Dots3-Note Preview :free.
- Automatic title generation disabled.
- Delegated subagent max iterations: 250 -> 50.
- Delegation concurrency: 2; nesting depth: 1.
- Large read limit: 80,000 chars.
- Terminal/tool output cap: 30,000 chars.
- Hook output spill cap: 8,000 chars.
- Existing provider routing remains price-first with require_parameters=true.
- Existing skills, MCP servers, hooks, memory, security, and platform toolsets were preserved.

Important:
Dots3-Note Preview :free has a 512K context window. The compressor now triggers at 250K,
so the free summarizer has enough room for the compaction payload. If the free auxiliary
endpoint is unavailable, Hermes' normal auxiliary fallback behavior can fall back to the
main model.

Install:
1. Replace config.yaml from this folder in %LOCALAPPDATA%\hermes\config.yaml.
2. Run APPLY-HERMES-COST-OPTIMIZATION.ps1.
3. Fully restart Hermes.
4. To undo, run RESTORE-LATEST-HERMES-BACKUP.ps1.

The installer backs up the current %LOCALAPPDATA%\hermes\config.yaml and profile.yaml first.
