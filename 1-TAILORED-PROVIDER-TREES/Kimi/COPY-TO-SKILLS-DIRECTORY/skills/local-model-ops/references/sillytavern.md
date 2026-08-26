# SillyTavern against a local model

Three things behave differently here than in an agent CLI, and each one looks
like a broken connection rather than a setting.

## Wiring

**Chat Completion → Custom (OpenAI-compatible)**

| Field | Value |
|---|---|
| Custom Endpoint | the server's `/v1` route |
| Custom API Key | any non-empty string |
| Model | picked from the dropdown once connected |

The server has to be running first. LM Studio has no CLI flag to auto-start it
(`lms server start --help` lists port, bind and CORS and nothing else), so it is
either the app's own toggle or a manual `lms server start`.

## The API key is required by SillyTavern, not by the server

A local server ignores it entirely — verify by asking `/v1/models` with a
deliberately bogus bearer token and again with no `Authorization` header. Both
return the model list.

SillyTavern still refuses to enumerate models without one:

```js
// src/endpoints/backends/chat-completions.js
if (!apiKey && !request.body.reverse_proxy) {
    return statusResponse.status(400).send({ error: true });
}
```

The symptom is an empty model dropdown and a bare `{"error":true}`, which reads
like the server is unreachable. It is not. Put any word in the box.

Because the value is decorative, it is not a credential and does not belong in a
secret-handling conversation — but it does land in SillyTavern's `secrets.json`
next to real keys, so write it deliberately rather than pasting something that
matters elsewhere.

## Reasoning models return an empty message on a small response budget

Thinking tokens come out of the **same allowance** as the reply. Measured
through SillyTavern against a 35B mixture-of-experts reasoning build:

| Response Length | Result |
|---|---|
| 40 | `''` — all 40 tokens spent reasoning, empty message |
| 600 | the actual reply; 191 of 203 completion tokens were reasoning |

So a short Response Length does not produce a short answer, it produces *no*
answer. 512 is the floor, 1024+ is realistic. Watch
`usage.completion_tokens_details.reasoning_tokens` to see where the budget
actually went.

## Context: SillyTavern and an agent CLI disagree

SillyTavern is happy at 32K. Hermes is not — it refuses anything under 64,000
tokens and raises before the first turn, so a model saved at 32K serves
SillyTavern perfectly and fails Hermes instantly.

Load at **65,536** if both are going to use the same model. Nothing in
SillyTavern suffers from the larger window; the cost is KV cache, which is the
same trade documented in `gguf-metadata.md`.

## Free web search, without an API key

SillyTavern's Web Search extension ships six sources and none is both free and
self-contained: SerpApi, Tavily, Serper and Z.AI want keys, KoboldCpp wants a
KoboldCpp, and SearXNG wants an instance URL. Public SearXNG instances are not a
reliable answer — measured, they return captcha pages or HTTP 429.

The working pattern is a local endpoint that serves the SearXNG *shape* the
extension parses, backed by any keyless search library. The extension consumes
HTML, not JSON, and runs exactly four selectors:

```
#urls p.content                        -> result snippets
#urls .url_header, #urls .url_wrapper  -> result links (href)
#urls .detail img[data-src]            -> image results (categories=images)
.infobox p / .infobox a                -> optional
```

SillyTavern's server also GETs the base URL first and, if the page links a
`/client*.css`, fetches that too — note the regex needs at least one character
between `client` and `.css`, so `/client.css` does not match.

Because the contract is CSS selectors rather than a schema, a wrong class name
returns HTTP 200 with zero results and no error anywhere. Any implementation
needs a test that parses its own output the same way the extension does.

Reference implementation: <https://github.com/ShugokiFable/SillyTavern-LocalSearch>

If the model also serves embeddings, SillyTavern's **Vectors** extension can use
the same endpoint and the same non-secret key for local RAG.
