# LM Studio presets and settings

Optional. Nothing here is touched by `START-HERE.bat` — LM Studio is a desktop
app with its own config, and an installer that silently rewrites it would be
the same class of mistake this pack spends its time fixing elsewhere.

Copy the presets with `Install-LMStudio-Presets.ps1`, or by hand.

## The one setting that actually breaks things

**Set LM Studio's context length to 65,536.**

Hermes refuses any model whose window is under **64,000 tokens** and raises at
startup — a hard `ValueError` before the first turn, not a warning. The floor
is a strict `<` against 64,000, and LM Studio's context field takes powers of
two, so 65,536 is the first setting that clears it.

Measured on the maintainer's machine 2026-08-26: LM Studio's
`defaultContextLength` was `{"type": "max", "value": 55000}`. That is below the
floor, so every local model it loaded was one Hermes would not accept.

Confirm it stuck by loading with **no** explicit context flag — the loaded
context LM Studio reports must be the new value. Loading once by hand with
`-c 65536` proves nothing, because a cold start uses the saved default and that
is what Hermes' preload picks up.

See the `local-model-ops` skill for the rest: VRAM budget, KV arithmetic, and
why a stale model id fails soft into `fallback_providers` instead of erroring.

## Presets

Sampling presets, copied from a working setup. They carry no paths, no
credentials, and no model names, so they apply to whatever you have loaded.

| preset | temperature | reasoning budget | intended use |
|---|---|---|---|
| `Hermes` | 0.6 | 1024 | agent work through Hermes — lower temperature, less drift on tool calls |
| `SillyTavern` | 0.75 | 1024 | roleplay and creative writing — looser |
| `Jailbreak` | 0.65 | 2086 | carries a system prompt, the same unrestraint preamble this pack ships in `0-UNRESTRAINT-PACKS` |

All three share `topKSampling: 20`, `minPSampling: 0` (checked), and
`repeatPenalty` **off**. Those are the Qwen3-family sampling recommendations;
repeat penalty in particular tends to hurt more than it helps on models that
already handle repetition through their own sampling.

Install them:

```powershell
.\Install-LMStudio-Presets.ps1            # copy, never overwrite
.\Install-LMStudio-Presets.ps1 -Force     # overwrite presets of the same name
.\Install-LMStudio-Presets.ps1 -WhatIf    # show what would be copied
```

They land in `%USERPROFILE%\.lmstudio\config-presets\` and appear in LM
Studio's preset dropdown after a restart.

## What is deliberately NOT shipped

`settings.json` is **not** in this folder, and should not be copied between
machines. The real one contains:

- `downloadsFolder` — an absolute path with a username in it,
- `hfSearchToken` / `hfDownloadToken` — Hugging Face credential fields,
- `cloudInference.billingContext` — an account detail,
- `dismissedModals`, `pre030ChatsMigrated` and similar per-install bookkeeping.

Set the handful of values that matter in the LM Studio UI instead:

| setting | value | why |
|---|---|---|
| context length | **65,536** | below 64,000 Hermes will not start (see above) |
| `Local Server` port | 1234 | the default every provider in this pack expects |
| model loading guardrails | your call | `high` refuses loads it predicts will not fit; useful on a tight VRAM budget, annoying when you know better |

## Wiring LM Studio to a provider

That is not done here — the pack's `local-model-ops` skill covers it, and
Hermes treats `lmstudio` as a first-class provider needing no credential. Two
rules from that skill worth repeating, because both were live bugs on the
maintainer's machine:

- **Read the model id from the server, never from the filename.** `/v1/models`
  reports `huihui-qwen3.8-27b-abliterated`; the file is
  `...@q2_k_xl`. The suffix is not part of the id, and an id that does not
  resolve fails soft into `fallback_providers` — the symptom is "local is
  slow", never an error.
- **Do not write a `models:` block under the provider.** A dict-shaped one
  merges alongside `discover_models` instead of narrowing it, and the model
  lists twice the moment LM Studio loads it.
