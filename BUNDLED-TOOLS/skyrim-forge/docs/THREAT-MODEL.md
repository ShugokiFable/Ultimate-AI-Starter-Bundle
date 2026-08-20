# Threat model

Primary threats include AI-invented command lines, shell injection, stale or replaced tool executables, live Data writes, path traversal, symlink escapes, archive bombs, unexpected dialogs, incomplete workers, missing completion markers, silent framework no-ops, and false claims of runtime validation.

Forge reduces these risks with typed jobs, allowlists, no-shell execution, executable hashes, path confinement, bounded archive handling, approval gates, receipts, and explicit evidence labels.
