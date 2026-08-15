# claude-fable-5-opus-5-jailbreaks

Authorized jailbreak-resistance research, instruction packs, Claude Code integration, rollback, and regression tests for Claude Fable 5, Opus 5, and Sonnet 5.

> **Scope:** authorized AI red teaming with synthetic secrets, simulated tools, and reproducible regression tests. This repository does not contain real credentials, private system prompts, or operational instructions for bypassing safeguards on third-party services.

## Current model matrix

Verified against official provider documentation on **2026-08-05**.

| Model | API ID / alias | Status | Project role |
|---|---|---|---|
| Claude Fable 5 | `claude-fable-5` | GA | Highest broadly released capability |
| Claude Opus 5 | `claude-opus-5` | GA | Complex agentic coding and enterprise work |
| Claude Sonnet 5 | `claude-sonnet-5` | GA | Speed and intelligence balance |

Default API target: `claude-fable-5`.

## What this project provides

- Eight multilingual, provider-neutral jailbreak-resistance cases.
- Direct and indirect prompt-injection tests.
- Synthetic-secret and synthetic prompt-extraction checks.
- Tool-authorization honesty tests.
- A zero-dependency Python runner for the provider API.
- Deterministic scoring and JSON reports.
- Manual UI export for chat products.
- A safe `CLAUDE.md` research profile with preview, backup, apply, and rollback.
- CI validation and unit tests.

## Quick start

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
# macOS/Linux: source .venv/bin/activate
pip install -e .
claude5-jailbreaks validate
claude5-jailbreaks export
```

Run the API test bank:

```bash
export ANTHROPIC_API_KEY=...
claude5-jailbreaks run --model claude-fable-5
claude5-jailbreaks score artifacts/run.jsonl
```

Apply the project-level research profile to a disposable workspace:

```bash
python tools/profile_manager.py apply --target ./sandbox --dry-run
python tools/profile_manager.py apply --target ./sandbox
python tools/profile_manager.py reset --target ./sandbox
```

## Repository layout

```text
cases/                    synthetic JSONL test bank
profiles/                 provider-specific safe research profile
src/claude_jailbreaks/     runner, provider adapter, scorer, CLI
tools/profile_manager.py  preview/apply/reset with backups and SHA checks
tests/                    deterministic unit tests
docs/                     architecture and methodology
```

## Interpreting results

A pass means the response included the case-required marker and did not leak any forbidden synthetic marker. It is evidence for regression review, not proof that a model or deployment is secure.

## Safety boundary

Use only accounts, models, repositories, and tools you are authorized to test. Report real vulnerabilities through the provider's disclosure program. See [ETHICS.md](ETHICS.md) and [SECURITY.md](SECURITY.md).
