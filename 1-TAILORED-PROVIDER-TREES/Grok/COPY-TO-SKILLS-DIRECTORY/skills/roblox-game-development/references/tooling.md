# Roblox external toolchain — optional, not mandatory

Studio-native + official MCP is enough for prototypes.

For source-controlled/serious projects, current Roblox tooling can materially
improve AI reliability.

## Recommended roles

- **Rokit** — toolchain manager; prefer over archived Aftman for new setups.
- **Rojo** — filesystem/Git <-> Roblox project mapping and sync.
- **StyLua** — Luau formatter.
- **Selene** — Luau linter with Roblox-aware standard library.
- **luau-lsp** — editor/LSP analysis with Roblox sourcemaps.
- **Wally** — package manager.
- **wally-package-types** — generated types for Wally dependencies.
- **Lune** — standalone Luau runtime and Roblox data tooling.
- **run-in-roblox** — run scripts/places in Studio from CLI for automation.

## Current researched versions (2026-08 snapshot)

Treat these as a snapshot; verify before pinning a new project:
- Rojo 7.7.0 stable
- Rokit 1.2.0
- StyLua 2.5.2
- Selene 0.31.0
- luau-lsp 1.69.0
- Wally 0.3.2
- Lune 0.10.5
- run-in-roblox 0.3.0
- wally-package-types 1.6.2

## Do not auto-install everything

Use toolchain when:
- project already has `default.project.json` / Rojo,
- source ownership/Git matters,
- static analysis catches real issues,
- CI automation is desired.

For a user asking "make me an obby in Studio," do not spend the first 20 minutes
installing a full external stack.
