# LOOT automation

Forge separates analysis from application:

1. A version-pinned LOOT worker calculates a proposed order, messages, and Bash Tags.
2. Forge validates the worker result and materializes a `skyrim-forge-loot-plan/1` plan.
3. `loot_compare` reports movement, additions, and omissions.
4. `loot_apply` requires approval, writes a staged copy, backs up the selected profile file, and atomically replaces it.

Forge does not pretend the LOOT GUI is a full unattended CLI. The worker is a distinct integration component with its own executable hash and version pin.
