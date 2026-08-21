---
name: secret-hygiene
description: Use when handling API keys, tokens, cookies, credentials, private URLs, environment files, logs, reports, or release artifacts.
---

# Secret Hygiene

## Core rule
A **secret** should exist only where required, for only as long as required, and never enter generated artifacts or logs by accident.

## Contract
- Read **credential** values from established secret stores/environment/config mechanisms rather than hardcoding.
- Never echo full tokens or authorization headers.
- **Redact** logs, error payloads, screenshots, diagnostics, and saved reports.
- Exclude `.env`, credential stores, auth caches, browser profiles, and machine-specific install state from release archives.
- Before publication, scan staged artifacts for common secret patterns and unexpected private files.
- Preserve file permissions where the platform supports them.

## Prove presence, never value

Most secret leaks in diagnostics come from an honest question: "is the variable actually set?" Answer it without printing it.

```
TOKEN = SET            GITHUB_TOKEN present (40 chars, sha256 3f9a…)
TOKEN = sk-live-9f…    <- never
```

Presence, length and a short hash are enough to distinguish unset, empty, wrong-length and stale. The same applies to headers, cookies, connection strings and full environment dumps: report the key, never the value. When a value genuinely must be compared, compare hashes.

Screenshots and rendered output count as logs. A captured UI can contain a token in a field, a URL bar or a devtools panel -- redact before saving or sharing.

Do not “sanitize” by replacing a secret in one obvious file while leaving it in Git history, generated logs, or copied config backups. If exposure occurred, removal is not revocation—rotate the credential.
