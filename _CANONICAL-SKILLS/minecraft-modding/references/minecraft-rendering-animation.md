# Rendering and animation

Verify the target rendering pipeline, mappings, loader hooks, render thread,
resource reload behavior, model format, texture paths, and dedicated-server
separation.

For GeckoLib or another animation library, pin the exact major version and
loader artifact. Major API generations are not interchangeable.

Validate:

- static and animated models;
- item/block/entity render contexts;
- armor and layer renderers;
- interpolation and partial tick behavior;
- resource-pack overrides;
- shader/mod compatibility;
- client-only loading.

Primary source:

- https://github.com/bernie-g/geckolib
- https://github.com/bernie-g/geckolib/wiki
