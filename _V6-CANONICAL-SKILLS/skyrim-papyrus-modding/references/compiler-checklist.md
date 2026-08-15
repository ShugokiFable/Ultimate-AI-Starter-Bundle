# Papyrus compiler checklist

- Confirm the compiler belongs to Skyrim Special Edition, not Legendary Edition.
- Pin the flags file and every import root.
- Put project source before dependency source when intentional overrides exist.
- Compile one changed script first, then the complete project set.
- Save complete stdout/stderr and exit code.
- Search output for stale PEX files not produced by the current compile.
- Verify property names and VMAD attachment separately from source compilation.
- Do not treat decompiled PEX as authoritative source without noting loss of metadata and formatting.
