# Base Object Swapper 3.4.1 authority

Current documented sections are `[Forms]`, `[References]`, `[Transforms]`, and
`[Properties]`, including qualified variants.

Property functions use contiguous comma-separated arguments, for example:

```text
rotR(-90,0,0)
posR(10.0,5.0,50.0/100.0)
```

Whitespace inside a transform invocation is a known production failure shape in
the supplied runtime log. Both the general linter and the dedicated BOS auditor
must detect it.

Alphabetical priority determines the winning config, not whether its coordinates
or conditions are semantically correct.
