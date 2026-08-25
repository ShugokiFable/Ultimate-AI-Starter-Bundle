# Multiloader / Architectury

Use multiloader only when the maintenance cost is justified.

## Decide

- shared game logic versus loader integration;
- common data/resources versus platform metadata;
- loader-specific networking, registries, attachments, events, and rendering;
- mapping and remapping strategy;
- dependency publication per platform;
- CI matrix and release naming;
- optional API adapters.

Architectury API can abstract many common calls, but it does not erase loader
lifecycle, mappings, packaging, or all API differences. Avoid a lowest-common-
denominator architecture that makes every feature worse.

Primary source:

- https://github.com/architectury/architectury-api
