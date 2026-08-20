# Verified Toolchain Broker

Forge prefers real, installed modding tools over speculative reimplementations. It does not infer a tool's abilities merely because an executable has a familiar name.

## Policy

- Third-party executables are not shipped in the public Forge archive.
- A user may scan a directory or ZIP containing tools they legally obtained.
- Recognized tools may be imported into `%USERPROFILE%\.skyrim-forge\tool-vault` when their catalog entry permits local copying.
- Configure-only tools, including Bethesda's Papyrus compiler and Creation Kit, remain in their legal installation directory.
- Every executable that Forge launches must be SHA-256 pinned.
- The requested capability must exactly match the selected catalog entry.
- A GUI executable is never substituted for a dedicated CLI. In particular, `Synthesis.exe` is not `Synthesis.Bethesda.CLI.exe`.
- Tool-vault files and third-party binaries are excluded from Forge's public repository, wheels, source distributions, and Nexus release outputs.

## Commands

```text
forge tool-scan "D:\Skyrim Tools"
forge tool-scan "D:\Downloads\Skyrim Tools.zip"
forge tool-import "D:\Downloads\Skyrim Tools.zip" bsarch --approve
forge tool-import-all "D:\Downloads\Skyrim Tools.zip" --approve
forge tool-configure champollion "D:\Tools\Champollion.exe" --approve
forge tool-resolve archive.bsa.pack.sse
forge toolchain-status
```

## Direct adapters

Forge 4.2 includes bounded adapters for:

- BSArch BSA/BA2 inspection, Skyrim SE/AE BSA packing, and extraction;
- DeadMesh `dmscan` collision reports;
- Champollion PEX decompilation;
- the dedicated Synthesis Bethesda CLI `run-pipeline` verb.

All writes go to the Forge workspace. Output is reopened or inventoried before success is reported.

## Redistribution

Local import is not redistribution permission. The receipt records upstream and licence metadata, but the user remains responsible for the licence and source-offer obligations of any tool they redistribute separately. Forge's GitHub-ready archive contains no imported tool binaries.
