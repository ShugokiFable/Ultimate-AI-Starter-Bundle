# FOMOD engineering

Forge 5.0.0 treats FOMOD installers as typed build artifacts, not hand-written XML fragments.

## Supported ModuleConfig 5.0 surface

The typed plan and validator cover the standard bounded XML installer surface defined by the pinned ModuleConfig schema:

- module title placement and colour;
- module image path, visibility, fade, and height;
- module dependencies;
- required files and folders;
- configurable install-step, group, and plugin ordering;
- UTF-8 and UTF-16 XML output;
- conditional step visibility;
- every standard group selection type;
- ordered plugins;
- descriptions and option images;
- file and folder mappings;
- `alwaysInstall`, `installIfUsable`, and priority;
- condition flags;
- static and dependency-driven option types;
- nested AND/OR dependencies;
- active, inactive, and missing file dependencies;
- condition-flag dependencies;
- game and FOMM version dependencies;
- conditional file installs;
- `info.xml` name, author, display version, machine version, description, website, ID, category ID, and groups.

Forge intentionally rejects C# scripted FOMOD installers. Those scripts can execute arbitrary code and do not fit the typed, bounded safety model. "Complete FOMOD support" therefore means the complete standard XML surface that can be represented safely, not arbitrary executable installer code.

The implementation is source-locked to `references/FOMOD-SOURCE-LOCK.json`, including the exact upstream `ModuleConfig.xsd` blob used to derive element order, attributes, defaults, and enumerations. Forge performs an equivalent pinned schema-shape and semantic validation with the Python standard library. It does not claim that an external XSD engine ran unless one is separately configured and reported.

## Commands

Create an install-everything starter plan:

```text
forge fomod-scaffold <PayloadRoot> <Workspace>/fomod.plan.json --module-name "My Mod" --module-version 1.0.0 --approve
```

Validate the edited plan and prove every payload file is mapped:

```text
forge fomod-plan-validate <Workspace>/fomod.plan.json --source-root <PayloadRoot>
```

Simulate selections without launching Vortex or MO2:

```text
forge fomod-simulate <Workspace>/fomod.plan.json --selections selections.json --state environment.json --source-root <PayloadRoot>
```

Build the installer tree transactionally:

```text
forge fomod-build <Workspace>/fomod.plan.json <PayloadRoot> <Workspace>/BuiltFomod --approve
```

Validate an existing installer:

```text
forge fomod-validate <BuiltFomod>
```

Use `--allow-unreferenced` only when a package intentionally contains payload files that no installer branch installs. Forge defaults to rejecting that state because it commonly means an option or entire feature was lost during a rebuild.

## Branch simulation files

Selections use `Step name/Group name` keys:

```json
{
  "Visual Options/Texture": "High Resolution",
  "Compatibility/Patches": ["Lux", "JK's Skyrim"]
}
```

Environment state can supply file states and versions:

```json
{
  "files": {
    "Lux.esp": "Active",
    "JKs Skyrim.esp": "Inactive",
    "Missing Requirement.esp": "Missing"
  },
  "game_version": "1.6.1170.0",
  "fomm_version": "0.0.0.0"
}
```

Condition flags are produced by selected plugins and evaluated in step order. A step's visibility and dynamic option types may consume only flags defined by earlier steps. Conditional file installs run after the step sequence and may consume flags produced anywhere in that sequence.

An explicit empty `files` array is supported for informational or flag-only options and emits `<files/>`. Omitting both `files` and `flags` is rejected because the plugin node would not select either schema branch. Existing `info.xml` metadata is optional according to the ecosystem documentation, so missing Name or Version is reported as a warning rather than a false format failure. Forge-generated installers always include both.

## Validation gates

Forge checks:

- the canonical ModuleConfig 5.0 schema-location token;
- pinned XSD element ordering and permitted attributes;

- XML parsing and root elements;
- ModuleConfig element ordering;
- unknown or duplicate top-level sections;
- group, plugin, and type-descriptor structure;
- empty `files` and `conditionFlags` elements;
- unsafe, absolute, and traversal paths;
- missing source files and folders;
- missing option and module images;
- undefined condition flags;
- selection-group constraints;
- unreachable or unusable explicit selections;
- payload files omitted from every branch;
- destination collisions, including whether options are mutually exclusive or priority resolves the overwrite;
- deterministic generated XML;
- complete reopen validation after generation.

`forge release-validate` automatically invokes the strict FOMOD gate whenever a release root contains a `fomod` directory.

## Evidence boundary

A Forge PASS proves the XML and payload model are internally coherent against the pinned standard XML format. It does not prove that every Vortex or MO2 presentation detail looks ideal, that a manager-specific extension behaves identically, or that arbitrary C# installer code is safe. The final archive still needs one actual installation in Vortex and one in MO2 when it uses complex conditional branches.
