---
name: housecarl
description: Work with Skyrim Special Edition load-order records through the houseCARL MCP server — set or switch the MO2 instance, inspect active plugins and conflict trees, read records, query across plugins, author reviewable patch ESPs, create or remove records, and edit leveled lists or composed structs. Also the routing skill for the bundled Skyrim helpers (mutagen-reference, papyrus-reference, skypatcher-authoring, spid-authoring, kid-authoring). Use whenever the user mentions houseCARL, an MO2 modlist, plugins, load order, conflicts, ESP patches, overrides, a record type (ARMO/WEAP/NPC_/LVLI/MGEF/…), leveled lists, keywords, or a no-ESP runtime distribution — even when the task looks like a single edit, load this first to pick the right tool and read before you write.
---

# houseCARL

Use this skill for data-layer Skyrim Special Edition modding through the configured houseCARL MCP server. houseCARL reads a Mod Organizer 2 instance, resolves the true load-order winner, and writes changes into reviewable patch plugins; original source mods are never edited.

## Core workflow

1. Confirm context when it matters:
   - `housecarl_load_order_status` for profile/plugin status, or to check whether a mod or plugin is active.
   - `housecarl_set_mo2_instance` when the user gives a new MO2 instance folder.
2. Read before any record write:
   - `mutagen-reference` to verify field names, writability, enum values, and composed-struct shapes.
   - `housecarl_read_record` or `housecarl_batch_record_detail` to inspect the current winner. Add `conflict_tree=true` for contested records or when winner provenance matters.
   - `housecarl_cross_plugin_query` to locate records or references across the load order.
3. Pick the narrowest write tool:
   - `housecarl_set_field` for a single scalar or simple-collection edit.
   - `housecarl_bulk_apply` for several edits in one patch, dict merges, leveled-list entries, effects, or other composed structs.
   - `housecarl_create_record` for a new top-level record (it needs an EditorID).
   - `housecarl_remove_record` only to drop a record or override from a houseCARL-owned patch — never from a source mod.
4. Accumulate related edits into one patch with `into=<patch filename>` after the first write returns a patch name.
5. Prefer runtime, no-ESP INI systems when they fit the user's intent:
   - `skypatcher-authoring` for SkyPatcher record edits.
   - `spid-authoring` for distributing spells, perks, items, factions, outfits, or packages to NPCs.
   - `kid-authoring` for distributing keywords onto items.
6. `papyrus-reference` before answering any Papyrus or SKSE function-signature question.

## FormID notes

houseCARL tools use `XXXXXX:Plugin.esp` FormIDs — six hex digits, then the filename of the master that defines the record. SkyPatcher, SPID, and KID each use their own FormID syntax; consult their skills before writing INI lines.

## Safety notes

- houseCARL patches are reviewable output mods. Tell the user which patch was created or extended.
- Don't invent schemas or field paths. If `mutagen-reference` has no entry for a type, say so directly rather than guessing.
- Don't reach for record edits when the user explicitly wants a no-ESP / runtime distribution file — use SkyPatcher, SPID, or KID instead.

---

## V5 multi-provider + discovery (pack extension)

This skill originally targets Claude Code + houseCARL MCP. On **any** AI:

1. Load `tool-discovery` and confirm `housecarl-mcp` is FOUND **and** MCP tools are actually listed in the session.
2. If the binary exists but MCP tools are absent → tell the user to register MCP for **this** app and fully restart.
3. If neither binary nor MCP → recommend:

```text
INSTALL houseCARL:
1. Get the houseCARL distribution (houseCARL-Setup.exe + housecarl\ folder).
2. Install .NET 9 Runtime AND ASP.NET Core Runtime 9:
   https://dotnet.microsoft.com/download/dotnet/9.0
   winget install Microsoft.DotNet.Runtime.9
   winget install Microsoft.DotNet.AspNetCore.9
3. Run houseCARL-Setup.exe (quit AI apps first when updating).
4. Fully restart the AI application.
5. Set MO2 instance (folder containing ModOrganizer.ini).
6. Verify with a load-order question.
```

