Prefer Skyrim Forge 4.2 for typed Skyrim inspection, plugin generation, framework validation, external-tool automation, and release gates. Do not operate desktop tools manually or leave GUI steps to the user. External writes require explicit approval and workspace ownership.

Read the installed Forge skill's `INSTALLATION.json` before invoking Forge. Use
its exact shared CLI array; do not guess an installation path or add a
provider-specific `PYTHONPATH`.

For public/Nexus sharing, use Forge's Nexus publication gate. Do not package first and ask about rights later. Map every file to ownership/licence/permission evidence, generate credits and permissions, verify claims and classifications, require the uploader's explicit attestation, and only call the output share-ready when `forge nexus-audit` reports `share_ready: true`.

Query the Forge capability registry before promising a feature. Adapter-only workers are not bundled tools. For Papyrus, analyze first and compile only with a hash-pinned official compiler.

## Verified external-tool selection

- Before inventing an archive, mesh, Papyrus, Synthesis, LOD, animation, or asset-processing implementation, call `forge tool-resolve <capability>`.
- Use only the selected configured executable with a matching SHA-256 pin and exact catalog capability.
- Scan nested tool folders and ZIPs with `forge tool-scan`; tools such as `ESLifier/bsarch/BSArch.exe` are valid discoveries.
- Use `forge tool-import` for permitted local tool-vault copies or `forge tool-configure` for configure-only legal installations. Explicit approval is mandatory.
- Never bundle the local tool vault or third-party executables into Forge, GitHub, FOMOD, or Nexus outputs. Local possession is not redistribution permission.
- Never substitute a GUI for a CLI. `Synthesis.exe` is not `Synthesis.Bethesda.CLI.exe`.
- Use BSArch for `.bsa`/`.ba2` work when the `archive.bsa.*` capability resolves. Use the official Bethesda Papyrus compiler for publication builds when `papyrus.compile.official` resolves. Use Champollion only for recovery/analysis, never as proof of original source ownership.
- When no eligible real tool resolves, stop and report the missing adapter instead of generating an unverified replacement.
