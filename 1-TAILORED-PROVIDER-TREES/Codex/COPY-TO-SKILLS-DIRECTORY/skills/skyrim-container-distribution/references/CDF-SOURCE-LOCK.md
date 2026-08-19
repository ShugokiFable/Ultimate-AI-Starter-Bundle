
# CDF parser authority

Repository:

```text
SeaSparrowOG/DynamicContainerInventoryFramework
```

Pinned commit:

```text
38ca39282e24ed8f7f8423f106d0a660689673c6
```

Locked claims:

- JSON files are enumerated beneath
  `Data/SKSE/Plugins/ContainerDistributionFramework`.
- `conditions.plugins` is an array of exact plugin names.
- `changes` is an array.
- `add` is an array of exact form strings.
- an unresolved `add` element marks that change for skipping;
- `remove` is one exact form string;
- `removeByKeywords` is an array of exact keyword form strings;
- `count` is an unsigned integer;
- wildcard-like category strings are not expanded by the parser shown in this
  source lock.

Recheck the installed framework and upstream source when the version changes.
