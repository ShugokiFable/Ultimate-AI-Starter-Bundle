# Reading a GGUF header

The label on a quant ("35B-A3B", "Q4_K_M", "128K") is marketing. The header is
fact. Everything needed to size a local model is in the first few kilobytes of
the file, and reading it costs nothing.

## Parser

Metadata sits at the start of the file: magic, version, tensor count, KV count,
then `n_kv` typed key/value pairs. Values are little-endian; type 9 is an array
of a nested type, type 8 is a length-prefixed UTF-8 string.

```python
import struct

TYPES = {0:'<B',1:'<b',2:'<H',3:'<h',4:'<I',5:'<i',6:'<f',7:'<?',10:'<Q',11:'<q',12:'<d'}

def read_gguf_metadata(path):
    f = open(path, 'rb')
    assert f.read(4) == b'GGUF', 'not a GGUF file'
    version, = struct.unpack('<I', f.read(4))
    n_tensors, n_kv = struct.unpack('<QQ', f.read(16))

    def rstr():
        n, = struct.unpack('<Q', f.read(8))
        return f.read(n).decode('utf-8', errors='replace')

    def rval(t):
        if t == 8:
            return rstr()
        if t == 9:
            et, = struct.unpack('<I', f.read(4))
            ln, = struct.unpack('<Q', f.read(8))
            return [rval(et) for _ in range(ln)]
        fmt = TYPES[t]
        return struct.unpack(fmt, f.read(struct.calcsize(fmt)))[0]

    out = {'_version': version, '_n_tensors': n_tensors}
    for _ in range(n_kv):
        k = rstr()
        t, = struct.unpack('<I', f.read(4))
        out[k] = rval(t)
    return out
```

Print only what matters — a chat template alone can be tens of kilobytes:

```python
md = read_gguf_metadata(path)
arch = md['general.architecture']
for k in ('context_length', 'block_count', 'attention.head_count_kv',
          'attention.key_length', 'attention.value_length',
          'expert_count', 'expert_used_count'):
    print('%-28s %s' % (k, md.get('%s.%s' % (arch, k))))
```

## What each field decides

| Field | Decides |
|---|---|
| `<arch>.context_length` | The model's real ceiling. A server loaded well under it is a choice, not a limit. |
| `<arch>.block_count` | Layer count — the multiplier on every per-layer cost. |
| `<arch>.attention.head_count_kv` | KV heads. Grouped-query models have far fewer of these than attention heads, and it is this number that sets cache size. |
| `<arch>.attention.key_length` / `value_length` | Per-head K and V width. |
| `<arch>.expert_count` / `expert_used_count` | Mixture-of-experts shape. A model with few experts used per token stays fast even when most weights sit in system RAM. |
| `general.file_type` | Quantization enum. 15 is `Q4_K_M`, 18 is `Q6_K`, 7 is `Q8_0`. |

## KV cache arithmetic

Per token, per layer, the cache holds one K and one V entry for every KV head:

```
elements_per_token = 2 * block_count * head_count_kv * key_length
```

Multiply by bytes per element for the cache quantization — 2 for `f16`, and
about 1.06 for `q8_0` (a 32-value block plus one 16-bit scale is 34 bytes).

Worked example, a 40-layer model with 2 KV heads and 256-wide keys:

```
2 * 40 * 2 * 256            = 40,960 elements/token
40,960 * 1.06 (q8_0)        ~ 43 KB/token
```

| Context | KV at q8_0 | KV at f16 |
|---|---|---|
| 32K | ~1.4 GB | ~2.7 GB |
| 64K | ~2.7 GB | ~5.4 GB |
| 128K | ~5.4 GB | ~10.9 GB |

Read that against free VRAM **after** weights. Quantizing the cache to `q8_0`
is almost always the right first move: it halves the largest variable cost in
the budget and is far less damaging than halving the context.

## Two traps

**Do not size from the loader's estimator.** LM Studio's `--estimate-only`
reports the same figure at 32K, 64K and 128K and labels itself
`Confidence: LOW` — it models weights, not the cache. Load the model and read
actual VRAM instead.

**Measure VRAM while generating, not at idle.** A freshly loaded model can
report a couple of gigabytes below its working peak because cache pages are
not touched until tokens flow.
