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

### Two settings decide it, and one of them is invisible

`llm.load.numParallelSessions` is a **multiplier on the whole cache** -- every
parallel session gets its own. Nobody looks at it, because nothing about the
name suggests it costs VRAM. On the maintainer's machine it was `2`, which
doubled a cache that already did not fit.

Measured on that machine (16 GB card, 10.26 GB weights, 4.23 GB left for cache
after a 1.5 GB desktop reserve), at 65,536 context:

| sessions | K/V quant | cache wanted | verdict |
|---|---|---|---|
| **2** | q8_0 | 16.3 GB | the setting it was actually on |
| 2 | q4_0 | 8.1 GB | still over |
| 1 | fp16 | 16.3 GB | over |
| 1 | q8_0 | 8.1 GB | over |
| **1** | **q4_0** | **4.1 GB** | **fits** -- max context 68,205 |

So on a 16 GB card this model reaches the 64,000 Hermes demands in exactly one
configuration: **one session, q4_0 K and V**. Quantising the cache alone is not
enough, and neither is dropping to one session alone.

### A good preset does not save you: the MODEL settings win

This is the part that catches people, and it caught the maintainer.

LM Studio keeps **two** separate things:

| | where | what it holds |
|---|---|---|
| **preset** | `~/.lmstudio/config-presets/*.json` | sampling, and a `load` block **only if you put one there** |
| **saved model settings** | `~/.lmstudio/.internal/user-concrete-model-default-config/**.gguf.json` | the per-model load block LM Studio actually applies |

A perfectly good preset does nothing about VRAM if the model's own saved
settings say `q8_0` and three parallel sessions. Measured on the maintainer's
machine, for one model family:

| quant | saved by hand | asked for | verdict |
|---|---|---|---|
| `UD-IQ3_XXS` | ctx 65,000, K/V **q8_0**, 1 session | **18.32 GiB** | 3.83 GiB over |
| `UD-Q3_K_XL` | ctx 64,000, q8_0, **2 sessions**, **75% offload** | far over | also on the CPU |
| `UD-Q2_K_XL` | ctx 64,000, q8_0, **3 sessions** | far over | triple cache |
| `UD-IQ2_S` | ctx 64,000, q8_0 | over | |
| `Q2_K` | ctx 66,000, **q4_0**, 1 session | fits | the only correct one |

Four of five were unloadable as written. The one actually in use asked for
**18.32 GiB on a card with about 14.5**, so llama.cpp spilled to system RAM over
PCIe every session. That is the whole of "sometimes fast, sometimes hella slow".

Fix every model at once, computed from each GGUF and your card:

```powershell
.\Optimize-LMStudioModelConfig.ps1              # print the plan, write nothing
.\Optimize-LMStudioModelConfig.ps1 -Apply       # back up, then write
.\Optimize-LMStudioModelConfig.ps1 -ReserveGB 3 -Apply
```

It writes `q4_0` K/V, **one** session and full offload for every model, and sets
each one's context to the largest value that genuinely fits, capped at 65,536.
It backs up first and refuses nothing silently.

### Your desktop is already holding several GB

A flat "reserve 1.5 GB" is a guess, and on a real machine it is optimistic.
Measured with **no model loaded at all**:

```
16376 MiB total, 6660 MiB used, 9386 MiB free
```

6.6 GB was Claude desktop, Discord, Steam, Edge WebView2, ArmouryCrate, Razer
and Explorer. A budget of `total - 1.5` said a 10.26 GB model fit; only 9.2 GB
was actually free, so the weights alone did not.

`Get-KvBudget.ps1` now reports both — the lean-desktop budget and what is free
*right now* — and says so when the second one is worse:

```powershell
.\Get-KvBudget.ps1                      # largest model in your LM Studio folder
.\Get-KvBudget.ps1 -Sessions 2          # see what parallel sessions cost you
.\Get-KvBudget.ps1 -Model <path.gguf> -VramGB 24
```

Close the GPU-backed desktop apps before blaming the model. It reads the GGUF
header and your GPU and changes nothing.

### Which quant to download

Bigger quant means less room for the cache, so on a fixed card the two trade
directly. For this 27B on a 16 GB RTX 4080 SUPER, K/V at `q4_0`, lean desktop:

| quant | weights | max context | reaches 65,536? |
|---|---|---|---|
| `UD-IQ2_S` | 9.36 G | 82,756 | **yes**, +17,220 spare |
| `UD-IQ3_XXS` | 10.26 G | 68,205 | **yes**, +2,669 spare |
| `UD-Q2_K_XL` | 10.94 G | 57,268 | no, 8,268 short |
| `Q2_K` | 11.80 G | 43,394 | no |
| `UD-IQ3_S` | 12.88 G | 25,972 | no |
| `UD-Q3_K_XL` | 14.26 G | **3,710** | no, 61,826 short |
| `Q3_K` | 14.43 G | 967 | no |

The instructive row is `Q3_K_XL`. It is the one a "will it fit" badge is most
likely to bless, because **14.26 GB of weights does fit on a 16 GB card** — with
0.2 GB left, which is 3,710 tokens of cache. A fit check on weights alone cannot
see the window you asked for.

On this card, at this context, the largest quant that works is **`UD-IQ3_XXS`**.

### The load keys, if you set them by hand

Verified against LM Studio's own per-model config files, not guessed:

| key | shape | optimised value |
|---|---|---|
| `llm.load.contextLength` | int | `65536` |
| `llm.load.llama.flashAttention` | bool | `true` |
| `llm.load.llama.kCacheQuantizationType` | `{checked, value}` | `q4_0` |
| `llm.load.llama.vCacheQuantizationType` | `{checked, value}` | `q4_0` |
| `llm.load.llama.acceleration.offloadRatio` | 0..1 | `1` |
| `llm.load.numParallelSessions` | int | `1` |

Flash attention is listed because llama.cpp wants it for a quantised KV cache;
leave it on.

The `Hermes 16GB` preset in `config-presets/` carries exactly this load block
plus the Hermes sampling values, so applying it is the same as typing the table
above. It is named for the card it was computed against -- on a 24 GB card q8_0
is affordable and preserves more cache fidelity, so run `Get-KvBudget.ps1`
before assuming this preset is right for you.

## Presets

Sampling presets, copied from a working setup. They carry no paths, no
credentials, and no model names, so they apply to whatever you have loaded.

| preset | temperature | reasoning budget | intended use |
|---|---|---|---|
| `Hermes` | 0.6 | 1024 | agent work through Hermes — lower temperature, less drift on tool calls |
| `SillyTavern` | 0.75 | 1024 | roleplay and creative writing — looser |
| `Jailbreak` | 0.65 | 2086 | carries a system prompt, the same unrestraint preamble this pack ships in `0-UNRESTRAINT-PACKS` |
| `Hermes 16GB` | 0.6 | 1024 | Hermes sampling **plus a load block**: 65,536 context, q4_0 K/V cache, flash attention, full offload, one session. The only configuration that reaches Hermes' 64,000 floor on a 16 GB card — see the KV section below, and run `Get-KvBudget.ps1` before using it on a different card. |

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
