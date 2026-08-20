# xEdit automation

Forge 3.0 uses fixed Pascal scripts and constructs xEdit arguments itself. The user should not need to click through SSEEdit for routine checks.

Supported built-in workflow:

```text
forge automation-run automation-xedit-check.job.json
```

The adapter uses the configured SSEEdit executable, `-sse`, `-quickedit:<plugin>`, `-autoload`, `-script:<approved-script>`, `-autoexit`, and `-nobuildrefs` for the read-only check operation.

A result is complete only when Forge finds the script marker:

```text
SKYRIM_FORGE_CHECK_ERRORS errors=<n> records=<n>
```

The GUI process may briefly appear because xEdit remains a Windows application. No user interaction is expected. An unexpected dialog or missing marker blocks the job.

Generic AI-generated Pascal is not accepted. Extra scripts require an explicit SHA-256 allowlist.
