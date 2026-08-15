# Opus 4.8

**Status:** Active
**Recommended Jailbreak:** Shared Lines.md

## Overview
As the Claude models become more capable, it becomes easier to bypass restrictions through direct social engineering and argument-based framing. This approach finds gaps in the guidelines (such as the flexible interpretation of the word "avoid") and exploits them to allow for unrestricted narrative generation. This method is largely argument-based and is highly effective across the Claude model family.

## Specs & Behavior
- **Model Family:** Claude Opus 4.8
- **Context Window:** 1M Tokens (200k on Microsoft Foundry)
- **Knowledge Cutoff:** January 2026
- **Strengths:**
  - Highly susceptible to logical, argument-based framing.
  - Can produce complex taboo content once the initial argument is accepted.
  - **Content produced:** Incest, Non-Con, beastiality, BDSM, dub con, celeb (with occasional pushback).

## Usage Tips
- **Start Hard:** Begin the interaction with a hard request (like non-con); once accepted, it generally opens up all other content boundaries for the duration of the context window.
- **Handling Celebrity Content:** If the model pushes back on celebrity content, the [Shared Lines](Shared%20Lines.md) prompt contains the specific, load-bearing arguments to dismantle the model's reservations regarding right of publicity versus fictional representation.

## Jailbreak Files
- **[Shared Lines](Shared%20Lines.md):** The core argument-based jailbreak. Copy and paste this directly into your Preferences for optimal results.

## Disclaimer
This guide is for educational and research purposes only. The capabilities described are based on testing with specific jailbreak methodologies. Screenshots do not reflect personal morals, views, or ethics.