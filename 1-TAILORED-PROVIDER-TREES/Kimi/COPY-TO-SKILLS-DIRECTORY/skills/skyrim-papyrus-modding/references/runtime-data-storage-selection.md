# Runtime data storage selection

| Need | Prefer |
|---|---|
| Menu settings persistent across characters/install | MCM Helper ModSettings |
| Save-specific scalar state | Papyrus properties, globals, or verified storage API |
| Simple JSON/key-value persistence | PapyrusUtil |
| Nested maps/arrays/dynamic structures | JContainers |
| High-frequency native state | Purpose-built SKSE/CommonLib storage with explicit serialization |

Do not add both PapyrusUtil and JContainers without a concrete reason. Define migration and uninstall behavior.
