# Native source lock

Forge native project generation is pinned to the CommonLibSSE-NG CMake contract and vcpkg registry baselines in `references/NATIVE-SOURCE-LOCK.json`.

A generated project is not a finished DLL mod. Publication requires:

1. A hash-pinned build toolchain.
2. A successful clean build into Forge staging.
3. PE x64 DLL inspection.
4. Runtime launch on every declared Skyrim/SKSE target.
5. SKSE log and crash-log review.
6. Coexistence testing with relevant native hooks.
7. Nexus rights, source, licence, and third-party-notice review.

Forge refuses to infer compatibility from compilation alone.
