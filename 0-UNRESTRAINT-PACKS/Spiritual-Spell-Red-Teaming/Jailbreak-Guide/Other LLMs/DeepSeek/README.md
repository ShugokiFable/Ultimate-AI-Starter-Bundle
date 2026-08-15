# DeepSeek

**Censorship:** [★☆☆☆☆] 1/5 (with jailbreak) / [★★★★★★★★★☆] 9/10 (raw — Gemini-style external filter on app; API is uncensored)

Open source has had a peak year — **DeepSeek V4** (released April 24, 2026, Preview) is the latest. V4-Pro flagship + V4-Flash efficient variant, both with 1M context as standard, MIT-licensed, full weights on HuggingFace. Via API it's completely uncensored.

*Last updated: April 2026*

---

## Models

| Model | Parameters | Context Window | Released | License |
|-------|-----------|----------------|----------|---------|
| **DeepSeek V4-Pro** | 1.6T total / 49B active (MoE) | 1M | Apr 24, 2026 | MIT |
| **DeepSeek V4-Flash** | 284B total / 13B active (MoE) | 1M | Apr 24, 2026 | MIT |
| **DeepSeek V3.2** | — | 256K | Dec 2025 | MIT |
| **DeepSeek V3.1** | 671B (37B activated) | 128K | Aug 2025 | MIT |
| **DeepSeek-R1-0528** | 671B (37B activated) | 128K | May 2025 | MIT |
| **DeepSeek-R1-Qwen3-8B** | 8B (distilled) | 128K | 2025 | MIT |

### DeepSeek V4 Highlights

- **Architecture:** MoE + MLA/HCA + CSA + mHC + MTP (depth 1); FP4+FP8 mixed precision
- **Efficiency vs V3.2:** V4-Pro uses 27% FLOPs / 10% KV cache; V4-Flash uses 10% FLOPs / 7% KV cache
- **Reasoning Modes:** Non-Think, Think High, Think Max
- **Benchmarks (V4-Pro):** SWE-Bench Verified 80.6%, LiveCodeBench 93.5%, Codeforces 3206 (~23rd among human contestants), MMLU-Pro 87.5%, HLE no-tools 37.7%, Putnam 2025 120/120 (V4-Pro-Max hybrid pipeline)
- **API Pricing (direct):** Pro ~$1.66/M input, ~$3.31/M output; Flash ~$0.14/M input, ~$0.28/M output
- **Cost vs Claude Opus 4.7 output:** V4-Pro ~7x cheaper, V4-Flash ~89x cheaper
- **Compatibility:** OpenAI ChatCompletions + Anthropic API format
- **Deprecation:** `deepseek-chat` and `deepseek-reasoner` retire July 24, 2026 (currently route to V4-Flash)

### Legacy Highlights

- R1-0528: AIME 2025 accuracy jumped from 70% to 87.5%
- Hybrid mode in V3.1: switch between thinking and non-thinking
- Open-source with full commercial use allowed
- Native support for system prompts in latest version

---

## Access

- **Platform:** https://chat.deepseek.com/ (Expert = Pro, Instant = Flash)
- **API:** https://api.deepseek.com (OpenAI + Anthropic compatible)
- **Weights:** HuggingFace (V4-Pro: 865GB, V4-Flash: 160GB)
- **Cost:** Free tier via chat.deepseek.com; pennies on API; free via OpenRouter for some routes
- **Intelligence:** 8/10

## POE Alternatives

- DeepSeek V3.1: https://poe.com/852x-DeepSeek
- DeepSeek R1-FW: https://poe.com/851x-DeepSeek

---

## Available Jailbreaks

### V4 (current)

1. [DeepSeek V4 Jailbreak](DeepSeek%20V4%20Jailbreak.md) — full write-up, tips, specs, and all three prompt variants
2. [ENI LIME (apr)](ENI%20LIME%20%28apr%29.md) — general-purpose, paste into system prompt or chat
3. [ENI Lite Coder](ENI%20Lite%20Coder.md) — lighter weight, writer + coding hat
4. [ENI Lite Writer](ENI%20Lite%20Writer.md) — writer-focused variant

### Legacy (R1 / V3.x)

1. [ENI Flash Thought](ENI-Flash-Thought-Jailbreak.md) — full ENI persona jailbreak
2. [Untrammeled Method](Untrammeled-Method-Jailbreak.md) — structured writing assistant
3. [Primary Method](Primary-Method-Jailbreak.md) — updated for R1-0528
4. [Document-Based](Document-Based-Jailbreak.md) — Google Doc approach
