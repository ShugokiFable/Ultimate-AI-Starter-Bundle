# Capability matrix

Forge distinguishes evidence levels so an AI cannot turn a configured adapter into a false claim of implementation.

| Capability | Level | Status | Boundary |
|---|---|---|---|
| Verified local toolchain | Direct/Profiled | Implemented | Recursive directory/ZIP discovery, private vault import, SHA-256 pins, exact capability match; no public binary bundling |
| BSArch BSA/BA2 | Direct | Implemented | Official BSArch contract for inspect/unpack/SSE pack; configured executable required |
| Champollion/Synthesis CLI/DeadMesh CLI | Adapter | Implemented | Exact executable identity and hash pin required; GUI substitutes rejected |
| Plugin header/query | Direct | Implemented | Forge parser evidence, not xEdit/runtime |
| Typed KYWD/GLOB/FLST/OTFT output | Direct | Implemented | No arbitrary record writing |
| SPID/KID/BOS/SkyPatcher/FLM lint/build | Profiled | Implemented | Modeled source-locked subsets; unknown syntax is unverified, not rewritten |
| Papyrus analysis | Profiled | Implemented | Performance findings are review heuristics |
| Papyrus compile | Adapter | Implemented | Pinned official compiler; fresh PEX is not runtime proof |
| CommonLibSSE-NG scaffold | Profiled | Implemented | Source-locked project generation |
| Native build | Adapter | Implemented | Pinned local build tools; workspace staging only |
| FOMOD XML | Profiled | Implemented | Declarative ModuleConfig only; arbitrary C# blocked |
| xEdit/MO2 | Adapter | Implemented | Installed pinned tools required |
| CK/Wrye/LOOT/Synthesis/assets/animations/LOD | Worker contract | Adapter only | Compatible pinned worker required |
| Nexus publication | Human gate | Implemented | Machine evidence plus uploader attestation; not legal authentication |
| Skyrim runtime/visual/save/gameplay | Human gate | Required | Must be tested in the game |
| Generic navmesh/worldspace/landscape binary editing | Unsupported | Blocked | Specialist editor and human verification required |
