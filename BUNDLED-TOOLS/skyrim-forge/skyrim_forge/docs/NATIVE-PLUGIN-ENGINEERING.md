# Native SKSE plugin engineering

Forge generates a source-locked CommonLibSSE-NG project and requires one explicit compatibility strategy:

- Address Library
- signature scanning
- an explicit runtime-version list

The generated CMake project refuses to deploy unless `FORGE_OUTPUT_ROOT` points to a staging directory. It does not write to live Skyrim `Data`.

`native-audit` checks the CommonLib target, lifecycle entry point, runtime strategy and staging rule. `native-binary-audit` checks x86-64 PE32+ DLL structure. `native-build` requires hash-pinned CMake and vcpkg executables and builds inside the Forge workspace.

A successful compilation and PE audit are not proof that a hook is correct, that offsets are current, or that the DLL coexists with another SKSE plugin. Those require a matching runtime, logs, crash testing and gameplay evidence.
