# KID 4.0.6 parser authority

Pinned source commit: `895df224d4964dc9723460038eb533bfff06d860`.

An ordinary row is split into:

```text
Keyword target | Type | Filters | Traits | Chance
```

The parser reads only present positions, but it returns without registering the
row when `Type` remains `kNone`. `GetType` performs an exact lookup against the
human-readable type array. Consequently:

```text
Weapon       valid
Magic Effect valid
WEAP         invalid ordinary type
MGEF         invalid ordinary type
blank field  invalid ordinary type
```

KID `ExclusiveGroup` is a separate key with `GroupName|KeywordFormFilters`; it
must not be forced through ordinary Keyword-row validation.
