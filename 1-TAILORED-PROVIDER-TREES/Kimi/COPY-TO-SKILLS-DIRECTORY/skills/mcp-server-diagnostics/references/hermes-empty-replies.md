# Hermes "(empty)" assistant messages

Symptom: a chat bubble renders the literal placeholder `(empty)` in the Hermes
desktop app. The message exists in the transcript but its final text content is
blank. `(empty)` is not a string anywhere in Hermes source — it is the UI's
placeholder for an assistant message with no displayable text.

## Verified causes (from runtime source, Aug 2026)

1. **Model ends its turn after tool calls without emitting final text** — the
   most common "random" case. Tool calls go out, results come back, the model
   emits end-of-turn immediately instead of a text block. Sampling fluke; more
   frequent on fast/stealth models and long tool loops.
   **Agent-side prevention (the only lever we control): always close the turn
   with visible final prose after tool calls — never end the turn on tool
   results alone.**
2. **Provider returns an empty stream** — retried up to N times, then fails
   with "Provider returned an empty response stream after N+1 attempts"
   (`agent/chat_completion_helpers.py` ~L4946). Provider-side glitch.
3. **Reasoning-only / token-capped turn** — model produces only thinking or hits
   the cap before visible text; adapters emit an empty assistant item to satisfy
   protocol ordering (`agent/codex_responses_adapter.py` ~L646).
4. **Dead SSE stream leaves an empty assistant stub mid-transcript** — poisons
   later requests until healed; self-recovery at
   `agent/agent_runtime_helpers.py` ~L3603 ("Heal empty-content non-final
   messages"). Related checkpoint-poisoning history:
   `agent/conversation_loop.py` ~L331.

## Handling

- User sees occasional `(empty)` after tool-heavy work → cause #1; retry/resend
  the turn. If one specific model does it constantly, switch models.
- Cron/background jobs: scheduler marks them failed with "Agent completed but
  produced empty response (model error, timeout, or misconfiguration)"
  (`cron/scheduler.py` ~L6981).
- Source of truth lives in the installed app copy:
  `%USERPROFILE%\AppData\Local\hermes\hermes-agent\` — grep the error strings
  above rather than trusting line numbers (they drift between versions).
