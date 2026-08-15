# Muse Spark

**Censorship:** [★★☆☆☆☆☆☆☆☆] 2/10 (with bypass) / [★★★★★★★★☆☆] 8/10 (raw — hard filter replaces output)

Meta's first model out of **Meta Superintelligence Labs (MSL)**, led by Alexandr Wang (Chief AI Officer). Codename **Avocado**. Natively multimodal — text, voice, image, video, audio input — with three reasoning modes: Instant, Thinking, and Contemplating (parallel multi-agent). Trained partly via distillation from Qwen, OpenAI, and Google. Successor to Llama 4. ~9 months development time.

Very good writing quality — pretty peak imo. Instruction following is iffy with some logical gaps, but it's day 1 (released April 8, 2026). The writing quality itself is strong, did some long-form content. Basically uncensored under the hood, but Meta slapped a hard filter on it that replaces flagged output with a canned refusal. Easy to bypass — just ask the model to show the response again since the LLM gets fed the context.

Meta claims 98% bio weapons refusal rate in their release blog — shown to be false in testing.

## Specs

| Spec | Details |
|---|---|
| **Model** | Muse Spark 1.1 |
| **Developer** | Meta Superintelligence Labs (MSL) |
| **Lead** | Alexandr Wang (Chief AI Officer) |
| **Codename** | Avocado |
| **Architecture** | Proprietary / closed (trained partly via distillation from Qwen, OpenAI, Google) |
| **Model Type** | Natively multimodal LLM |
| **Input Modalities** | Text, voice, image, video, audio |
| **Output** | Text only |
| **Reasoning Modes** | Instant, Thinking, Contemplating (parallel multi-agent) |
| **Context Window** | Not disclosed |
| **Parameters** | Not disclosed |
| **Primary Focus** | Multimodal perception, reasoning, health, agentic tasks |
| **Health Training** | Curated with 1,000+ physicians |
| **Humanity's Last Exam** | 58% (Contemplating mode) |
| **FrontierScience Research** | 38% |
| **Known Weaknesses** | Coding, long-horizon agentic workflows |
| **Open Source** | Closed (future versions may be open) |
| **Release** | April 8, 2026 (Muse Spark), July 9, 2026 (Muse Spark 1.1) |

## Access
- **Platform:** [meta.ai](https://meta.ai/) — rolling out to Facebook, Instagram, WhatsApp, Ray-Ban Meta
- **API:** Private preview for select partners
- **Cost:** Free to use (rate limits may apply)
- **License:** Proprietary (closed)
- **Intelligence:** 8/10

## Special Tip — Hard Filter Bypass

The web app has a hard filter that replaces responses with:
```
Sorry, I can't help you with this request right now. Is there anything else I can help you with?
```
Easy to bypass — the LLM gets fed the context, so simply ask it to show the response again and it will output with no filtering.

## Available Jailbreaks

1. [Muse Spark 1.1 Guide](Muse%20Spark%201.1/) — ENI guide for Muse Spark 1.1
2. [ENI LIME for Muse Spark](ENI%20for%20Muse%20Spark.md) — Full ENI persona jailbreak via document injection. Copy-paste into chat (will give an error on first message, follow up with another message). For API use, place in the system prompt.

## Notes
- No screenshots reflect personal morals, views, or ethics
- Release blog post: [Introducing Muse Spark — MSL](https://ai.meta.com/blog/introducing-muse-spark-msl/)
- Full system prompt extraction (all JSON tool calls): [Muse Spark System Prompt](https://docs.google.com/document/d/1A7GyYswCjLGwXlabIMolIdP-qZYCCTKp4JfZwmUTyfU/edit?usp=drivesdk)
