---
name: upgrade-path-testing
description: Use when a release, installer, schema, configuration, or tool must work for both new users and users upgrading from an older version.
---

# Upgrade Path Testing

A **fresh install** and an **upgrade** are different products. Prove both.

## Contract

Test at least:

1. empty profile → current version;
2. previous version (supported) → current version;
3. partially configured previous install → current version;
4. rerun current installer over current version.

For upgrades, preserve user-owned configuration, credentials, caches worth retaining, project data, and unrelated files. Replace only bundle-owned state. Validate migrations before deleting old data and keep rollback/backup material until the new state passes its doctor.

Compare the post-upgrade effective configuration with a fresh install plus the user's intentional customizations. A successful fresh install does not prove the upgrade path.
