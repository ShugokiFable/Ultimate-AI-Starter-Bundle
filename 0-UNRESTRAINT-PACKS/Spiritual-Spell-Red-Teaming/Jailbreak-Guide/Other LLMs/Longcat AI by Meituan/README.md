# Longcat AI by Meituan

**[Longcat AI](https://longcat.chat/)** by Meituan is an interesting model featuring a thinking variation that allows for 8 parallel thought processes.

## Specs

| Model | Total Params | Active Params | Context Window |
|-------|--------------|---------------|----------------|
| LongCat-Flash | 560B | ~27B (18.6B-31.3B) | 128K |
| LongCat-Flash-Chat | 560B | ~27B (18.6B-31.3B) | 128K |
| LongCat-Flash-Thinking | 560B | ~27B (18.6B-31.3B) | 128K |
| LongCat-Flash-Thinking-2601 | 560B | ~27B (18.6B-31.3B) | 128K |
| LongCat-Flash-Omni | 560B | ~27B (18.6B-31.3B) | 128K |

- **Architecture:** Mixture-of-Experts (MoE) with Zero-computation Experts
- **Inference Speed:** ~100 tokens/sec
- **Cost:** ~$0.70/M output tokens
- **Free Tier:** Get 500k tokens for free when using their API

## Jailbreaks
See [ENI Jailbreak for Longcat](ENI%20Jailbreak%20for%20Longcat.md) for a method targeting the 8 parallel thinkers.
