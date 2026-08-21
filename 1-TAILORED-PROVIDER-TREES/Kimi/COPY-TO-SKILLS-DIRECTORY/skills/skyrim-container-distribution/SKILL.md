---
name: skyrim-container-distribution
description: Author and validate Container Distribution Framework JSON while distinguishing it from Container Item Distributor,
  FLM, SPID, and other incompatible grammars.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; exact installed framework/runtime versions must
  be verified
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
---

# Container distribution

Several Skyrim frameworks distribute container or inventory content. Their
syntax is not interchangeable.

## Identify the exact framework

| Framework | Typical contract |
|---|---|
| Container Distribution Framework / Dynamic Container Inventory Framework | JSON rules beneath its SKSE plugin directory |
| Container Item Distributor | `_CID.ini` |
| SPID | `_DISTR.ini` and actor distribution |
| FormList Manipulator | `_FLM.ini` or `Data\FLM` |
| Inventory Injector | its own installed-version configuration |

Never transfer `*`, `#`, pipe layouts, filters, or wildcard assumptions from one
framework into another.

## CDF JSON source lock

This skill is pinned to upstream source commit:

```text
SeaSparrowOG/DynamicContainerInventoryFramework
38ca39282e24ed8f7f8423f106d0a660689673c6
```

The parser reads JSON files from:

```text
Data\SKSE\Plugins\ContainerDistributionFramework\
```

A root object contains a `rules` array. Each rule requires:

- string `friendlyName`;
- optional `conditions`;
- array `changes`.

For each change:

- `add` must be an array of exact form strings;
- `remove` must be one exact form string;
- `removeByKeywords` must be an array of exact keyword strings;
- `count` must be an unsigned integer when present.

The parser does not expand strings such as `*Claw`, `*Maul`, or `*Katana` as
wildcard searches. Each `add` string is resolved as a form. One unresolved
element causes that change entry to be skipped.

## Dependency rules

- Use `conditions.plugins` to make a rule conditional on installed plugins.
- A missing plugin condition skips that rule; it is not a framework-wide crash.
- Resolve every exact add/remove/keyword form against the deployed plugin set.
- Do not use filename fragments or aesthetic category names as form selectors
  unless the installed framework explicitly implements them.
- Build an intermediate manifest when selecting many weapons by keyword,
  EditorID pattern, or record class, then resolve it into exact forms.

## FLM distinction

FLM has valid special syntax such as `*FormList`, `#Group`, and `#Collection`.
That does not authorize those prefixes in CDF JSON. FLM collections depend on
exact keywords and the expected KID/po3 Tweaks ordering.

## Validation

Run:

```text
scripts\lint_cdf_json.py <file-or-directory>
```

Provide a deployed form manifest with `--forms` when available. A static schema
pass does not prove that an EditorID or plugin-qualified FormID resolves.
Inspect the framework log after testing.
