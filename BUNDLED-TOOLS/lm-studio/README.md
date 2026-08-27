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

## "Sometimes fast, sometimes hella slow" is the KV cache

If a local model is quick in a fresh chat and collapses later in the same
conversation, nothing else has grabbed the GPU. The KV cache grew past VRAM and
started spilling to system RAM over PCIe. It is the conversation itself.

Work out the cliff before blaming anything else. Read the geometry from the
GGUF header, never from the model card:

```
KV bytes/token = block_count x head_count_kv x (key_length + value_length) x bytes_per_element
```

`bytes_per_element` is 2 at fp16, 1 at Q8_0, ~0.5 at Q4_0.

Measured on the maintainer's machine 2026-08-26 --
`Huihui-Qwen3.8-27B-abliterated-UD-IQ3_XXS`, RTX 4080 SUPER (15.99 GB):

| field | value |
|---|---|
| `block_count` | 65 |
| `head_count_kv` | 4 |
| `key_length` / `value_length` | 256 / 256 |
| KV at fp16 | **266,240 bytes/token = 0.254 MB** |
| weights on disk | 10.26 GB |

That geometry is unusually KV-hungry: `key_length` 256 is double the common
128, so this model costs twice the cache of a same-size model with 128.

| context | KV @ fp16 | + weights | verdict on 16 GB |
|---|---|---|---|
| 20,000 | 5.1 GB | 15.4 GB | fits, barely |
| 55,000 | 13.6 GB | 23.9 GB | spills |
| 64,000 | 17.0 GB | 27.3 GB | exceeds the card before weights |

So on this card the fp16 cliff is around **20k tokens**, and the 64,000 floor
Hermes enforces is **not reachable at fp16 with a 27B**. The two constraints
genuinely conflict, and quantising the cache is what resolves it:

| KV quant | bytes/token | 64,000 ctx | + 10.26 GB weights |
|---|---|---|---|
| fp16 | 266,240 | 17.0 GB | 27.3 GB -- impossible |
| Q8_0 | 133,120 | 8.5 GB | 18.8 GB -- still over |
| Q4_0 | ~66,560 | 4.3 GB | 14.5 GB -- **fits**, ~1.5 GB spare |

Enable KV cache quantisation in LM Studio's model-load settings. Q4_0 K/V is
what makes a 27B usable at the context Hermes requires on a 16 GB card; Q8_0
is enough if you stay near 20-30k. The alternative is a smaller model: weights
under ~8 GB leave room for a Q8 cache at 64k.

Check the real numbers for YOUR model rather than reusing these -- the geometry
varies enormously between models, and `key_length` is the field that surprises
people.

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
