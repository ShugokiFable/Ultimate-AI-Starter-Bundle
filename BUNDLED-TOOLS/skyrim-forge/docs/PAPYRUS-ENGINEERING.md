# Papyrus engineering

Forge separates source analysis from compilation.

Source analysis checks case-insensitive `ScriptName` identity, filename agreement, duplicate scripts, inheritance cycles and conflicting import roots. Performance diagnostics are intentionally heuristic warnings. Forge never rewrites Papyrus merely because a pattern looks expensive.

Compilation requires a hash-pinned Bethesda Papyrus compiler, a flags file and explicit import order. Release compilation uses `-optimize` by default, writes to a transaction directory, requires a fresh non-empty PEX for every source, and installs the complete batch with rollback protection. The build manifest hashes compiler, flags, sources and outputs.

Compiler success does not prove event lifecycle correctness, save compatibility, latency, or runtime load. Those require Papyrus logs and in-game testing.
