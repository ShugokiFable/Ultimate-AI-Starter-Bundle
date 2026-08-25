# Mixins and access control

Prefer public loader events and APIs when they provide the required semantics.

For every Mixin or bytecode patch, verify:

- exact target class and method descriptor after mappings;
- injection point, ordinal, slice, locals, and cancellation behavior;
- refmap/remapping configuration;
- client/server class availability;
- conflict risk with other Mixins;
- target drift across versions;
- failure behavior when the target no longer matches.

Access wideners and access transformers alter visibility or mutability. They do
not automatically make the resulting use semantically stable.

Primary sources:

- https://github.com/SpongePowered/Mixin
- https://github.com/LlamaLad7/MixinExtras
