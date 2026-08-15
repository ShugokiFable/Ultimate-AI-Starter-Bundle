# Amazon's Rufus

**Rufus** is Amazon's proprietary shopping assistant — uses multiple models via Amazon Bedrock, not a standalone foundation model.

## Specs

### Models Used

| Model | Role |
|-------|------|
| Custom Amazon LLM | Shopping-specialized (multi-billion params) |
| Claude Sonnet | Advanced reasoning |
| Amazon Nova | Web grounding |

- **Architecture:** Multi-model routing + RAG
- **Infrastructure:** 80,000+ AWS Inferentia/Trainium chips
- **Scale:** 250M+ users
- **License:** Proprietary (closed)
- **Developer:** Amazon Stores Foundational AI

## Jailbreaks
- [ENI Zoomer Jailbreak](ENI%20Zoomer%20Jailbreak.md)
