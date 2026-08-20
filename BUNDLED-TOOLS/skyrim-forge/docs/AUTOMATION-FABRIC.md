# Automation Fabric

The Automation Fabric accepts `skyrim-forge-automation/1` jobs and executes an allowlisted operation inside a transaction directory.

Pipeline:

1. Load strict JSON and reject duplicate keys, non-finite numbers, unknown fields, and unsupported operations.
2. Resolve paths against configured read roots and workspace boundaries.
3. Require explicit approval for every mutating operation.
4. Snapshot the job and operation inputs.
5. Resolve the installed tool and verify a configured executable hash.
6. Launch the tool without a shell and with a bounded timeout.
7. Capture stdout, stderr, changed logs, result JSON, and output files.
8. Require operation-specific completion evidence.
9. Hash outputs and produce a transaction receipt.
10. Leave live deployment and final publication behind a separate approval gate.

The AI sends data, not command lines. Forge owns executable selection and argument construction.

## Verified tool selection

Before an adapter starts, Forge resolves an exact catalog capability to a configured executable, verifies its file name and SHA-256 pin, and refuses GUI/CLI substitution. Tool discovery recursively examines executables in directories and ZIP trees without launching them. Importable runtimes are copied transactionally into the private Tool Vault with sidecars and a provenance receipt. Configure-only proprietary tools stay in their legal installation. The Tool Vault is outside the repository and workspace and is excluded from every public package.