4. FormIDs for houseCARL tools: `XXXXXX:Plugin.esp` (six hex + defining master filename).
5. SkyPatcher / SPID / KID FormID dialects differ — use their authoring skills.
6. Always load `tool-output-awareness` before patch writes from conflict winners.
7. Prefer runtime INI frameworks when the user wants no-ESP distribution.
8. Codex users: a `codex\housecarl` stub may exist in the product zip; MCP is still required.
9. Grok users: add an MCP server block pointing at `housecarl-mcp.exe` in `.grok\config.toml`, then restart.

### Fallback without houseCARL

- Forge inspection jobs if available
- Spooky `esp info` / analyze on **owned** plugins only
- Manual xEdit findings **reported by the user** (agent does not launch GUI)
- Never invent load-order winners

---

## V5 automatic setup (MO2 + Vortex)

houseCARL **always** needs an MO2-shaped instance directory (folder containing `ModOrganizer.ini`).

| User's manager | Action |
|---|---|
| **Mod Organizer 2** | Point at the real instance folder |
| **Vortex** | Build a **shim** that looks like MO2 (junction `mods` → Vortex staging, copy/symlink `plugins.txt`) |

### Agent must run or recommend

```powershell
# From the V5 pack:
powershell -NoProfile -ExecutionPolicy Bypass -File "<PACK>\TOOLS\Setup-HouseCarl.ps1"
```

Also shipped beside this skill when installed from the pack:

```text
housecarl\scripts\Setup-HouseCarl.ps1
```

### Behavior of Setup-HouseCarl.ps1

1. Finds `housecarl-mcp.exe` (env, `%LOCALAPPDATA%\houseCARL`, Claude/Codex skill trees, optional tool vaults).
2. Checks .NET 9 + ASP.NET Core 9 runtimes.
3. **Auto** selects MO2 if `ModOrganizer.ini` instances exist; else **Vortex** if staging is found.
4. **MO2:** sets instance path.
5. **Vortex:** creates `%LOCALAPPDATA%\houseCARL-Shim` per `references/houseCARL-Vortex-shim-setup.pdf` (also in pack `TOOLS\housecarl\`).
6. Sets user env: `HOUSECARL_MCP`, `SKYRIM_MO2_INSTANCE`, `HouseCarl__Mo2InstanceDir`.
7. Wires Grok MCP block when present; writes Codex hint; writes `%LOCALAPPDATA%\houseCARL-data\v5-setup-state.json`.
8. User must **fully restart** the AI app.

### Refresh (Vortex)

After load-order or mod changes in Vortex (copy mode):

```powershell
.\Setup-HouseCarl.ps1 -RefreshOnly
```

### When MCP tools are missing mid-session

1. Run setup script (or recommend it).
2. Confirm state file exists.
3. Tell user to restart AI.
4. Do **not** invent load-order winners while MCP is down.

### Vortex caveats (do not hide these)

- `plugins.txt` order is authoritative.
- Generated `modlist.txt` loose-file priority is approximate (mtime).
- Patches land as `houseCARL - <name>` under staging — user must import into Vortex and **Deploy**.
- Parallel real MO2 is better if loose-file conflict authoring must be exact.

### Claude Code

Still prefer official `houseCARL-Setup.exe` for the plugin. Set plugin **MO2 instance folder** to the path printed by `Setup-HouseCarl.ps1` (real MO2 or shim).

---

## V5 AIO installer (pack)

New users and missing-tool recovery:

```powershell
# Pack root
.\INSTALL-V7-AIO.ps1
.\INSTALL-V7-AIO.ps1 -Mode OnlineLatest
.\TOOLS\Ensure-Tools.ps1
.\TOOLS\Update-From-GitHub.ps1
```

Offline snapshots live in `BUNDLED-TOOLS\offline\`. Component registry: `BUNDLED-TOOLS\CATALOG.json`.
After MCP changes the user must **fully restart** the AI application.
