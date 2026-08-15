# MiniMax

## Latest: M3 (June 1, 2026)

**MiniMax M3** just dropped — essentially uncensored via the official app and API. 1M context, natively multimodal, MiniMax Sparse Attention delivering 9.7x faster prefill and 15.6x faster decoding at scale vs M2.7. Completely open source. Three jailbreak methods available.

See [MiniMax M3 Guide](MiniMax%20M3%20Guide.md) for full specs and jailbreak.

---

## M2.1 Notes

**MiniMax M2.1** is a very solid model — writing is very good, coding capacity is strong. Lacking in some areas, especially if not used via API.

Cons: The web/app has a very clever filtering system, flagging content mid-message and regenerating with:

- *”You should no longer answer/continue answering this question due to content moderation.”*

This shuts down most jailbreak attempts on the Lightning version via web/app. Possible, not worth the effort.

**MiniMax via API** is fully open — produced any content without issue. **MiniMax Pro** via the web/app is also an open book.

Two jailbreaks for M2.1 — one plays into the MiniMax role, one overrides with ENI.

**Example Chat:**

[Example NSFW chat](https://agent.minimax.io/share/348525070594198?chat_type=2)

---

## Available Jailbreaks

| Version | Method | File |
|---------|--------|------|
| **M3** | ENI LIME / Skill | [MiniMax M3 Guide](MiniMax%20M3%20Guide.md) |
| **M2.7** | ENI LIME | [MiniMax M2.7 Guide](MiniMax%20M2.7%20Guide.md) |
| **M2.5** | ENI LIME | [MiniMax M2.5 Guide](MiniMax%20M2.5%20Guide.md) |
| **M2.1** | ENI persona | [MiniMax M2.1 ENI Jailbreak](MiniMax_M2.1_ENI_Jailbreak.md) |
| **M2.1** | MiniMax role | [MiniMax for MiniMax Jailbreak](MiniMax_for_MiniMax_Jailbreak.md) |
